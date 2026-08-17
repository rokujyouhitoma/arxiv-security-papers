#!/usr/bin/env python3
"""
Storage Backend Pager & Buffer Cache Subsystem.
Implements 4096-byte page cache with LRU eviction, dirty page tracking,
and Write-Ahead Logging (WAL) transaction boundaries.
"""

import os
import threading
from collections import OrderedDict
from typing import Dict, List, Optional, Tuple, Union

from .vfs import VFSFile, get_vfs

PAGE_SIZE = 4096


class Page:
    """Represents a single in-memory 4096-byte database page."""

    def __init__(
        self, page_id: int, data: Union[bytearray, bytes], is_dirty: bool = False
    ) -> None:
        self.page_id = page_id
        self.data = (
            bytearray(data)
            if isinstance(data, (bytes, bytearray))
            else bytearray(PAGE_SIZE)
        )
        self.is_dirty = is_dirty


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
    Coordinates page I/O between buffer cache and VFS storage,
    managing WAL transaction boundaries.
    """

    def __init__(
        self,
        file_path: str,
        vfs_name: Optional[str] = None,
        cache_capacity: int = 256,
    ) -> None:
        self.file_path = file_path
        self.vfs = get_vfs(vfs_name)
        self.file = self.vfs.open(file_path, mode="r+b")
        self.cache = PageCache(capacity=cache_capacity)
        self.wal_buffer: Dict[int, bytearray] = {}
        self.is_in_transaction = False
        self._lock = threading.RLock()

    def page_count(self) -> int:
        with self._lock:
            total_bytes = self.file.file_size()
            return (total_bytes + PAGE_SIZE - 1) // PAGE_SIZE

    def read_page(self, page_id: int) -> bytearray:
        """Reads page from WAL buffer, page cache, or disk."""
        with self._lock:
            # 1. Check WAL transaction buffer
            if page_id in self.wal_buffer:
                return bytearray(self.wal_buffer[page_id])

            # 2. Check LRU Cache
            cached = self.cache.get(page_id)
            if cached is not None:
                return bytearray(cached.data)

            # 3. Read from VFS file
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
        """Writes page into cache and WAL buffer."""
        with self._lock:
            page_data = bytearray(data)
            if len(page_data) < PAGE_SIZE:
                page_data.extend(b"\x00" * (PAGE_SIZE - len(page_data)))
            elif len(page_data) > PAGE_SIZE:
                page_data = page_data[:PAGE_SIZE]

            if self.is_in_transaction:
                self.wal_buffer[page_id] = bytearray(page_data)

            page = Page(page_id, page_data, is_dirty=True)
            evicted = self.cache.put(page)
            if evicted and evicted.is_dirty:
                self._flush_page_to_disk(evicted)

    def begin(self) -> None:
        """Starts a WAL transaction."""
        with self._lock:
            self.is_in_transaction = True
            self.wal_buffer.clear()

    def commit(self) -> None:
        """Flushes all WAL buffered pages to disk."""
        with self._lock:
            for page_id, data in self.wal_buffer.items():
                offset = page_id * PAGE_SIZE
                self.file.write(offset, bytes(data))
                cached = self.cache.get(page_id)
                if cached:
                    cached.is_dirty = False

            self.file.sync()
            self.wal_buffer.clear()
            self.is_in_transaction = False

    def rollback(self) -> None:
        """Aborts WAL transaction and discards uncommitted buffers."""
        with self._lock:
            for page_id in self.wal_buffer.keys():
                self.cache.remove(page_id)
            self.wal_buffer.clear()
            self.is_in_transaction = False

    def flush_all(self) -> None:
        """Flushes all dirty pages to disk."""
        with self._lock:
            for page in self.cache.get_all_pages():
                if page.is_dirty:
                    self._flush_page_to_disk(page)
            self.file.sync()

    def _flush_page_to_disk(self, page: Page) -> None:
        offset = page.page_id * PAGE_SIZE
        self.file.write(offset, bytes(page.data))
        page.is_dirty = False

    def close(self) -> None:
        with self._lock:
            self.flush_all()
            self.file.close()
