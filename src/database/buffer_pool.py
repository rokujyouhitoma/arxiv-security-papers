#!/usr/bin/env python3
"""
2Q (Two-Queue) Buffer Pool Subsystem with Page Pinning.
Implements scan-pollution resistant page replacement using three queues:
- A1_in: FIFO queue for newly loaded pages.
- A1_out: Ghost FIFO queue tracking recent eviction page IDs.
- Am: LRU queue for frequently accessed hot pages.
Guarantees memory retention for pinned pages (pin_count > 0).
"""

import threading
from collections import OrderedDict
from typing import List, Optional


class BufferPoolError(Exception):
    """Raised when a buffer pool invariant or operation fails."""

    pass


class BufferFrame:
    """
    Represents an in-memory 4KB page frame with synchronization,
    pin counting, and dirty state tracking.
    """

    def __init__(
        self,
        page_id: int,
        data: bytearray,
        page_lsn: int = 0,
        is_dirty: bool = False,
    ) -> None:
        self.page_id = page_id
        self.data = data
        self.page_lsn = page_lsn
        self.is_dirty = is_dirty
        self.pin_count = 0

    def pin(self) -> int:
        """Increments pin count, protecting frame from eviction."""
        self.pin_count += 1
        return self.pin_count

    def unpin(self, is_dirty: bool = False) -> int:
        """Decrements pin count and optionally marks frame as dirty."""
        if self.pin_count > 0:
            self.pin_count -= 1
        if is_dirty:
            self.is_dirty = True
        return self.pin_count

    def is_pinned(self) -> bool:
        """Returns True if frame is pinned by one or more active queries."""
        return self.pin_count > 0

    def __repr__(self) -> str:
        return (
            f"<BufferFrame Page={self.page_id} PinCount={self.pin_count} "
            f"Dirty={self.is_dirty} LSN={self.page_lsn}>"
        )


class BufferPool2Q:
    """
    2Q Buffer Pool Manager.
    Protects cache from full-table scan pollution while maintaining high hit ratio
    for index roots and hot tuples.
    """

    def __init__(
        self,
        capacity: int = 64,
        kin_ratio: float = 0.25,
        kout_ratio: float = 0.50,
    ) -> None:
        if capacity < 2:
            capacity = 2
        self.capacity = capacity
        self.kin = max(1, int(capacity * kin_ratio))
        self.kout = max(1, int(capacity * kout_ratio))

        self._lock = threading.RLock()
        # A1_in: FIFO queue (page_id -> BufferFrame)
        self._a1_in: OrderedDict[int, BufferFrame] = OrderedDict()
        # A1_out: Ghost FIFO queue (page_id -> None)
        self._a1_out: OrderedDict[int, None] = OrderedDict()
        # Am: LRU queue (page_id -> BufferFrame)
        self._am: OrderedDict[int, BufferFrame] = OrderedDict()

    @property
    def total_cached_pages(self) -> int:
        """Returns the total number of resident data pages in memory."""
        with self._lock:
            return len(self._a1_in) + len(self._am)

    def get(self, page_id: int) -> Optional[BufferFrame]:
        """
        Retrieves a frame from buffer pool.
        Updates LRU position if in Am, or maintains FIFO order if in A1_in.
        """
        with self._lock:
            if page_id in self._am:
                # Hit in Am -> move to MRU
                self._am.move_to_end(page_id, last=True)
                return self._am[page_id]

            if page_id in self._a1_in:
                # Hit in A1_in -> remains in A1_in FIFO
                return self._a1_in[page_id]

            return None

    def put(self, page_id: int, frame: BufferFrame) -> Optional[BufferFrame]:
        """
        Inserts or updates a page frame in the buffer pool.
        Promotes page to Am if present in A1_out (re-referenced).
        Evicts a victim frame if capacity is exceeded.
        Returns the evicted BufferFrame (if any) so the caller can flush dirty data.
        """
        with self._lock:
            if page_id in self._am:
                self._am[page_id] = frame
                self._am.move_to_end(page_id, last=True)
                return None

            if page_id in self._a1_in:
                self._a1_in[page_id] = frame
                return None

            evicted: Optional[BufferFrame] = None
            if self.total_cached_pages >= self.capacity:
                evicted = self._evict_one()

            if page_id in self._a1_out:
                # Re-reference detected -> promote to Am LRU
                del self._a1_out[page_id]
                self._am[page_id] = frame
            else:
                # First-time access -> insert into A1_in FIFO
                self._a1_in[page_id] = frame

            return evicted

    def _evict_one(self) -> Optional[BufferFrame]:
        """
        Selects and removes one unpinned victim frame according to 2Q rules.
        """
        # Rule 1: If A1_in exceeds Kin, evict from A1_in into A1_out
        if len(self._a1_in) >= self.kin:
            victim_id = self._find_unpinned(self._a1_in)
            if victim_id is not None:
                victim = self._a1_in.pop(victim_id)
                self._add_to_a1_out(victim_id)
                return victim

        # Rule 2: Evict from Am LRU (oldest unpinned)
        victim_id = self._find_unpinned(self._am)
        if victim_id is not None:
            return self._am.pop(victim_id)

        # Rule 3: Fallback to A1_in if Am is fully pinned
        victim_id = self._find_unpinned(self._a1_in)
        if victim_id is not None:
            victim = self._a1_in.pop(victim_id)
            self._add_to_a1_out(victim_id)
            return victim

        # All resident pages are pinned!
        raise BufferPoolError("All buffer frames are currently pinned; cannot evict.")

    def _find_unpinned(self, queue: OrderedDict[int, BufferFrame]) -> Optional[int]:
        """Finds the first unpinned page ID in queue order (FIFO or LRU)."""
        for pid, frame in queue.items():
            if not frame.is_pinned():
                return pid
        return None

    def _add_to_a1_out(self, page_id: int) -> None:
        """Adds page_id to ghost FIFO queue A1_out."""
        if page_id in self._a1_out:
            del self._a1_out[page_id]
        self._a1_out[page_id] = None
        if len(self._a1_out) > self.kout:
            self._a1_out.popitem(last=False)

    def pin_page(self, page_id: int) -> BufferFrame:
        """Pins page by ID, returning the frame. Raises KeyError if not cached."""
        with self._lock:
            frame = self.get(page_id)
            if frame is None:
                raise KeyError(f"Page {page_id} is not resident in buffer pool")
            frame.pin()
            return frame

    def unpin_page(self, page_id: int, is_dirty: bool = False) -> None:
        """Unpins page by ID, optionally marking it dirty."""
        with self._lock:
            frame = self.get(page_id)
            if frame is not None:
                frame.unpin(is_dirty=is_dirty)

    def contains(self, page_id: int) -> bool:
        """Returns True if page is resident in A1_in or Am."""
        with self._lock:
            return page_id in self._a1_in or page_id in self._am

    def is_ghost(self, page_id: int) -> bool:
        """Returns True if page_id is in the A1_out ghost queue."""
        with self._lock:
            return page_id in self._a1_out

    def get_dirty_frames(self) -> List[BufferFrame]:
        """Returns list of all currently dirty resident frames."""
        with self._lock:
            dirty = [f for f in self._a1_in.values() if f.is_dirty]
            dirty.extend([f for f in self._am.values() if f.is_dirty])
            return dirty

    def clear(self) -> None:
        """Clears all queues and frames."""
        with self._lock:
            self._a1_in.clear()
            self._a1_out.clear()
            self._am.clear()
