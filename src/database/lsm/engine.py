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

    def get(self, key: str) -> Optional[Any]:
        """
        Looks up a key across MemTable, Immutable MemTables, and SSTables (newest to oldest).
        """
        with self._lock:
            # 1. Search Active MemTable
            found, val = self.active_memtable.get(key)
            if found:
                return val

            # 2. Search Immutable MemTables
            for imm in reversed(self.immutable_memtables):
                found, val = imm.get(key)
                if found:
                    return val

            # 3. Search SSTables from newest to oldest
            for sstable in self.sstables:
                found, val = sstable.get(key)
                if found:
                    return val

            return None

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

    def compact(self) -> Optional[str]:
        """
        Merges all current SSTables into a single compacted SSTable,
        resolving duplicate keys and purging deleted tombstones.
        """
        with self._lock:
            if not self.sstables:
                return None

            # Merge all SSTables (oldest to newest so newer overwrites older)
            merged_dict: Dict[str, bytes] = {}
            for sstable in reversed(self.sstables):
                for k, v in sstable.scan_all():
                    merged_dict[k] = v

            # Purge tombstones
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

            writer = SSTableWriter(file_path=compacted_path, vfs=self.vfs)
            writer.write(compacted_entries)

            # Close and delete old SSTables
            old_readers = list(self.sstables)
            self.sstables = []
            for old in old_readers:
                old.close()
                try:
                    self.vfs.delete(old.file_path)
                except Exception:
                    pass

            new_reader = SSTableReader(file_path=compacted_path, vfs=self.vfs)
            self.sstables = [new_reader]
            return compacted_path

    def scan_all(self) -> List[Tuple[str, Any]]:
        """
        Returns all active key-value pairs sorted ascending by key,
        reflecting the latest state across MemTable and SSTables.
        """
        with self._lock:
            latest: Dict[str, bytes] = {}

            # Read SSTables (oldest to newest)
            for sstable in reversed(self.sstables):
                for k, v in sstable.scan_all():
                    latest[k] = v

            # Read Immutable MemTables
            for imm in self.immutable_memtables:
                for k, v in imm.items():
                    latest[k] = v

            # Read Active MemTable
            for k, v in self.active_memtable.items():
                latest[k] = v

            results: List[Tuple[str, Any]] = []
            for k in sorted(latest.keys()):
                raw = latest[k]
                if raw == TOMBSTONE:
                    continue
                try:
                    decoded = json.loads(raw.decode("utf-8"))
                    results.append((k, decoded))
                except Exception:
                    try:
                        results.append((k, raw.decode("utf-8")))
                    except Exception:
                        results.append((k, raw))

            return results

    def close(self) -> None:
        """Closes all open SSTable reader file handles."""
        with self._lock:
            for sstable in self.sstables:
                sstable.close()
            self.sstables.clear()
