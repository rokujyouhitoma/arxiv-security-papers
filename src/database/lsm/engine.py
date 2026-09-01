#!/usr/bin/env python3
"""
LSM-Tree (Log-Structured Merge-Tree) Storage Engine.
Coordinates Active MemTable, Immutable MemTable, Multi-level SSTables,
point lookups, range scans, automatic flush, and Leveled/Size-Tiered Compaction.
"""

import json
import os
import threading
import time
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
    ) -> None:
        self.data_dir = data_dir
        self.vfs: VFS = vfs if vfs is not None else get_vfs()
        self.max_memtable_bytes = max_memtable_bytes
        self._lock = threading.RLock()

        self.active_memtable = MemTable(max_bytes=max_memtable_bytes)
        self.immutable_memtables: List[MemTable] = []
        self.sstables: List[SSTableReader] = []
        self._sstable_seq: int = 0

    def put(self, key: str, value: Any) -> None:
        """Writes or updates a key-value record."""
        with self._lock:
            self.active_memtable.put(key, value)
            if self.active_memtable.is_full():
                self.flush_memtable()

    def delete(self, key: str) -> None:
        """Records a deletion marker (tombstone) for key."""
        with self._lock:
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

            writer = SSTableWriter(file_path=sstable_path, vfs=self.vfs)
            writer.write(items)

            reader = SSTableReader(file_path=sstable_path, vfs=self.vfs)
            self.sstables.insert(0, reader)

            self.active_memtable.clear()
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
            SSTableWriter(file_path=compacted_path, vfs=self.vfs).write(
                compacted_entries
            )
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
