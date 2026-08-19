#!/usr/bin/env python3
"""
Unit and Integration Tests for 2Q Buffer Pool and Pin/Unpin Lifecycle.
Verifies scan pollution resistance, A1_in/A1_out/Am queue transitions,
pinning eviction guards, and Pager integration.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from database.buffer_pool import BufferFrame, BufferPool2Q, BufferPoolError
from database.pager import Pager
from database.vfs import MemoryVFS


class TestBufferPool2Q(unittest.TestCase):
    """Tests for core 2Q Buffer Pool algorithm."""

    def test_2q_scan_pollution_resistance(self) -> None:
        """
        Verifies that a large sequential scan (reading many one-off pages)
        does NOT evict hot pages stored in Am (LRU).
        """
        pool = BufferPool2Q(capacity=10, kin_ratio=0.3, kout_ratio=0.5)

        # 1. Warm up hot pages (Pages 1, 2, 3) and promote them to Am
        for pid in [1, 2, 3]:
            pool.put(pid, BufferFrame(page_id=pid, data=bytearray(b"hot" * 10)))

        # Evict Pages 1, 2, 3 into A1_out by inserting dummy pages
        for dummy_id in range(100, 110):
            pool.put(dummy_id, BufferFrame(page_id=dummy_id, data=bytearray(4096)))

        # Re-reference Pages 1, 2, 3 to promote all of them to Am
        for pid in [1, 2, 3]:
            pool.put(pid, BufferFrame(page_id=pid, data=bytearray(b"hot" * 10)))

        # Verify all hot pages are resident in Am
        for pid in [1, 2, 3]:
            self.assertIsNotNone(pool.get(pid))

        # 2. Perform a massive full-table scan (Pages 200 .. 250)
        for scan_id in range(200, 250):
            pool.put(scan_id, BufferFrame(page_id=scan_id, data=bytearray(4096)))

        # 3. Verify hot pages (1, 2, 3) are STILL resident in cache!
        for pid in [1, 2, 3]:
            cached = pool.get(pid)
            self.assertIsNotNone(
                cached, f"Hot page {pid} should survive sequential scan in 2Q"
            )

    def test_2q_lifecycle_and_ghost_queue(self) -> None:
        """
        Verifies A1_in -> A1_out -> Am transition lifecycle.
        """
        pool = BufferPool2Q(capacity=4, kin_ratio=0.25, kout_ratio=0.5)

        # Insert Page 10 into A1_in
        f10 = BufferFrame(page_id=10, data=bytearray(4096))
        pool.put(10, f10)
        self.assertTrue(pool.contains(10))
        self.assertFalse(pool.is_ghost(10))

        # Fill capacity to force Page 10 into ghost A1_out
        for pid in [20, 30, 40, 50]:
            pool.put(pid, BufferFrame(page_id=pid, data=bytearray(4096)))

        self.assertFalse(pool.contains(10))
        self.assertTrue(pool.is_ghost(10))

        # Re-reference Page 10 -> Should promote to Am
        pool.put(10, BufferFrame(page_id=10, data=bytearray(4096)))
        self.assertTrue(pool.contains(10))
        self.assertFalse(pool.is_ghost(10))

    def test_pin_unpin_eviction_guard(self) -> None:
        """
        Verifies that pinned frames (pin_count > 0) cannot be evicted.
        """
        pool = BufferPool2Q(capacity=2)

        f1 = BufferFrame(page_id=1, data=bytearray(4096))
        f2 = BufferFrame(page_id=2, data=bytearray(4096))
        pool.put(1, f1)
        pool.put(2, f2)

        # Pin Page 1
        pool.pin_page(1)
        self.assertTrue(f1.is_pinned())

        # Put Page 3 -> Should evict Page 2 (unpinned), keeping Page 1
        f3 = BufferFrame(page_id=3, data=bytearray(4096))
        evicted = pool.put(3, f3)
        self.assertIsNotNone(evicted)
        self.assertEqual(evicted.page_id, 2)
        self.assertTrue(pool.contains(1))
        self.assertTrue(pool.contains(3))

        # Pin Page 3 as well
        pool.pin_page(3)

        # Now all resident pages (1, 3) are pinned -> attempting to put Page 4 should fail
        with self.assertRaises(BufferPoolError):
            pool.put(4, BufferFrame(page_id=4, data=bytearray(4096)))

        # Unpin Page 1
        pool.unpin_page(1)
        self.assertFalse(f1.is_pinned())

        # Now putting Page 4 should succeed by evicting Page 1
        evicted2 = pool.put(4, BufferFrame(page_id=4, data=bytearray(4096)))
        self.assertIsNotNone(evicted2)
        self.assertEqual(evicted2.page_id, 1)


class TestPagerBufferPoolIntegration(unittest.TestCase):
    """Tests for Pager integration with 2Q Buffer Pool and Pin/Unpin."""

    def test_pager_pin_and_steal_eviction(self) -> None:
        vfs = MemoryVFS()
        pager = Pager(
            file_path="test_2q.vdb",
            vfs=vfs,
            cache_capacity=4,
            use_wal=True,
            auto_recover=False,
        )

        # Write pages 0, 1, 2
        pager.write_page(0, b"Page 0 Data")
        pager.write_page(1, b"Page 1 Data")
        pager.write_page(2, b"Page 2 Data")

        # Pin Page 0
        p0 = pager.pin_page(0)
        self.assertTrue(p0.is_pinned())

        # Write more pages (3, 4, 5) to cause evictions
        pager.write_page(3, b"Page 3 Data")
        pager.write_page(4, b"Page 4 Data")
        pager.write_page(5, b"Page 5 Data")

        # Page 0 must still be pinned in cache
        cached_p0 = pager.cache.get(0)
        self.assertIsNotNone(cached_p0)
        self.assertTrue(cached_p0.is_pinned())

        # Unpin Page 0
        pager.unpin_page(0)
        self.assertFalse(cached_p0.is_pinned())

        # Verify reading all pages from disk/cache returns correct data
        self.assertEqual(bytes(pager.read_page(0))[:11], b"Page 0 Data")
        self.assertEqual(bytes(pager.read_page(1))[:11], b"Page 1 Data")
        self.assertEqual(bytes(pager.read_page(5))[:11], b"Page 5 Data")


if __name__ == "__main__":
    unittest.main()
