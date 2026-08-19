#!/usr/bin/env python3
"""
Storage Backend Pager & Buffer Cache Subsystem.
Implements 4096-byte page cache with LRU eviction, dirty page tracking,
disk-persistent Write-Ahead Logging (WAL), Steal/No-Force buffer policy,
and ARIES crash recovery integration.
"""

import struct
import threading
from collections import OrderedDict
from typing import Any, Dict, List, Optional, Tuple, Union

from .recovery import ARIESRecoveryManager
from .vfs import VFS, VFSFile, get_vfs
from .wal import DEFAULT_PAGE_SIZE, LogRecordType, WALReader, WALWriter

PAGE_SIZE = DEFAULT_PAGE_SIZE


class Page:
    """Represents a single in-memory 4096-byte database page."""

    def __init__(
        self,
        page_id: int,
        data: Union[bytearray, bytes],
        is_dirty: bool = False,
        page_lsn: int = 0,
    ) -> None:
        self.page_id = page_id
        self.data = (
            bytearray(data)
            if isinstance(data, (bytes, bytearray))
            else bytearray(PAGE_SIZE)
        )
        self.is_dirty = is_dirty
        self.page_lsn = page_lsn or self._read_lsn_from_header()

    def _read_lsn_from_header(self) -> int:
        if len(self.data) >= 28:
            try:
                _, lsn, _, _, _, _, _ = struct.unpack_from("<IQHHHHI", self.data, 0)
                return int(lsn)
            except Exception:
                return 0
        return 0

    def set_lsn(self, lsn: int) -> None:
        self.page_lsn = lsn

    def to_slotted_page(self) -> Any:
        """Converts this page into a structured SlottedPage instance."""
        from .slotted_page import SlottedPage

        return SlottedPage(raw_data=bytes(self.data))

    @classmethod
    def from_slotted_page(cls, slotted: Any) -> "Page":
        """Creates a Page from a SlottedPage instance."""
        serialized = slotted.serialize()
        page_lsn = slotted.header.lsn if hasattr(slotted, "header") else 0
        return cls(
            page_id=slotted.page_id,
            data=serialized,
            is_dirty=True,
            page_lsn=page_lsn,
        )


class PageCache:
    """LRU page buffer pool cache."""

    def __init__(self, capacity: int = 256) -> None:
        self.capacity = capacity
        self._cache: OrderedDict[int, Page] = OrderedDict()
        self._lock = threading.RLock()

    def __len__(self) -> int:
        with self._lock:
            return len(self._cache)

    def get(self, page_id: int) -> Optional[Page]:
        with self._lock:
            if page_id not in self._cache:
                return None
            self._cache.move_to_end(page_id)
            return self._cache[page_id]

    def put(self, page: Page) -> Optional[Page]:
        """Puts page into cache, returning evicted page if capacity is reached."""
        with self._lock:
            evicted: Optional[Page] = None
            if page.page_id in self._cache:
                self._cache.move_to_end(page.page_id)
            elif len(self._cache) >= self.capacity:
                _, evicted = self._cache.popitem(last=False)

            self._cache[page.page_id] = page
            return evicted

    def remove(self, page_id: int) -> Optional[Page]:
        with self._lock:
            return self._cache.pop(page_id, None)

    def get_all_pages(self) -> List[Page]:
        with self._lock:
            return list(self._cache.values())

    def clear(self) -> None:
        with self._lock:
            self._cache.clear()


