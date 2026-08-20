#!/usr/bin/env python3
"""
Unit and Integration Tests for CoW (Copy-on-Write) B-Tree and MMap Zero-Copy Engine.
Verifies mmap memoryview zero-copy, Double Meta Page Ping-Pong, shadow-paged CoW B-Tree,
and lock-free SWMR (Single-Writer Multi-Reader) snapshot isolation.
"""

import os
import sys
import tempfile
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.cow import CoWBTree, CoWEngine, MetaPage, MMapFile


class TestMMapFile(unittest.TestCase):
    """Tests for MMapFile zero-copy page views and dynamic allocation."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.temp_dir.name, "test_mmap.vdb")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_mmap_page_allocation_and_zero_copy_view(self) -> None:
        mmap_file = MMapFile(file_path=self.db_path, initial_pages=4)
        self.assertGreaterEqual(mmap_file.page_count, 2)

        # Write data to page 2
        payload = b"TEST_PAYLOAD_DATA" + b"\x00" * (4096 - 17)
        mmap_file.write_page(2, payload)

        # Zero-copy memoryview read
        view = mmap_file.read_page_view(2)
        self.assertIsInstance(view, memoryview)
        self.assertEqual(bytes(view[:17]), b"TEST_PAYLOAD_DATA")

        # Dynamic page allocation
        pid = mmap_file.allocate_page()
        self.assertGreaterEqual(pid, 3)
        self.assertGreaterEqual(mmap_file.page_count, 4)

        mmap_file.close()


class TestMetaPagePingPong(unittest.TestCase):
    """Tests for Double Meta Page Ping-Pong commit and CRC32 integrity."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.temp_dir.name, "test_meta.vdb")
        self.mmap_file = MMapFile(file_path=self.db_path, initial_pages=4)

    def tearDown(self) -> None:
        self.mmap_file.close()
        self.temp_dir.cleanup()

    def test_meta_ping_pong_commits(self) -> None:
        # Initial state
        meta0 = MetaPage.load_latest(self.mmap_file)
        self.assertEqual(meta0.tx_id, 0)

        # Commit tx 1 (slot 1)
        meta1, slot1 = MetaPage.commit_next(
            self.mmap_file, next_tx_id=1, root_page_id=2, page_count=4
        )
        self.assertEqual(slot1, 1)
        self.assertEqual(meta1.tx_id, 1)
        self.assertEqual(meta1.root_page_id, 2)

        # Verify load_latest selects tx 1
        loaded = MetaPage.load_latest(self.mmap_file)
        self.assertEqual(loaded.tx_id, 1)
        self.assertEqual(loaded.root_page_id, 2)

        # Commit tx 2 (slot 0)
        meta2, slot2 = MetaPage.commit_next(
            self.mmap_file, next_tx_id=2, root_page_id=3, page_count=5
        )
        self.assertEqual(slot2, 0)
        self.assertEqual(meta2.tx_id, 2)

        loaded2 = MetaPage.load_latest(self.mmap_file)
        self.assertEqual(loaded2.tx_id, 2)
        self.assertEqual(loaded2.root_page_id, 3)


class TestCoWBTree(unittest.TestCase):
    """Tests for CoW B-Tree shadow-paging and in-order range scans."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.temp_dir.name, "test_btree.vdb")
        self.mmap_file = MMapFile(file_path=self.db_path, initial_pages=8)
        self.btree = CoWBTree(self.mmap_file)

    def tearDown(self) -> None:
        self.mmap_file.close()
        self.temp_dir.cleanup()

    def test_cow_insert_split_and_scan(self) -> None:
        root_pid = 0

        # Insert 100 sorted keys to trigger node splits
        for i in range(100):
            k = f"key:{i:04d}"
            v = f"val:{i:04d}".encode("utf-8")
            root_pid, retired = self.btree.insert(root_pid, k, v)
            self.assertGreater(root_pid, 0)

        # Verify point lookups
        for i in range(100):
            k = f"key:{i:04d}"
            expected = f"val:{i:04d}".encode("utf-8")
            actual = self.btree.get(root_pid, k)
            self.assertEqual(actual, expected)

        # Verify absent key
        self.assertIsNone(self.btree.get(root_pid, "key:9999"))

        # Verify range scan
        scanned = self.btree.scan(root_pid, start_key="key:0010", end_key="key:0020")
        self.assertEqual(len(scanned), 10)
        self.assertEqual(scanned[0][0], "key:0010")
        self.assertEqual(scanned[-1][0], "key:0019")

        # Verify delete
        new_root, _ = self.btree.delete(root_pid, "key:0015")
        self.assertIsNone(self.btree.get(new_root, "key:0015"))
        # Old root still has the key! (Immutability guarantee)
        self.assertEqual(self.btree.get(root_pid, "key:0015"), b"val:0015")


class TestCoWEngine(unittest.TestCase):
    """Tests for CoWEngine SWMR concurrency and rollback durability."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.temp_dir.name, "test_engine.vdb")
        self.engine = CoWEngine(db_path=self.db_path)

    def tearDown(self) -> None:
        self.engine.close()
        self.temp_dir.cleanup()

    def test_swmr_lock_free_snapshot_isolation(self) -> None:
        # Populate initial database
        self.engine.put("paper:001", {"title": "Zero-Trust Architecture", "year": 2024})
        self.engine.put("paper:002", {"title": "LSM-Tree Security", "year": 2025})

        # Reader 1 starts a transaction and gets snapshot v2
        reader1 = self.engine.begin_read()
        self.assertEqual(reader1.tx_id, 2)
        self.assertEqual(reader1.get("paper:001")["title"], "Zero-Trust Architecture")

        # Writer updates paper:001 and inserts paper:003, then commits (tx_id 3 & 4)
        self.engine.put(
            "paper:001", {"title": "Zero-Trust Architecture (Updated)", "year": 2026}
        )
        self.engine.put("paper:003", {"title": "Quantum Safe Crypto", "year": 2026})

        # Reader 1 still sees snapshot v2 without any lock!
        self.assertEqual(reader1.get("paper:001")["title"], "Zero-Trust Architecture")
        self.assertIsNone(reader1.get("paper:003"))

        # New Reader 2 sees latest committed snapshot v4
        reader2 = self.engine.begin_read()
        self.assertEqual(reader2.tx_id, 4)
        self.assertEqual(
            reader2.get("paper:001")["title"], "Zero-Trust Architecture (Updated)"
        )
        self.assertIsNotNone(reader2.get("paper:003"))

    def test_rollback_durability(self) -> None:
        self.engine.put("key:a", "val_a")
        init_tx_id = self.engine.latest_meta.tx_id

        # Start write transaction and rollback
        tx = self.engine.begin_write()
        tx.put("key:b", "val_b")
        tx.rollback()

        self.assertEqual(self.engine.latest_meta.tx_id, init_tx_id)
        self.assertIsNone(self.engine.get("key:b"))
        self.assertEqual(self.engine.get("key:a"), "val_a")


if __name__ == "__main__":
    unittest.main()
