#!/usr/bin/env python3
"""
Storage Backend Pager & Buffer Cache Subsystem.
Implements 4096-byte page cache with LRU eviction, dirty page tracking,
disk-persistent Write-Ahead Logging (WAL), Steal/No-Force buffer policy,
and ARIES crash recovery integration.
"""

import struct
import threading
from typing import Any, Dict, List, Optional, Tuple

from ..transaction.recovery import ARIESRecoveryManager
from ..transaction.wal import LogRecordType, WALReader, WALWriter
from .buffer_pool import BufferFrame, BufferPool2Q
from .vfs import VFS, VFSFile, get_vfs

PAGE_SIZE = 4096


class Page:
    """Represents a cached 4KB database page with LSN and pin lifecycle."""

    def __init__(
        self,
        page_id: int,
        data: bytearray,
        is_dirty: bool = False,
        page_lsn: int = 0,
    ) -> None:
        self.page_id = page_id
        self.data = data
        self.is_dirty = is_dirty
        self.page_lsn = page_lsn
        self.pin_count = 0
        if page_lsn == 0 and len(data) >= 28:
            self.page_lsn = self._read_lsn_from_header()

    def pin(self) -> int:
        """Increments pin count, protecting page from eviction."""
        self.pin_count += 1
        return self.pin_count

    def unpin(self, is_dirty: bool = False) -> int:
        """Decrements pin count and optionally marks page dirty."""
        if self.pin_count > 0:
            self.pin_count -= 1
        if is_dirty:
            self.is_dirty = True
        return self.pin_count

    def is_pinned(self) -> bool:
        """Returns True if currently pinned."""
        return self.pin_count > 0

    def _read_lsn_from_header(self) -> int:
        if len(self.data) >= 28:
            try:
                page_id, lsn, slot_count, free_lower, free_upper, flags, next_id = (
                    struct.unpack_from("<IQHHHHI", self.data, 0)
                )
                if 28 <= free_lower <= free_upper <= 4096 and flags in (1, 2, 4, 8, 16):
                    return int(lsn)
            except Exception:
                return 0
        return 0

    def set_lsn(self, lsn: int) -> None:
        """Updates the page LSN both in memory attribute and header if slotted page."""
        if len(self.data) >= 28:
            try:
                page_id, old_lsn, slot_count, free_lower, free_upper, flags, next_id = (
                    struct.unpack_from("<IQHHHHI", self.data, 0)
                )
                if 28 <= free_lower <= free_upper <= 4096 and flags in (1, 2, 4, 8, 16):
                    struct.pack_into(
                        "<IQHHHHI",
                        self.data,
                        0,
                        page_id,
                        lsn,
                        slot_count,
                        free_lower,
                        free_upper,
                        flags,
                        next_id,
                    )
            except Exception:
                pass
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
    """
    2Q (Two-Queue) Page Buffer Pool Cache with Scan Resistance.
    Maintains A1_in (FIFO), A1_out (Ghost FIFO), and Am (LRU) queues.
    """

    def __init__(self, capacity: int = 256) -> None:
        self.capacity = capacity
        self._pool = BufferPool2Q(capacity=capacity)
        # page_id -> Page instance wrapper mapping
        self._pages: Dict[int, Page] = {}
        self._lock = threading.RLock()

    def __len__(self) -> int:
        with self._lock:
            return self._pool.total_cached_pages

    def get(self, page_id: int) -> Optional[Page]:
        with self._lock:
            frame = self._pool.get(page_id)
            if frame is None:
                return None
            if page_id not in self._pages:
                page = Page(
                    page_id=frame.page_id,
                    data=frame.data,
                    is_dirty=frame.is_dirty,
                    page_lsn=frame.page_lsn,
                )
                page.pin_count = frame.pin_count
                self._pages[page_id] = page
            else:
                page = self._pages[page_id]
                page.data = frame.data
                page.is_dirty = frame.is_dirty
                page.page_lsn = frame.page_lsn
                page.pin_count = frame.pin_count
            return page

    def put(self, page: Page) -> Optional[Page]:
        """Puts page into 2Q buffer pool, returning evicted Page if any."""
        with self._lock:
            frame = BufferFrame(
                page_id=page.page_id,
                data=page.data,
                page_lsn=page.page_lsn,
                is_dirty=page.is_dirty,
            )
            frame.pin_count = page.pin_count
            self._pages[page.page_id] = page

            evicted_frame = self._pool.put(page.page_id, frame)
            if evicted_frame is not None:
                evicted_page = self._pages.pop(
                    evicted_frame.page_id,
                    Page(
                        page_id=evicted_frame.page_id,
                        data=evicted_frame.data,
                        is_dirty=evicted_frame.is_dirty,
                        page_lsn=evicted_frame.page_lsn,
                    ),
                )
                evicted_page.is_dirty = evicted_frame.is_dirty
                return evicted_page
            return None

    def pin_page(self, page_id: int) -> Page:
        """Pins a page in 2Q buffer pool."""
        with self._lock:
            page = self.get(page_id)
            if page is None:
                raise KeyError(f"Page {page_id} is not resident in cache")
            page.pin()
            self._pool.pin_page(page_id)
            return page

    def unpin_page(self, page_id: int, is_dirty: bool = False) -> None:
        """Unpins a page in 2Q buffer pool."""
        with self._lock:
            page = self.get(page_id)
            if page is not None:
                page.unpin(is_dirty=is_dirty)
            self._pool.unpin_page(page_id, is_dirty=is_dirty)

    def remove(self, page_id: int) -> Optional[Page]:
        with self._lock:
            page = self._pages.pop(page_id, None)
            return page

    def get_all_pages(self) -> List[Page]:
        with self._lock:
            return [self.get(pid) for pid in list(self._pages.keys()) if self.get(pid) is not None]  # type: ignore

    def clear(self) -> None:
        with self._lock:
            self._pool.clear()
            self._pages.clear()


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
            disk_pages = (
                (total_bytes + PAGE_SIZE - 1) // PAGE_SIZE if total_bytes > 0 else 0
            )
            cached_pages = 0
            all_cached = self.cache.get_all_pages()
            if all_cached:
                cached_pages = max(p.page_id for p in all_cached) + 1
            return max(disk_pages, cached_pages)

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

    @staticmethod
    def _normalize_page_data(data: bytes) -> bytearray:
        page_data = bytearray(data)
        if len(page_data) < PAGE_SIZE:
            page_data.extend(b"\x00" * (PAGE_SIZE - len(page_data)))
        elif len(page_data) > PAGE_SIZE:
            page_data = page_data[:PAGE_SIZE]
        return page_data

    def _append_wal_update(
        self, page_id: int, old_data: bytearray, page_data: bytearray
    ) -> int:
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
        self.tx_prev_lsn[self.current_tx_id] = record.lsn
        return record.lsn

    def _create_and_cache_page(
        self, page_id: int, page_data: bytearray, assigned_lsn: int
    ) -> None:
        page = Page(page_id, page_data, is_dirty=True, page_lsn=assigned_lsn)
        if assigned_lsn > 0:
            page.set_lsn(assigned_lsn)
        evicted = self.cache.put(page)
        if evicted and evicted.is_dirty:
            self._flush_page_to_disk(evicted)

    def write_page(self, page_id: int, data: bytes) -> None:
        """Writes page into cache, logging WAL update if transaction is active."""
        with self._lock:
            page_data = self._normalize_page_data(data)
            old_data = self.read_page(page_id)
            assigned_lsn = 0
            if self.is_in_transaction and self.wal:
                assigned_lsn = self._append_wal_update(page_id, old_data, page_data)
            self._create_and_cache_page(page_id, page_data, assigned_lsn)

    def read_slotted_page(self, page_id: int) -> Any:
        """Reads and constructs a SlottedPage instance by page_id."""
        from .slotted_page import SlottedPage

        raw = self.read_page(page_id)
        return SlottedPage(raw_data=raw)

    def write_slotted_page(self, slotted: Any) -> None:
        """Serializes and writes a SlottedPage instance to cache and WAL."""
        self.write_page(slotted.page_id, slotted.serialize())

    def pin_page(self, page_id: int) -> Page:
        """Loads and pins a page in the 2Q buffer pool, guaranteeing memory residency."""
        with self._lock:
            # Ensure page is resident
            self.read_page(page_id)
            return self.cache.pin_page(page_id)

    def unpin_page(self, page_id: int, is_dirty: bool = False) -> None:
        """Unpins a page, allowing it to be evicted if needed."""
        with self._lock:
            self.cache.unpin_page(page_id, is_dirty=is_dirty)

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

    def _undo_update_record(self, rec: Any) -> None:
        """Undoes a single WAL UPDATE record."""
        page_data = self.read_page(rec.page_id)
        offset = rec.offset
        undo = rec.undo_data
        page_data[offset : offset + len(undo)] = undo
        clr_rec = self.wal.append_record(
            tx_id=self.current_tx_id,
            record_type=LogRecordType.CLR,
            prev_lsn=self.wal.next_lsn - 1,
            page_id=rec.page_id,
            offset=offset,
            redo_data=undo,
            undo_next_lsn=rec.prev_lsn,
        )
        page = Page(rec.page_id, page_data, is_dirty=True, page_lsn=clr_rec.lsn)
        page.set_lsn(clr_rec.lsn)
        self.cache.put(page)

    def _apply_undo_if_update(self, rec: Any) -> None:
        if rec.record_type == LogRecordType.UPDATE and rec.page_id != 0xFFFFFFFF:
            self._undo_update_record(rec)

    def _undo_records_chain(self, last_lsn: int) -> None:
        reader = WALReader(self.wal_path, vfs=self.vfs)
        records = {r.lsn: r for r in reader.read_all_records()}
        curr: Optional[int] = last_lsn
        while curr and curr in records:
            rec = records[curr]
            self._apply_undo_if_update(rec)
            curr = rec.prev_lsn

    def rollback(self) -> None:
        """Rolls back active transaction changes using ARIES Undo logic."""
        with self._lock:
            if not self.is_in_transaction or not self.wal:
                self.is_in_transaction = False
                return
            last_lsn = self.tx_prev_lsn.get(self.current_tx_id, 0)
            if last_lsn > 0:
                self._undo_records_chain(last_lsn)
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
