#!/usr/bin/env python3
"""
src/database/storage/csv_storage.py

Pure-Python CSV Table Storage Engine for Git-Trackable Open Data.
Provides:
  - CsvTableStorage: Primary-key indexed storage engine persisting entire table as RFC 4180 CSV.
  - Maintains in-memory primary key index for O(1) existence checks and lookups.
  - Flushes changes atomically via crash-safe replace (.tmp.<pid>.<uuid> -> os.replace).
  - flock protected for concurrent access safety.

Conforms to DSN-05 Section 21, zero-external-dependency rule, and STRIDE security model.
"""

from __future__ import annotations

import csv
import fcntl
import json
import os
import uuid
from typing import Any, Dict, List, Optional, Sequence, Set

from .json_storage import file_flock


class CsvStorageError(Exception):
    """Base exception for CSV storage errors."""


def _parse_bool_val(low: str) -> Optional[bool]:
    if low == "true":
        return True
    if low == "false":
        return False
    return None


def _parse_int_val(val: str) -> Optional[int]:
    if val.isdigit() or (val.startswith("-") and val[1:].isdigit()):
        return int(val)
    return None


def _is_json_enclosed(val: str) -> bool:
    if val.startswith("{") and val.endswith("}"):
        return True
    return val.startswith("[") and val.endswith("]")


def _parse_json_val(val: str) -> Any:
    if not _is_json_enclosed(val):
        return val
    try:
        return json.loads(val)
    except json.JSONDecodeError:
        return val


def _parse_csv_val(val: str) -> Any:
    """Safely coerces a string CSV cell value into typed Python object."""
    if not val:
        return ""
    b_val = _parse_bool_val(val.lower())
    if b_val is not None:
        return b_val
    i_val = _parse_int_val(val)
    if i_val is not None:
        return i_val
    return _parse_json_val(val)


def _format_cell_val(val: Any) -> str:
    """Formats a Python object into a string suitable for CSV cell storage."""
    if val is None:
        return ""
    if isinstance(val, bool):
        return "1" if val else "0"
    if isinstance(val, (dict, list)):
        return json.dumps(val, ensure_ascii=False)
    return str(val)


class CsvTableStorage:
    """Primary-key indexed storage engine for mutable catalogs stored as CSV.

    Conforms to same interface as JsonTableStorage and VectorStorage for SQL/Catalog compatibility.
    """

    def __init__(
        self,
        file_path: str,
        primary_key: str = "id",
        fieldnames: Optional[Sequence[str]] = None,
    ) -> None:
        self.file_path = os.path.abspath(file_path)
        self.primary_key = primary_key
        self._fieldnames: List[str] = list(fieldnames) if fieldnames else []
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

        with open(self.file_path, "r", encoding="utf-8", newline="") as f:
            with file_flock(f, fcntl.LOCK_SH):
                self._load_from_stream(f)
        self._is_loaded = True

    def _merge_fieldnames(self, new_names: Optional[Sequence[str]]) -> None:
        if not new_names:
            return
        for fn in new_names:
            if fn and fn not in self._fieldnames:
                self._fieldnames.append(fn)

    def _index_single_row(self, row: Dict[str, Any]) -> None:
        if not row:
            return
        parsed_row = {k: _parse_csv_val(v) for k, v in row.items() if k}
        pk_val = str(parsed_row.get(self.primary_key, ""))
        if pk_val:
            self._pk_index[pk_val] = parsed_row

    def _load_from_stream(self, stream: Any) -> None:
        reader = csv.DictReader(stream)
        self._merge_fieldnames(reader.fieldnames)
        for row in reader:
            self._index_single_row(row)

    def _update_fieldnames(self, record: Dict[str, Any]) -> None:
        for k in record.keys():
            if k not in self._fieldnames:
                self._fieldnames.append(k)

    def contains_pk(self, pk_value: str) -> bool:
        """O(1) check whether the primary key exists."""
        self._ensure_loaded()
        return str(pk_value) in self._pk_index

    def get_by_pk(self, pk_value: str) -> Optional[Dict[str, Any]]:
        """O(1) retrieval of record by primary key."""
        self._ensure_loaded()
        return self._pk_index.get(str(pk_value))

    def upsert(self, record: Dict[str, Any], auto_flush: bool = True) -> None:
        """Upserts a single record by primary key."""
        self._ensure_loaded()
        pk = str(record.get(self.primary_key, ""))
        if not pk:
            raise CsvStorageError(f"Record missing primary key '{self.primary_key}'")
        self._update_fieldnames(record)
        self._pk_index[pk] = dict(record)
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
                self._update_fieldnames(rec)
                self._pk_index[pk] = dict(rec)
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

    @property
    def fieldnames(self) -> List[str]:
        """Returns current list of CSV column header fieldnames."""
        return list(self._fieldnames)

    def flush(self) -> None:
        """Atomically flushes in-memory state to disk as CSV.

        Uses .tmp.<pid>.<uuid> and os.replace for complete crash safety.
        """
        self._ensure_loaded()
        records = self.all_records()
        headers = list(self._fieldnames)
        if not headers and records:
            headers = sorted(records[0].keys())

        tmp_path = f"{self.file_path}.tmp.{os.getpid()}.{uuid.uuid4().hex[:8]}"
        try:
            self._write_csv_file(tmp_path, headers, records)
            os.replace(tmp_path, self.file_path)
        finally:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass

    def _write_csv_file(
        self, target_path: str, headers: List[str], records: List[Dict[str, Any]]
    ) -> None:
        with open(target_path, "w", encoding="utf-8", newline="") as f:
            with file_flock(f, fcntl.LOCK_EX):
                writer = csv.DictWriter(
                    f,
                    fieldnames=headers,
                    quoting=csv.QUOTE_MINIMAL,
                    extrasaction="ignore",
                )
                writer.writeheader()
                for rec in records:
                    formatted_row = {k: _format_cell_val(rec.get(k)) for k in headers}
                    writer.writerow(formatted_row)
                f.flush()
                try:
                    os.fsync(f.fileno())
                except OSError:
                    pass

    @property
    def metadata(self) -> List[Dict[str, Any]]:
        """Returns all records for TableCatalog / SQL executor compatibility."""
        return self.all_records()
