#!/usr/bin/env python3
"""
MMap Zero-Copy File Abstraction for CoW B-Tree Storage.
Provides memory-mapped 4KB page access with direct memoryview slicing,
zero-copy reads, dynamic page allocation, and OS page cache integration.
"""

import mmap
import os
import threading
from typing import BinaryIO, Optional

PAGE_SIZE: int = 4096
DEFAULT_MAP_PAGES: int = 4096  # 16MB virtual address space reservation


class MMapFile:
    """
    Memory-mapped file handle with preallocated virtual mapping space and zero-copy memoryview reads.
    """

    def __init__(
        self,
        file_path: str,
        initial_pages: int = DEFAULT_MAP_PAGES,
    ) -> None:
        self.file_path = file_path
        self.initial_pages = max(16, initial_pages, DEFAULT_MAP_PAGES)
        self._lock = threading.RLock()
        self._file_obj: Optional[BinaryIO] = None
        self._mmap: Optional[mmap.mmap] = None
        self._page_count: int = 0
        self._open()

    def _open(self) -> None:
        os.makedirs(os.path.dirname(os.path.abspath(self.file_path)), exist_ok=True)
        init_size = self.initial_pages * PAGE_SIZE

        if not os.path.exists(self.file_path):
            with open(self.file_path, "wb") as f:
                f.write(b"\x00" * init_size)
            self._page_count = 2  # Meta 0 & Meta 1
        else:
            file_size = os.path.getsize(self.file_path)
            if file_size < init_size:
                with open(self.file_path, "a+b") as f:
                    f.truncate(init_size)
            self._page_count = max(2, file_size // PAGE_SIZE)

        f_obj = open(self.file_path, "r+b")
        self._mmap = mmap.mmap(f_obj.fileno(), 0)
        self._file_obj = f_obj

    @property
    def page_count(self) -> int:
        with self._lock:
            return self._page_count

    def read_page_view(self, page_id: int) -> memoryview:
        """
        Returns a zero-copy memoryview slice of the requested 4KB page.
        """
        with self._lock:
            if self._mmap is None:
                raise RuntimeError("MMapFile is closed")
            offset = page_id * PAGE_SIZE
            if offset + PAGE_SIZE > len(self._mmap):
                raise IndexError(f"Page ID {page_id} out of bounds (offset {offset})")
            return memoryview(self._mmap)[offset : offset + PAGE_SIZE]

    def write_page(self, page_id: int, data: bytes) -> None:
        """
        Writes a 4KB page into the memory mapped buffer.
        """
        if len(data) > PAGE_SIZE:
            raise ValueError(f"Page data size {len(data)} exceeds 4096 bytes")
        padded = (
            data if len(data) == PAGE_SIZE else data + b"\x00" * (PAGE_SIZE - len(data))
        )

        with self._lock:
            if self._mmap is None:
                raise RuntimeError("MMapFile is closed")
            offset = page_id * PAGE_SIZE
            if offset + PAGE_SIZE > len(self._mmap):
                raise IndexError(
                    f"Page ID {page_id} exceeds preallocated mmap capacity"
                )
            self._mmap[offset : offset + PAGE_SIZE] = padded
            if page_id >= self._page_count:
                self._page_count = page_id + 1

    def allocate_page(self) -> int:
        """
        Allocates a new page and returns its Page ID.
        """
        with self._lock:
            new_pid = self._page_count
            self._page_count += 1
            if (new_pid + 1) * PAGE_SIZE > len(self._mmap):  # type: ignore[arg-type]
                raise RuntimeError(
                    "MMap capacity exceeded preallocated virtual address space"
                )
            return new_pid

    def sync(self) -> None:
        """Flushes memory mapped modifications to disk."""
        with self._lock:
            if self._mmap is not None:
                self._mmap.flush()
            if self._file_obj is not None:
                self._file_obj.flush()
                os.fsync(self._file_obj.fileno())

    def close(self) -> None:
        """Flushes and closes underlying file."""
        with self._lock:
            if self._mmap is not None:
                try:
                    self._mmap.flush()
                except Exception:
                    pass
                # Do not hard-close mmap if active memoryview pointers exist; let GC finalize
                self._mmap = None
            if self._file_obj is not None:
                try:
                    self._file_obj.close()
                except Exception:
                    pass
                self._file_obj = None
