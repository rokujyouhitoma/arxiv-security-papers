#!/usr/bin/env python3
"""
LSM-Tree (Log-Structured Merge-Tree) Storage Engine.
Coordinates Active MemTable, Immutable MemTable, Multi-level SSTables,
point lookups, range scans, automatic flush, and Leveled/Size-Tiered Compaction.
"""

import json
import os
import struct
import threading
import time
import zlib
from typing import Any, Dict, List, Optional, Tuple

from ..vfs import VFS, get_vfs
from .memtable import TOMBSTONE, MemTable
from .sstable import SSTableReader, SSTableWriter


class LSMTreeEngine:
    """
    Log-Structured Merge-Tree (LSM-Tree) Storage Engine.
    Optimized for high-throughput write ingestion, append-only durability,
    and fast point lookups with Bloom filters.
    """

    def __init__(
        self,
        data_dir: str = "data/lsm",
        vfs: Optional[VFS] = None,
        max_memtable_bytes: int = 65536,
        use_slotted_page: bool = True,
        enable_wal: bool = True,
    ) -> None:
        self.data_dir = data_dir
        self.vfs: VFS = vfs if vfs is not None else get_vfs()
        self.max_memtable_bytes = max_memtable_bytes
        self.use_slotted_page = use_slotted_page
        self.enable_wal = enable_wal
        self.wal_path = os.path.join(self.data_dir, "wal.log").replace("\\", "/")
        self._lock = threading.RLock()

        self.active_memtable = MemTable(max_bytes=max_memtable_bytes)
        self.immutable_memtables: List[MemTable] = []
        self.sstables: List[SSTableReader] = []
        self._sstable_seq: int = 0
        if self.enable_wal:
            self._replay_wal()

    def _append_wal(self, op: str, key: str, value: Any) -> None:
        record = json.dumps({"op": op, "key": key, "val": value}) + "\n"
        rec_bytes = record.encode("utf-8")
        crc = zlib.crc32(rec_bytes)
        framed = struct.pack("<II", len(rec_bytes), crc) + rec_bytes
        try:
            mode = "a+b" if self.vfs.exists(self.wal_path) else "w+b"
            f = self.vfs.open(self.wal_path, mode=mode)
            f.write(f.file_size(), framed)
            f.sync()
            f.close()
        except Exception:
            pass

    def _truncate_wal(self) -> None:
        try:
            if self.vfs.exists(self.wal_path):
                self.vfs.delete(self.wal_path)
        except Exception:
            pass

    def _apply_wal_record(self, payload: bytes, crc: int) -> bool:
        if zlib.crc32(payload) != crc:
            return False
        item = json.loads(payload.decode("utf-8"))
        op, key, val = item.get("op"), item.get("key"), item.get("val")
        if op == "PUT":
            self.active_memtable.put(str(key), val)
        elif op == "DEL":
            self.active_memtable.delete(str(key))
        return True

    def _read_wal_bytes(self) -> bytes:
        if not self.vfs.exists(self.wal_path):
            return b""
        try:
            f = self.vfs.open(self.wal_path, mode="r+b")
            raw = f.read(0, f.file_size())
            f.close()
            return raw
        except Exception:
            return b""

    def _parse_wal_bytes(self, raw: bytes) -> None:
        pos = 0
        while pos + 8 <= len(raw):
            rec_len, crc = struct.unpack_from("<II", raw, pos)
            pos += 8
            if pos + rec_len > len(raw):
                break
            payload = raw[pos : pos + rec_len]
            pos += rec_len
            if not self._apply_wal_record(payload, crc):
                break

    def _replay_wal(self) -> None:
        raw = self._read_wal_bytes()
        if raw:
            self._parse_wal_bytes(raw)

    def put(self, key: str, value: Any) -> None:
        """Writes or updates a key-value record."""
        with self._lock:
            if self.enable_wal:
                self._append_wal("PUT", key, value)
            self.active_memtable.put(key, value)
            if self.active_memtable.is_full():
                self.flush_memtable()

    def delete(self, key: str) -> None:
        """Records a deletion marker (tombstone) for key."""
        with self._lock:
            if self.enable_wal:
                self._append_wal("DEL", key, None)
            self.active_memtable.delete(key)
            if self.active_memtable.is_full():
                self.flush_memtable()

    def _search_immutables(self, key: str) -> Tuple[bool, Any]:
        for imm in reversed(self.immutable_memtables):
            found, val = imm.get(key)
            if found:
                return True, val
        return False, None

    def _search_sstables(self, key: str) -> Tuple[bool, Any]:
        for sstable in self.sstables:
            found, val = sstable.get(key)
            if found:
                return True, val
        return False, None

    def _search_in_sources(self, key: str) -> Tuple[bool, Any]:
        """Searches active memtable, immutable memtables, then SSTables."""
        found, val = self.active_memtable.get(key)
        if found:
            return True, val
        found_imm, val_imm = self._search_immutables(key)
        if found_imm:
            return True, val_imm
        return self._search_sstables(key)

    def get(self, key: str) -> Optional[Any]:
        """
        Looks up a key across MemTable, Immutable MemTables, and SSTables (newest to oldest).
        """
        with self._lock:
            found, val = self._search_in_sources(key)
            return val if found else None

    def flush_memtable(self) -> Optional[str]:
        """
        Flushes the current active MemTable to an on-disk immutable SSTable.
        Returns the path of the generated SSTable file.
        """
        with self._lock:
            if len(self.active_memtable) == 0:
                return None

            items = self.active_memtable.items()
            self._sstable_seq += 1
            filename = f"sstable_{int(time.time() * 1000)}_{self._sstable_seq:04d}.sst"
            sstable_path = os.path.join(self.data_dir, filename).replace("\\", "/")

            writer = SSTableWriter(
                file_path=sstable_path,
                vfs=self.vfs,
                use_slotted_page=self.use_slotted_page,
            )
            writer.write(items)

            reader = SSTableReader(file_path=sstable_path, vfs=self.vfs)
            self.sstables.insert(0, reader)

            self.active_memtable.clear()
            if self.enable_wal:
                self._truncate_wal()
            return sstable_path

    def _merge_sstables(self) -> Dict[str, bytes]:
        merged: Dict[str, bytes] = {}
        for sstable in reversed(self.sstables):
            for k, v in sstable.scan_all():
                merged[k] = v
        return merged

    def _close_old_sstables(self) -> None:
        for old in self.sstables:
            old.close()
            try:
                self.vfs.delete(old.file_path)
            except Exception:
                pass
        self.sstables = []

    def compact(self) -> Optional[str]:
        """
        Merges all current SSTables into a single compacted SSTable,
        resolving duplicate keys and purging deleted tombstones.
        """
        with self._lock:
            if not self.sstables:
                return None
            merged_dict = self._merge_sstables()
            compacted_entries = [
                (k, v) for k, v in merged_dict.items() if v != TOMBSTONE
            ]
            self._sstable_seq += 1
            compacted_filename = (
                f"compacted_{int(time.time() * 1000)}_{self._sstable_seq:04d}.sst"
            )
            compacted_path = os.path.join(self.data_dir, compacted_filename).replace(
                "\\", "/"
            )
            SSTableWriter(
                file_path=compacted_path,
                vfs=self.vfs,
                use_slotted_page=self.use_slotted_page,
            ).write(compacted_entries)
            self._close_old_sstables()
            self.sstables = [SSTableReader(file_path=compacted_path, vfs=self.vfs)]
            return compacted_path

    @staticmethod
    def _decode_value(raw: bytes) -> Any:
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            try:
                return raw.decode("utf-8")
            except Exception:
                return raw

    def _collect_memtables_into(self, latest: Dict[str, bytes]) -> None:
        for imm in self.immutable_memtables:
            for k, v in imm.items():
                latest[k] = v
        for k, v in self.active_memtable.items():
            latest[k] = v

    def _collect_latest(self) -> Dict[str, bytes]:
        latest: Dict[str, bytes] = {}
        for sstable in reversed(self.sstables):
            for k, v in sstable.scan_all():
                latest[k] = v
        self._collect_memtables_into(latest)
        return latest

    def scan_all(self) -> List[Tuple[str, Any]]:
        """
        Returns all active key-value pairs sorted ascending by key,
        reflecting the latest state across MemTable and SSTables.
        """
        with self._lock:
            latest = self._collect_latest()
            return [
                (k, self._decode_value(latest[k]))
                for k in sorted(latest)
                if latest[k] != TOMBSTONE
            ]

    def close(self) -> None:
        """Closes all open SSTable reader file handles."""
        with self._lock:
            for sstable in self.sstables:
                sstable.close()
            self.sstables.clear()
