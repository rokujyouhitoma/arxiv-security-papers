#!/usr/bin/env python3
"""
Zero-Dependency Binary Multi-Table Vector Storage Container (OKFMTC01).
Enables storing and querying multiple named VectorStorage tables inside a single .vdb file.
"""

from __future__ import annotations

import io
import json
import logging
import os
import struct
import time
import zlib
from typing import Any, Dict, List, Optional, Tuple

from .storage import VectorStorage, VectorStorageSecurityError

logger = logging.getLogger(__name__)

SUPERBLOCK_MAGIC = b"OKFMTC01"
SUPERBLOCK_FORMAT = "<8sHHQQIQ24s"  # 64 Bytes
SUPERBLOCK_SIZE = struct.calcsize(SUPERBLOCK_FORMAT)
MAX_TABLE_COUNT = 1024
MAX_TOTAL_VECTORS = 10_000_000


class MultiTableSecurityError(VectorStorageSecurityError):
    """Raised when container binary header tampering or bounds corruption is detected."""

    pass


def _validate_table_name(name: str) -> str:
    cleaned = name.strip()
    if not cleaned or not cleaned.isidentifier():
        raise ValueError(f"Invalid table identifier: {name!r}")
    return cleaned


def _pack_superblock(
    table_count: int, catalog_offset: int, catalog_len: int, crc32_val: int
) -> bytes:
    now_ts = int(time.time())
    padding = b"\x00" * 24
    return struct.pack(
        SUPERBLOCK_FORMAT,
        SUPERBLOCK_MAGIC,
        1,  # format version
        table_count,
        catalog_offset,
        catalog_len,
        crc32_val,
        now_ts,
        padding,
    )


def _unpack_and_validate_superblock(header_bytes: bytes) -> Tuple[int, int, int, int]:
    if len(header_bytes) < SUPERBLOCK_SIZE:
        raise MultiTableSecurityError("Header truncated: smaller than superblock")
    magic, ver, count, cat_off, cat_len, crc, _, _ = struct.unpack(
        SUPERBLOCK_FORMAT, header_bytes[:SUPERBLOCK_SIZE]
    )
    if magic != SUPERBLOCK_MAGIC:
        raise MultiTableSecurityError(
            f"Invalid magic: {magic!r}, expected {SUPERBLOCK_MAGIC!r}"
        )
    if ver != 1:
        raise MultiTableSecurityError(f"Unsupported container version: {ver}")
    if count > MAX_TABLE_COUNT:
        raise MultiTableSecurityError(f"Table count {count} exceeds MAX_TABLE_COUNT")
    return count, cat_off, cat_len, crc


def _verify_crc32(data: bytes, expected_crc: int) -> None:
    actual = zlib.crc32(data) & 0xFFFFFFFF
    if actual != expected_crc:
        raise MultiTableSecurityError(
            f"Catalog CRC32 mismatch: {actual:#x} != {expected_crc:#x}"
        )


def _validate_catalog_bounds(cat_off: int, cat_len: int, file_size: int) -> None:
    if cat_off < SUPERBLOCK_SIZE or cat_off + cat_len > file_size:
        raise MultiTableSecurityError("Catalog bounds exceed container file size")


def _verify_table_bounds(
    offset: int, length: int, cat_off: int, file_size: int
) -> None:
    if offset < SUPERBLOCK_SIZE or offset + length > file_size:
        raise MultiTableSecurityError("Table segment exceeds container bounds")
    if offset + length > cat_off:
        raise MultiTableSecurityError("Table segment overlaps with catalog")


