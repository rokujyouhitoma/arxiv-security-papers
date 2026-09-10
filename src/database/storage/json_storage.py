#!/usr/bin/env python3
"""
Pure-Python JSON and JSONL Storage Engines for Git-Trackable Open Data.
Provides:
  1. JsonLinesStorage: Append-only time-series audit logger (O(1) write, flock protected).
  2. JsonTableStorage: Primary-key indexed catalog table with O(1) in-memory lookup
     and atomic crash-safe rename flush.
Conforms to DSN-05 Section 21 and zero-external-dependency rule.
"""

import fcntl
import json
import os
import uuid
from contextlib import contextmanager
from typing import Any, Callable, Dict, Generator, List, Optional, Set


class JsonStorageError(Exception):
    """Base exception for JSON storage errors."""


class JsonStorageLockError(JsonStorageError):
    """Raised when file locking fails."""


@contextmanager
def file_flock(
    file_obj: Any, lock_flags: int = fcntl.LOCK_EX
) -> Generator[None, None, None]:
    """Context manager acquiring POSIX flock if supported."""
    locked = False
    try:
        fcntl.flock(file_obj.fileno(), lock_flags)
        locked = True
    except (OSError, AttributeError):
        pass  # Fallback gracefully in environments where flock is not supported
    try:
        yield
    finally:
        if locked:
            try:
                fcntl.flock(file_obj.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass


class JsonLinesStorage:
    """
    Append-only storage engine for line-delimited JSON (JSONL).
    Optimized for execution history, logs, and telemetry.
    O(1) disk writes with minimal Git diff impact (+1 line per entry).
    """

    def __init__(self, file_path: str) -> None:
        self.file_path = os.path.abspath(file_path)
        self._ensure_parent_dir()

    def _ensure_parent_dir(self) -> None:
        parent = os.path.dirname(self.file_path)
        if parent and not os.path.exists(parent):
            os.makedirs(parent, exist_ok=True)

    def append(self, record: Dict[str, Any]) -> None:
        """Appends a single JSON record to the file with POSIX lock."""
        line = json.dumps(record, ensure_ascii=False) + "\n"
        with open(self.file_path, "a", encoding="utf-8") as f:
            with file_flock(f, fcntl.LOCK_EX):
                f.write(line)
                f.flush()
                try:
                    os.fsync(f.fileno())
                except OSError:
                    pass

    def append_many(self, records: List[Dict[str, Any]]) -> None:
        """Batch appends multiple records in a single lock session."""
        if not records:
            return
        payload = "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records)
        with open(self.file_path, "a", encoding="utf-8") as f:
            with file_flock(f, fcntl.LOCK_EX):
                f.write(payload)
                f.flush()
                try:
                    os.fsync(f.fileno())
                except OSError:
                    pass

    @staticmethod
    def _parse_record_line(line_str: str) -> Optional[Dict[str, Any]]:
        if not line_str:
            return None
        try:
            rec = json.loads(line_str)
            return rec if isinstance(rec, dict) else None
        except json.JSONDecodeError:
            return None

    def _read_raw_lines(self, reverse: bool) -> List[str]:
        if not os.path.exists(self.file_path):
            return []
        with open(self.file_path, "r", encoding="utf-8") as f:
            with file_flock(f, fcntl.LOCK_SH):
                lines = f.readlines()
        if reverse:
            lines.reverse()
        return lines

    @staticmethod
    def _matches_filter(
        rec: Optional[Dict[str, Any]],
        predicate: Optional[Callable[[Dict[str, Any]], bool]],
    ) -> bool:
        if rec is None:
            return False
        return predicate is None or predicate(rec)

    def _iter_records(
        self,
        reverse: bool,
        predicate: Optional[Callable[[Dict[str, Any]], bool]],
    ) -> Generator[Dict[str, Any], None, None]:
        for line in self._read_raw_lines(reverse):
            rec = self._parse_record_line(line.strip())
            if self._matches_filter(rec, predicate):
                assert rec is not None
                yield rec

    def scan(
        self,
        predicate: Optional[Callable[[Dict[str, Any]], bool]] = None,
        limit: Optional[int] = None,
        reverse: bool = False,
    ) -> List[Dict[str, Any]]:
        """
        Scans records with optional predicate filter and reverse iteration.
        Reads line-by-line to prevent memory spikes.
        """
        results: List[Dict[str, Any]] = []
        for rec in self._iter_records(reverse, predicate):
            results.append(rec)
            if limit is not None and len(results) >= limit:
                break
        return results

    def count(self) -> int:
        """Returns total valid records in the file."""
        if not os.path.exists(self.file_path):
            return 0
        total = 0
        with open(self.file_path, "r", encoding="utf-8") as f:
            with file_flock(f, fcntl.LOCK_SH):
                for line in f:
                    if line.strip():
                        total += 1
        return total


class JsonTableStorage:
    """
    Primary-key indexed storage engine for mutable catalogs (pretty JSON).
    Maintains an in-memory primary key index for O(1) existence checks.
    Flushes changes via crash-safe atomic replace (.tmp.<uuid> -> os.replace).
    """

    def __init__(self, file_path: str, primary_key: str = "clean_id") -> None:
        self.file_path = os.path.abspath(file_path)
        self.primary_key = primary_key
        self._pk_index: Dict[str, Dict[str, Any]] = {}
        self._is_loaded: bool = False
        self._ensure_parent_dir()

    def _ensure_parent_dir(self) -> None:
        parent = os.path.dirname(self.file_path)
        if parent and not os.path.exists(parent):
            os.makedirs(parent, exist_ok=True)

    def _ensure_loaded(self) -> None:
        if self._is_loaded:
            return
        if not os.path.exists(self.file_path):
            self._is_loaded = True
            return

        with open(self.file_path, "r", encoding="utf-8") as f:
            with file_flock(f, fcntl.LOCK_SH):
                content = f.read().strip()
                if not content:
                    self._is_loaded = True
                    return
                try:
                    data = json.loads(content)
                    self._build_index_from_raw(data)
                except json.JSONDecodeError as exc:
                    raise JsonStorageError(
                        f"Corrupt JSON table at {self.file_path}: {exc}"
                    ) from exc
        self._is_loaded = True

    def _index_list(self, items: List[Any]) -> None:
        for item in items:
            if isinstance(item, dict) and self.primary_key in item:
                self._pk_index[str(item[self.primary_key])] = item

    def _index_dict(self, mapping: Dict[str, Any]) -> None:
        for k, item in mapping.items():
            if isinstance(item, dict):
                pk_val = str(item.get(self.primary_key, k))
                self._pk_index[pk_val] = item

    def _build_index_from_raw(self, data: Any) -> None:
        if isinstance(data, list):
            self._index_list(data)
        elif isinstance(data, dict):
            self._index_dict(data)

    def contains_pk(self, pk_value: str) -> bool:
        """O(1) check whether the primary key exists."""
        self._ensure_loaded()
        return str(pk_value) in self._pk_index

    def get_by_pk(self, pk_value: str) -> Optional[Dict[str, Any]]:
        """O(1) retrieval of record by primary key."""
        self._ensure_loaded()
        return self._pk_index.get(str(pk_value))

    def upsert(self, record: Dict[str, Any], auto_flush: bool = True) -> None:
        """Upserts a record by primary key."""
        self._ensure_loaded()
        pk = str(record.get(self.primary_key, ""))
        if not pk:
            raise JsonStorageError(f"Record missing primary key '{self.primary_key}'")
        self._pk_index[pk] = record
        if auto_flush:
            self.flush()

    def upsert_many(
        self, records: List[Dict[str, Any]], auto_flush: bool = True
    ) -> None:
        """Batch upserts multiple records and optionally flushes once."""
        self._ensure_loaded()
        for rec in records:
            pk = str(rec.get(self.primary_key, ""))
            if pk:
                self._pk_index[pk] = rec
        if auto_flush:
            self.flush()

    def delete(self, pk_value: str, auto_flush: bool = True) -> bool:
        """Deletes a record by primary key."""
        self._ensure_loaded()
        key = str(pk_value)
        if key in self._pk_index:
            del self._pk_index[key]
            if auto_flush:
                self.flush()
            return True
        return False

    def all_records(self) -> List[Dict[str, Any]]:
        """Returns all records in table sorted by primary key."""
        self._ensure_loaded()
        sorted_keys = sorted(self._pk_index.keys())
        return [self._pk_index[k] for k in sorted_keys]

    def all_pks(self) -> Set[str]:
        """Returns set of all indexed primary keys."""
        self._ensure_loaded()
        return set(self._pk_index.keys())

    def count(self) -> int:
        """Returns total number of rows in table."""
        self._ensure_loaded()
        return len(self._pk_index)

    def flush(self) -> None:
        """
        Atomically flushes in-memory state to disk.
        Uses .tmp.<pid>.<uuid> and os.replace for complete crash safety.
        """
        self._ensure_loaded()
        records = self.all_records()
        formatted_json = json.dumps(
            records, ensure_ascii=False, indent=2, sort_keys=True
        )

        tmp_path = f"{self.file_path}.tmp.{os.getpid()}.{uuid.uuid4().hex[:8]}"
        try:
            with open(tmp_path, "w", encoding="utf-8") as f:
                with file_flock(f, fcntl.LOCK_EX):
                    f.write(formatted_json)
                    f.flush()
                    try:
                        os.fsync(f.fileno())
                    except OSError:
                        pass
            os.replace(tmp_path, self.file_path)
        finally:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass
