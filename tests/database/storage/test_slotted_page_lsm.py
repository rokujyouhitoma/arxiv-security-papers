#!/usr/bin/env python3
"""
Integration Tests for Slotted-Page Binary Format with LSM-Tree SSTable Storage Engine.
Validates Issue 126 requirements:
- 4KB Slotted-Page block formatting inside SSTables
- Sparse index binary search and Bloom filter pruning
- WAL append-only persistence and crash recovery replay
- Compaction and tombstone garbage collection
"""

import unittest

from database.lsm import LSMTreeEngine, SSTableReader, SSTableWriter
from database.storage.slotted_page import PAGE_SIZE
from database.vfs import MemoryVFS


class TestSlottedPageLSM(unittest.TestCase):
    """Verifies integration between 4KB SlottedPage and LSM-Tree engine."""

    def setUp(self) -> None:
        self.vfs = MemoryVFS()
        self.test_dir = "test_lsm_slotted"

    def test_sstable_with_slotted_pages(self) -> None:
        """Verifies SSTable written with 4KB SlottedPage blocks can be read correctly."""
        sst_path = f"{self.test_dir}/slotted_test.sst"
        writer = SSTableWriter(
            file_path=sst_path,
            vfs=self.vfs,
            use_slotted_page=True,
        )

        entries = [
            (f"cwe:cwe-{i:04d}", f'{{"id": {i}, "name": "Vuln-{i}"}}'.encode("utf-8"))
            for i in range(1, 150)
        ]
        bytes_written = writer.write(entries)
        self.assertGreater(bytes_written, PAGE_SIZE)

        reader = SSTableReader(file_path=sst_path, vfs=self.vfs)
        # Verify first, middle, and last keys
        found, val = reader.get("cwe:cwe-0001")
        self.assertTrue(found)
        self.assertEqual(val, {"id": 1, "name": "Vuln-1"})

        found, val = reader.get("cwe:cwe-0075")
        self.assertTrue(found)
        self.assertEqual(val, {"id": 75, "name": "Vuln-75"})

        found, val = reader.get("cwe:cwe-0149")
        self.assertTrue(found)
        self.assertEqual(val, {"id": 149, "name": "Vuln-149"})

        # Absent key check with Bloom Filter
        found, _ = reader.get("cwe:cwe-9999")
        self.assertFalse(found)

        # scan_all check
        all_entries = reader.scan_all()
        self.assertEqual(len(all_entries), 149)
        reader.close()

    def test_lsm_engine_wal_and_crash_recovery(self) -> None:
        """Verifies WAL persistence and recovery into MemTable on restart."""
        engine1 = LSMTreeEngine(
            data_dir=self.test_dir,
            vfs=self.vfs,
            max_memtable_bytes=100000,
            use_slotted_page=True,
            enable_wal=True,
        )
        engine1.put("paper:2401.0001", {"title": "Zero-Trust Architecture"})
        engine1.put("paper:2401.0002", {"title": "Post-Quantum Cryptography"})
        engine1.delete("paper:2401.0001")

        # Simulate abrupt restart without flush (WAL must replay)
        engine2 = LSMTreeEngine(
            data_dir=self.test_dir,
            vfs=self.vfs,
            max_memtable_bytes=100000,
            use_slotted_page=True,
            enable_wal=True,
        )
        self.assertIsNone(engine2.get("paper:2401.0001"))
        val = engine2.get("paper:2401.0002")
        self.assertIsNotNone(val)
        self.assertEqual(val.get("title"), "Post-Quantum Cryptography")

    def test_lsm_engine_flush_and_compaction(self) -> None:
        """Verifies MemTable flushing to slotted SSTable and multi-SSTable compaction."""
        engine = LSMTreeEngine(
            data_dir=self.test_dir,
            vfs=self.vfs,
            max_memtable_bytes=512,  # Low threshold to trigger frequent flush
            use_slotted_page=True,
            enable_wal=True,
        )

        for i in range(50):
            engine.put(f"key:{i:03d}", {"val": i})

        self.assertGreater(len(engine.sstables), 0)

        # Verify point lookup across SSTables
        for i in range(50):
            res = engine.get(f"key:{i:03d}")
            self.assertEqual(res, {"val": i})

        # Compact all SSTables
        compacted_path = engine.compact()
        self.assertIsNotNone(compacted_path)
        self.assertEqual(len(engine.sstables), 1)

        # Lookup post-compaction
        for i in range(50):
            res = engine.get(f"key:{i:03d}")
            self.assertEqual(res, {"val": i})


if __name__ == "__main__":
    unittest.main()
