#!/usr/bin/env python3
"""
src/database/storage/factory.py

Storage Engine Factory & Dynamic Engine Discovery.
Conforms to DSN-05 Section 21.7, zero-external-dependency rule, and STRIDE security model.
"""

from __future__ import annotations

import os
import tempfile
from typing import Any, Callable, Dict, Optional

from .json_storage import JsonLinesStorage, JsonTableStorage
from .multi_storage import MultiTableVectorStorage
from .storage import VectorStorage


class StorageFactoryError(Exception):
    """Base error for storage factory operations."""

    pass


class StorageSecurityError(StorageFactoryError):
    """Raised when a file path violates workspace security boundaries."""

    pass


_EXT_MAP = {
    ".vdb": "binary_vdb",
    ".jsonl": "json_lines",
    ".json": "json_table",
    ".md": "file_plain_text",
    ".txt": "file_plain_text",
}


def _is_within_root(path: str, root: str) -> bool:
    try:
        return os.path.commonpath([path, root]) == root or path.startswith(root)
    except ValueError:
        return False


def _get_allowed_roots(workspace_dir: Optional[str]) -> list[str]:
    if workspace_dir:
        return [os.path.realpath(os.path.abspath(workspace_dir))]
    ws = os.path.realpath(os.path.abspath(os.environ.get("WORKSPACE_DIR", os.getcwd())))
    tmp = os.path.realpath(os.path.abspath(tempfile.gettempdir()))
    return [ws, tmp]


def _validate_safe_workspace_path(
    path: str, workspace_dir: Optional[str] = None
) -> str:
    """Validates that the target path does not escape workspace boundary."""
    resolved = os.path.realpath(os.path.abspath(path))
    roots = _get_allowed_roots(workspace_dir)
    if any(_is_within_root(resolved, root) for root in roots):
        return resolved
    raise StorageSecurityError(
        f"Access denied: path '{path}' escapes workspace boundary"
    )


def _detect_engine_by_extension(norm_path: str) -> str:
    """Helper to detect engine type from path extension or directory check."""
    _, ext = os.path.splitext(norm_path)
    if ext in _EXT_MAP:
        return _EXT_MAP[ext]
    if os.path.isdir(norm_path):
        return "file_plain_text"
    return "unknown"


def _is_multi_vdb_file(path: str) -> bool:
    if not os.path.exists(path) or os.path.isdir(path):
        return False
    try:
        with open(path, "rb") as f:
            return f.read(8) == b"OKFMTC01"
    except OSError:
        return False


class StorageEngineFactory:
    """Pluggable Storage Engine Factory for URI auto-detection and DDL USING clauses."""

    _registry: Dict[str, Callable[..., Any]] = {}
    _initialized: bool = False

    @classmethod
    def _ensure_builtins(cls) -> None:
        """Lazily registers built-in storage engines."""
        if cls._initialized:
            return

        cls._registry["binary_vdb"] = cls._create_binary_vdb
        cls._registry["multi_vdb"] = cls._create_binary_vdb
        cls._registry["json_lines"] = cls._create_json_lines
        cls._registry["json_table"] = cls._create_json_table
        cls._registry["file_plain_text"] = cls._create_plain_text
        cls._initialized = True

    @staticmethod
    def _create_plain_text(location: Optional[str], **kwargs: Any) -> Any:
        from .plain_text_storage import FileBackedPlainTextStorage

        kw = dict(kwargs)
        ws = kw.pop("workspace_dir", None)
        kw.pop("dim", None)
        kw.pop("table_name", None)
        return FileBackedPlainTextStorage(root_dir=location, workspace_dir=ws, **kw)

    @staticmethod
    def _resolve_multi_vdb_table(
        container: MultiTableVectorStorage, tbl_name: Optional[Any]
    ) -> Any:
        if tbl_name and container.has_table(str(tbl_name)):
            return container.get_table(str(tbl_name))
        return container

    @staticmethod
    def _create_binary_vdb(location: Optional[str], **kwargs: Any) -> Any:
        loc = location or "default.vdb"
        dim = int(kwargs.get("dim", 128))
        tbl_name = kwargs.get("table_name")
        if _is_multi_vdb_file(loc) or "multi" in kwargs:
            container = MultiTableVectorStorage(loc)
            return StorageEngineFactory._resolve_multi_vdb_table(container, tbl_name)
        return VectorStorage(file_path=loc, dim=dim)

    @staticmethod
    def _create_json_lines(location: Optional[str], **kwargs: Any) -> Any:
        loc = location or "data.jsonl"
        return JsonLinesStorage(file_path=loc)

    @staticmethod
    def _create_json_table(location: Optional[str], **kwargs: Any) -> Any:
        loc = location or "catalog.json"
        pk = str(kwargs.get("primary_key", kwargs.get("pk_field", "id")))
        return JsonTableStorage(file_path=loc, primary_key=pk)

    @classmethod
    def register_engine(cls, name: str, factory_fn: Callable[..., Any]) -> None:
        """Registers a custom storage engine factory callable."""
        cls._ensure_builtins()
        cls._registry[name.lower()] = factory_fn

    @classmethod
    def create_by_engine_name(
        cls,
        engine_name: str,
        location: Optional[str] = None,
        workspace_dir: Optional[str] = None,
        **kwargs: Any,
    ) -> Any:
        """Instantiates a storage engine by explicit engine identifier (e.g. from DDL USING)."""
        cls._ensure_builtins()
        clean_name = engine_name.strip().lower()
        if clean_name not in cls._registry:
            valid_names = ", ".join(sorted(cls._registry.keys()))
            raise StorageFactoryError(
                f"Unknown storage engine: '{engine_name}'. Supported engines: [{valid_names}]"
            )

        safe_loc = None
        if location:
            safe_loc = _validate_safe_workspace_path(location, workspace_dir)

        factory_fn = cls._registry[clean_name]
        return factory_fn(safe_loc, **kwargs)

    @classmethod
    def create_from_uri(
        cls, uri_or_path: str, workspace_dir: Optional[str] = None, **kwargs: Any
    ) -> Any:
        """Auto-detects engine type from URI/path extension and instantiates storage engine."""
        cls._ensure_builtins()
        clean_path = uri_or_path.strip()
        safe_path = _validate_safe_workspace_path(clean_path, workspace_dir)
        engine_type = _detect_engine_by_extension(safe_path)

        if engine_type == "unknown":
            raise StorageFactoryError(
                f"Cannot determine storage engine for URI/path: '{uri_or_path}'"
            )

        return cls.create_by_engine_name(
            engine_type, location=safe_path, workspace_dir=workspace_dir, **kwargs
        )
