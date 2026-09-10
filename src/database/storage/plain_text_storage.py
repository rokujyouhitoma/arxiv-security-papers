#!/usr/bin/env python3
"""
src/database/storage/plain_text_storage.py

File-Backed PlainText / Markdown Virtual Storage Engine.
Conforms to DSN-05 Section 21.6, zero-external-dependency rule, and STRIDE security model.
"""

from __future__ import annotations

import fnmatch
import os
import tempfile
from collections import OrderedDict
from datetime import datetime, timezone
from typing import Any, Dict, Iterator, List, Mapping, Optional


class PlainTextStorageError(Exception):
    """Base error for plain text storage."""

    pass


class PlainTextSecurityError(PlainTextStorageError):
    """Raised when file operations violate security boundaries."""

    pass


def _is_safe_under_dir(path: str, base_dir: str) -> bool:
    try:
        return os.path.commonpath([path, base_dir]) == base_dir or path.startswith(
            base_dir
        )
    except ValueError:
        return False


def _parse_tag_values(v: str) -> List[str]:
    res: List[str] = []
    for t in v.split(","):
        clean = t.strip().strip("'\"[]")
        if clean:
            res.append(clean)
    return res


def _handle_tags_key(v: str, meta: Dict[str, Any], tags_list: List[str]) -> bool:
    if v:
        tags_list.extend(_parse_tag_values(v))
    meta["tags"] = tags_list
    return True


def _handle_tag_bullet(stripped: str, in_tags: bool, tags_list: List[str]) -> bool:
    if stripped.startswith("- ") and in_tags:
        tags_list.append(stripped[2:].strip().strip("'\""))
        return True
    return False


def _handle_kv_pair(stripped: str, meta: Dict[str, Any], tags_list: List[str]) -> bool:
    if ":" not in stripped:
        return False
    key, val = stripped.split(":", 1)
    k, v = key.strip(), val.strip().strip("'\"")
    if k == "tags":
        return _handle_tags_key(v, meta, tags_list)
    meta[k] = v
    return False


def _process_frontmatter_line(
    line: str, in_tags: bool, meta: Dict[str, Any], tags_list: List[str]
) -> bool:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return in_tags
    if _handle_tag_bullet(stripped, in_tags, tags_list):
        return True
    return _handle_kv_pair(stripped, meta, tags_list)


def _parse_yaml_frontmatter_light(raw_header: str) -> Dict[str, Any]:
    """Lightweight pure-Python YAML frontmatter parser for OKF documents."""
    meta: Dict[str, Any] = {}
    in_tags = False
    tags_list: List[str] = []

    for line in raw_header.splitlines():
        in_tags = _process_frontmatter_line(line, in_tags, meta, tags_list)

    if tags_list and "tags" not in meta:
        meta["tags"] = tags_list
    return meta


class LazyRecordDict(Mapping[str, Any]):
    """Proxy mapping that lazy-loads frontmatter and heavy text columns on demand."""

    def __init__(
        self,
        base_meta: Dict[str, Any],
        storage: FileBackedPlainTextStorage,
    ) -> None:
        self._base = base_meta
        self._storage = storage
        self._header_loaded = "title" in base_meta
        self._resolved_heavy: Dict[str, str] = {}

    def _ensure_header(self) -> None:
        if not self._header_loaded:
            self._storage.load_header_for_record(self._base)
            self._header_loaded = True

    def __getitem__(self, key: str) -> Any:
        if key in ("body_markdown", "raw_text", "raw_abstract"):
            if key in self._resolved_heavy:
                return self._resolved_heavy[key]
            val = self._storage.read_heavy_column(
                str(self._base.get("clean_id", "")), key
            )
            self._resolved_heavy[key] = val
            return val

        self._ensure_header()
        if key in self._base:
            return self._base[key]
        raise KeyError(key)

    def __iter__(self) -> Iterator[str]:
        self._ensure_header()
        keys = list(self._base.keys())
        for k in ("body_markdown", "raw_text", "raw_abstract"):
            if k not in keys:
                keys.append(k)
        return iter(keys)

    def __len__(self) -> int:
        self._ensure_header()
        return len(self._base) + 3

    def get(self, key: str, default: Any = None) -> Any:
        try:
            return self[key]
        except KeyError:
            return default

    def to_dict(self) -> Dict[str, Any]:
        """Materializes all fields including heavy text columns into a pure dict."""
        self._ensure_header()
        res = dict(self._base)
        for k in ("body_markdown", "raw_text", "raw_abstract"):
            res[k] = self[k]
        return res


class FileBackedPlainTextStorage:
    """Virtual Table Storage directly mounting physical plaintext/markdown files."""

    MAX_FILE_SIZE = 20 * 1024 * 1024  # 20MB DoS mitigation
    LRU_CACHE_CAPACITY = 500

    def __init__(
        self,
        root_dir: Optional[str] = None,
        file_patterns: Optional[List[str]] = None,
        workspace_dir: Optional[str] = None,
    ) -> None:
        self._custom_workspace = workspace_dir is not None
        self.workspace_dir = os.path.realpath(
            os.path.abspath(
                workspace_dir or os.environ.get("WORKSPACE_DIR", os.getcwd())
            )
        )
        target_dir = root_dir or os.path.join(
            self.workspace_dir, "outputs", "okf_papers"
        )
        self.root_dir = os.path.realpath(os.path.abspath(target_dir))
        self._verify_workspace_boundary(self.root_dir)

        self.patterns = file_patterns or ["*.md", "*.txt"]
        self._meta_index: Dict[str, Dict[str, Any]] = {}
        self._content_cache: OrderedDict[str, str] = OrderedDict()
        self.dim = 0  # Compatibility with VectorStorage interface
        self._scan_and_index()

    def _verify_workspace_boundary(self, path: str) -> None:
        norm_path = os.path.realpath(os.path.abspath(path))
        if _is_safe_under_dir(norm_path, self.workspace_dir):
            return

        if not self._custom_workspace:
            tmp_dir = os.path.realpath(os.path.abspath(tempfile.gettempdir()))
            if _is_safe_under_dir(norm_path, tmp_dir):
                return

        raise PlainTextSecurityError(
            f"Path '{path}' violates workspace boundary '{self.workspace_dir}'"
        )

    def _scan_and_index(self) -> None:
        """Discovers files and indexes lightweight metadata without loading entire contents."""
        self._meta_index.clear()
        if not os.path.exists(self.root_dir):
            return

        for root, _, files in os.walk(self.root_dir):
            for fname in files:
                if self._matches_pattern(fname):
                    fpath = os.path.join(root, fname)
                    self._index_single_file(fpath, fname)

    def _matches_pattern(self, filename: str) -> bool:
        return any(fnmatch.fnmatch(filename, pat) for pat in self.patterns)

    def _index_single_file(self, fpath: str, fname: str) -> None:
        try:
            stat = os.stat(fpath)
        except OSError:
            return

        if stat.st_size > self.MAX_FILE_SIZE:
            return

        rel_path = os.path.relpath(fpath, self.workspace_dir)
        clean_id = os.path.splitext(fname)[0]
        mtime_iso = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat()

        # Fast lazy index: store lightweight paths without opening file
        self._meta_index[clean_id] = {
            "id": clean_id,
            "clean_id": clean_id,
            "arxiv_id": clean_id.replace("_", "."),
            "file_path": rel_path,
            "file_size_bytes": stat.st_size,
            "updated_at": mtime_iso,
        }

    def load_header_for_record(self, meta: Dict[str, Any]) -> None:
        """Loads frontmatter or header on demand when fields are accessed."""
        clean_id = str(meta.get("clean_id", ""))
        rel_path = str(meta.get("file_path", ""))
        full_path = os.path.join(self.workspace_dir, rel_path)
        frontmatter_dict: Dict[str, Any] = {}
        try:
            with open(full_path, "r", encoding="utf-8", errors="replace") as f:
                header = f.read(4096)
                if header.startswith("---"):
                    parts = header.split("---", 2)
                    if len(parts) >= 3:
                        frontmatter_dict = _parse_yaml_frontmatter_light(parts[1])
        except OSError:
            pass

        if "arxiv_id" in frontmatter_dict:
            meta["arxiv_id"] = str(frontmatter_dict["arxiv_id"])
        meta["title"] = str(frontmatter_dict.get("title", clean_id))
        meta["description"] = str(frontmatter_dict.get("description", ""))
        meta["tags"] = frontmatter_dict.get("tags", ["security-paper"])
        meta["provenance"] = frontmatter_dict.get("provenance", {})
        meta["trust"] = frontmatter_dict.get("trust", {})

    def read_heavy_column(self, clean_id: str, col_name: str) -> str:
        """Reads heavy content (body_markdown, raw_text, raw_abstract) with LRU caching."""
        cache_key = f"{clean_id}:{col_name}"
        if cache_key in self._content_cache:
            self._content_cache.move_to_end(cache_key)
            return self._content_cache[cache_key]

        meta = self._meta_index.get(clean_id)
        if not meta:
            return ""

        content = self._read_file_content(meta["file_path"], col_name)
        self._add_to_lru_cache(cache_key, content)
        return content

    def _add_to_lru_cache(self, key: str, value: str) -> None:
        if len(self._content_cache) >= self.LRU_CACHE_CAPACITY:
            self._content_cache.popitem(last=False)
        self._content_cache[key] = value

    def _read_file_content(self, rel_path: str, col_name: str) -> str:
        full_path = os.path.join(self.workspace_dir, rel_path)
        self._verify_workspace_boundary(full_path)
        try:
            with open(full_path, "r", encoding="utf-8", errors="replace") as f:
                full_text = f.read(self.MAX_FILE_SIZE)
        except OSError:
            return ""

        if col_name == "body_markdown" and full_text.startswith("---"):
            parts = full_text.split("---", 2)
            if len(parts) >= 3:
                return parts[2].strip()
        return full_text.strip()

    @property
    def count(self) -> int:
        return len(self._meta_index)

    @property
    def metadata(self) -> List[Any]:
        """Returns lazy records compatible with executor TableCatalog.storage.metadata interface."""
        return [LazyRecordDict(base, self) for base in self._meta_index.values()]

    def get_by_pk(self, clean_id: str) -> Optional[Dict[str, Any]]:
        """Fast O(1) lookup by primary key."""
        base = self._meta_index.get(clean_id)
        if not base:
            return None
        return LazyRecordDict(base, self).to_dict()

    def get_all_vectors(self) -> List[List[float]]:
        """VectorStorage compatibility stub."""
        return []