class MultiTableVectorStorage:
    """
    High-performance Multi-Table Vector Storage Container using OKFMTC01 format.
    Holds multiple named VectorStorage tables inside a single .vdb file or memory buffer.
    """

    def __init__(self, file_path: str = ":memory:") -> None:
        self.file_path = file_path
        self.is_memory = file_path in (":memory:", "")
        self._tables: Dict[str, VectorStorage] = {}
        self._memory_buffer: Optional[io.BytesIO] = (
            io.BytesIO() if self.is_memory else None
        )
        if not self.is_memory and os.path.exists(self.file_path):
            self.load()

    def has_table(self, name: str) -> bool:
        return name in self._tables

    def list_tables(self) -> List[str]:
        return sorted(list(self._tables.keys()))

    def get_table(self, name: str) -> VectorStorage:
        if name not in self._tables:
            raise KeyError(f"Table '{name}' not found in container")
        return self._tables[name]

    def create_table(self, name: str, dim: int = 16) -> VectorStorage:
        valid_name = _validate_table_name(name)
        if len(self._tables) >= MAX_TABLE_COUNT:
            raise ValueError(f"Max table limit {MAX_TABLE_COUNT} reached")
        tbl = VectorStorage(file_path=":memory:", dim=dim)
        self._tables[valid_name] = tbl
        return tbl

    def get_or_create_table(self, name: str, dim: int = 16) -> VectorStorage:
        if self.has_table(name):
            return self.get_table(name)
        return self.create_table(name, dim=dim)

    def drop_table(self, name: str) -> bool:
        if name in self._tables:
            tbl = self._tables.pop(name)
            tbl.close()
            return True
        return False

    def _collect_table_blobs(self) -> Tuple[List[bytes], Dict[str, Any]]:
        blobs: List[bytes] = []
        catalog_entries: Dict[str, Any] = {}
        curr_offset = SUPERBLOCK_SIZE
        for name in sorted(self._tables.keys()):
            tbl = self._tables[name]
            blob = tbl.to_bytes()
            blobs.append(blob)
            catalog_entries[name] = {
                "offset": curr_offset,
                "length": len(blob),
                "dim": tbl.dim,
                "count": tbl.count,
            }
            curr_offset += len(blob)
        return blobs, catalog_entries

    def to_bytes(self) -> bytes:
        blobs, catalog_entries = self._collect_table_blobs()
        cat_json = json.dumps(
            {"format_version": 1, "tables": catalog_entries}, ensure_ascii=False
        ).encode("utf-8")
        crc = zlib.crc32(cat_json) & 0xFFFFFFFF
        cat_offset = SUPERBLOCK_SIZE + sum(len(b) for b in blobs)
        sb = _pack_superblock(len(self._tables), cat_offset, len(cat_json), crc)

        out = io.BytesIO()
        out.write(sb)
        for b in blobs:
            out.write(b)
        out.write(cat_json)
        return out.getvalue()

    def _parse_catalog_from_bytes(
        self, data: bytes, cat_off: int, cat_len: int, crc: int
    ) -> Dict[str, Any]:
        _validate_catalog_bounds(cat_off, cat_len, len(data))
        cat_bytes = data[cat_off : cat_off + cat_len]
        _verify_crc32(cat_bytes, crc)
        return json.loads(cat_bytes.decode("utf-8"))  # type: ignore[no-any-return]

    def _load_single_table_from_blob(
        self, name: str, meta: Dict[str, Any], cat_off: int, data: bytes
    ) -> None:
        off = int(meta["offset"])
        length = int(meta["length"])
        dim = int(meta.get("dim", 16))
        _verify_table_bounds(off, length, cat_off, len(data))
        tbl_blob = data[off : off + length]
        storage = VectorStorage(file_path=":memory:", dim=dim)
        if tbl_blob:
            storage.load_from_bytes(tbl_blob)
        self._tables[name] = storage

    def load_from_bytes(self, data: bytes) -> None:
        self.close()
        count, cat_off, cat_len, crc = _unpack_and_validate_superblock(data)
        catalog = self._parse_catalog_from_bytes(data, cat_off, cat_len, crc)
        tables_meta = catalog.get("tables", {})
        for name, meta in tables_meta.items():
            self._load_single_table_from_blob(name, meta, cat_off, data)
        if self.is_memory:
            self._memory_buffer = io.BytesIO(data)

    def save(self, target_path: Optional[str] = None) -> None:
        dest = target_path or self.file_path
        data = self.to_bytes()
        if dest in (":memory:", ""):
            self._memory_buffer = io.BytesIO(data)
            return
        os.makedirs(os.path.dirname(os.path.abspath(dest)), exist_ok=True)
        tmp_file = dest + ".tmp"
        with open(tmp_file, "wb") as f:
            f.write(data)
        os.replace(tmp_file, dest)

    def load(self, source_path: Optional[str] = None) -> None:
        src = source_path or self.file_path
        if src in (":memory:", ""):
            if self._memory_buffer is not None:
                self.load_from_bytes(self._memory_buffer.getvalue())
            return
        with open(src, "rb") as f:
            raw = f.read()
        self.load_from_bytes(raw)

    def attach_to_executor(self, executor: Any) -> None:
        """Registers all container tables into SQLExecutor catalogs."""
        from ..sql.executor import TableCatalog

        for name, storage in self._tables.items():
            executor.tables[name] = TableCatalog(name=name, storage=storage)

    def close(self) -> None:
        for tbl in self._tables.values():
            tbl.close()
        self._tables.clear()
        if self._memory_buffer is not None and not self._memory_buffer.closed:
            self._memory_buffer.close()
            self._memory_buffer = None

    def __enter__(self) -> "MultiTableVectorStorage":
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.close()