class Pager:
    """
    Coordinates page I/O between buffer cache, disk VFS storage, and WAL engine.
    Enforces Steal / No-Force buffer policy and coordinates ARIES crash recovery.
    """

    def __init__(
        self,
        file_path: str,
        vfs_name: Optional[str] = None,
        vfs: Optional[VFS] = None,
        cache_capacity: int = 256,
        use_wal: bool = True,
        auto_recover: bool = True,
    ) -> None:
        self.file_path = file_path
        self.vfs_name = vfs_name
        self.vfs = vfs if vfs is not None else get_vfs(vfs_name)
        self.file: VFSFile = self.vfs.open(file_path, mode="r+b")
        self.cache = PageCache(capacity=cache_capacity)
        self.use_wal = use_wal
        self.wal_path = f"{file_path}.vdb-wal"
        self._lock = threading.RLock()

        self.wal: Optional[WALWriter] = None
        if self.use_wal:
            self.wal = WALWriter(self.wal_path, vfs=self.vfs)

        self.current_tx_id: int = 0
        self.tx_prev_lsn: Dict[int, int] = {}
        self.is_in_transaction = False
        self._tx_counter = 1000

        # Run crash recovery on startup if needed
        if self.use_wal and auto_recover:
            self.recover()

    def page_count(self) -> int:
        with self._lock:
            total_bytes = self.file.file_size()
            return (total_bytes + PAGE_SIZE - 1) // PAGE_SIZE

    def read_page(self, page_id: int) -> bytearray:
        """Reads page from LRU Cache or Disk VFS."""
        with self._lock:
            # 1. Check LRU Cache
            cached = self.cache.get(page_id)
            if cached is not None:
                return bytearray(cached.data)

            # 2. Read from VFS file
            offset = page_id * PAGE_SIZE
            raw = self.file.read(offset, PAGE_SIZE)
            data = bytearray(raw)
            if len(data) < PAGE_SIZE:
                data.extend(b"\x00" * (PAGE_SIZE - len(data)))

            page = Page(page_id, data, is_dirty=False)
            evicted = self.cache.put(page)
            if evicted and evicted.is_dirty:
                self._flush_page_to_disk(evicted)

            return bytearray(data)

    def write_page(self, page_id: int, data: bytes) -> None:
        """Writes page into cache, logging WAL update if transaction is active."""
        with self._lock:
            page_data = bytearray(data)
            if len(page_data) < PAGE_SIZE:
                page_data.extend(b"\x00" * (PAGE_SIZE - len(page_data)))
            elif len(page_data) > PAGE_SIZE:
                page_data = page_data[:PAGE_SIZE]

            # Fetch existing page to compute undo payload if in WAL transaction
            old_data = self.read_page(page_id)

            assigned_lsn = 0
            if self.is_in_transaction and self.wal:
                prev_lsn = self.tx_prev_lsn.get(self.current_tx_id, 0)
                record = self.wal.append_record(
                    tx_id=self.current_tx_id,
                    record_type=LogRecordType.UPDATE,
                    prev_lsn=prev_lsn,
                    page_id=page_id,
                    offset=0,
                    undo_data=bytes(old_data),
                    redo_data=bytes(page_data),
                )
                assigned_lsn = record.lsn
                self.tx_prev_lsn[self.current_tx_id] = assigned_lsn

            page = Page(page_id, page_data, is_dirty=True, page_lsn=assigned_lsn)
            if assigned_lsn > 0:
                page.set_lsn(assigned_lsn)

            evicted = self.cache.put(page)
            if evicted and evicted.is_dirty:
                self._flush_page_to_disk(evicted)

    def read_slotted_page(self, page_id: int) -> Any:
        """Reads and constructs a SlottedPage instance by page_id."""
        from .slotted_page import SlottedPage

        raw = self.read_page(page_id)
        return SlottedPage(raw_data=raw)

    def write_slotted_page(self, slotted: Any) -> None:
        """Serializes and writes a SlottedPage instance to cache and WAL."""
        self.write_page(slotted.page_id, slotted.serialize())

    def begin(self, tx_id: Optional[int] = None) -> int:
        """Starts a WAL transaction and appends BEGIN record."""
        with self._lock:
            if tx_id is None:
                self._tx_counter += 1
                self.current_tx_id = self._tx_counter
            else:
                self.current_tx_id = tx_id

            self.is_in_transaction = True

            if self.wal:
                rec = self.wal.append_record(
                    tx_id=self.current_tx_id,
                    record_type=LogRecordType.BEGIN,
                    prev_lsn=0,
                )
                self.tx_prev_lsn[self.current_tx_id] = rec.lsn

            return self.current_tx_id

    def commit(self) -> None:
        """Appends COMMIT record, forces fsync of WAL, and closes transaction."""
        with self._lock:
            if not self.is_in_transaction:
                return

            if self.wal:
                prev_lsn = self.tx_prev_lsn.get(self.current_tx_id, 0)
                self.wal.append_record(
                    tx_id=self.current_tx_id,
                    record_type=LogRecordType.COMMIT,
                    prev_lsn=prev_lsn,
                    force_sync=True,
                )
                self.tx_prev_lsn.pop(self.current_tx_id, None)

            self.is_in_transaction = False

    def rollback(self) -> None:
        """Rolls back active transaction changes using ARIES Undo logic."""
        with self._lock:
            if not self.is_in_transaction or not self.wal:
                self.is_in_transaction = False
                return

            last_lsn = self.tx_prev_lsn.get(self.current_tx_id, 0)
            if last_lsn > 0:
                # Read WAL records for this transaction and perform Undo
                reader = WALReader(self.wal_path, vfs=self.vfs)
                records = {r.lsn: r for r in reader.read_all_records()}

                curr = last_lsn
                while curr > 0 and curr in records:
                    rec = records[curr]
                    if (
                        rec.record_type == LogRecordType.UPDATE
                        and rec.page_id != 0xFFFFFFFF
                    ):
                        # Revert page data
                        page_data = self.read_page(rec.page_id)
                        offset = rec.offset
                        undo = rec.undo_data
                        page_data[offset : offset + len(undo)] = undo

                        # Log CLR
                        clr_rec = self.wal.append_record(
                            tx_id=self.current_tx_id,
                            record_type=LogRecordType.CLR,
                            prev_lsn=self.wal.next_lsn - 1,
                            page_id=rec.page_id,
                            offset=offset,
                            redo_data=undo,
                            undo_next_lsn=rec.prev_lsn,
                        )

                        page = Page(
                            rec.page_id,
                            page_data,
                            is_dirty=True,
                            page_lsn=clr_rec.lsn,
                        )
                        page.set_lsn(clr_rec.lsn)
                        self.cache.put(page)

                    curr = rec.prev_lsn

                # Append ABORT record
                self.wal.append_record(
                    tx_id=self.current_tx_id,
                    record_type=LogRecordType.ABORT,
                    prev_lsn=self.wal.next_lsn - 1,
                    force_sync=True,
                )

            self.tx_prev_lsn.pop(self.current_tx_id, None)
            self.is_in_transaction = False

    def checkpoint(self) -> Tuple[int, int]:
        """
        Performs a Fuzzy Checkpoint by recording Active Transactions
        and Dirty Page Table to WAL.
        """
        with self._lock:
            if not self.wal:
                return 0, 0

            # 1. CHECKPOINT_BEGIN
            self.wal.append_record(
                tx_id=0,
                record_type=LogRecordType.CHECKPOINT_BEGIN,
            )

            # Build ATT and DPT
            att = dict(self.tx_prev_lsn)
            dpt: Dict[int, int] = {}
            for page in self.cache.get_all_pages():
                if page.is_dirty:
                    dpt[page.page_id] = page.page_lsn

            # 2. CHECKPOINT_END
            rec = self.wal.append_record(
                tx_id=0,
                record_type=LogRecordType.CHECKPOINT_END,
                extra_info={"att": att, "dpt": dpt},
                force_sync=True,
            )
            return rec.lsn, len(dpt)

    def recover(self) -> Tuple[int, int]:
        """Runs ARIES crash recovery on startup."""
        with self._lock:
            recovery_mgr = ARIESRecoveryManager(
                db_file_path=self.file_path,
                wal_file_path=self.wal_path,
                vfs=self.vfs,
                page_size=PAGE_SIZE,
            )
            redo_cnt, undo_cnt = recovery_mgr.run_recovery(pager=self)
            return redo_cnt, undo_cnt

    def flush_all(self) -> None:
        """Flushes all dirty pages to disk adhering to WAL-First (Steal) policy."""
        with self._lock:
            for page in self.cache.get_all_pages():
                if page.is_dirty:
                    self._flush_page_to_disk(page)
            self.file.sync()

    def _flush_page_to_disk(self, page: Page) -> None:
        """
        Enforces WAL-First principle (Steal policy):
        Flushes WAL to disk before writing dirty page if page_lsn > wal.flushed_lsn.
        """
        if self.wal and page.page_lsn > self.wal.flushed_lsn:
            self.wal.flush()

        offset = page.page_id * PAGE_SIZE
        self.file.write(offset, bytes(page.data))
        page.is_dirty = False

    def close(self) -> None:
        with self._lock:
            self.flush_all()
            if self.wal:
                self.wal.close()
            self.file.close()

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            pass
