#!/usr/bin/env python3
"""
Unit and Integration Tests for LSM-Tree Storage Engine.
Verifies BloomFilter membership & false positive rate, MemTable operations,
SSTable binary format & sparse indexing, and LSMTreeEngine Compaction.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from database.lsm import (
    BloomFilter,
    LSMTreeEngine,
    MemTable,
    SSTableReader,
    SSTableWriter,
)
from database.vfs import MemoryVFS


class TestBloomFilter(unittest.TestCase):
    """Tests for probabilistic Bloom Filter."""

    def test_bloom_filter_membership_and_serialization(self) -> None:
        bf = BloomFilter(expected_items=500, fp_rate=0.01)

        keys = [f"paper:arxiv:{i:05d}" for i in range(500)]
        for k in keys:
            bf.add(k)

        # Zero false negatives guarantee
        for k in keys:
            self.assertTrue(
                bf.contains(k), f"Key {k} should be present in Bloom filter"
            )

        # Test false positive rate on non-existent keys
        absent_keys = [f"nonexistent:key:{i:05d}" for i in range(500)]
        false_positives = sum(1 for k in absent_keys if bf.contains(k))
        fp_rate = false_positives / len(absent_keys)
        self.assertLess(
            fp_rate, 0.05, f"False positive rate {fp_rate} exceeded threshold"
        )

        # Test serialization roundtrip
        raw = bf.to_bytes()
        restored = BloomFilter.from_bytes(raw)
        for k in keys:
            self.assertTrue(restored.contains(k))
        for k in absent_keys[:50]:
            self.assertEqual(restored.contains(k), bf.contains(k))


class TestMemTable(unittest.TestCase):
    """Tests for in-memory MemTable sorted buffer."""

    def test_memtable_operations_and_scan(self) -> None:
        mem = MemTable(max_bytes=1024)

        mem.put("key:c", {"val": 3})
        mem.put("key:a", {"val": 1})
        mem.put("key:b", {"val": 2})

        # Test sorted items
        items = mem.items()
        self.assertEqual([k for k, _ in items], ["key:a", "key:b", "key:c"])

        # Test point lookups
        found, val = mem.get("key:b")
        self.assertTrue(found)
        self.assertEqual(val, {"val": 2})

        # Test delete / tombstone
        mem.delete("key:b")
        found, val = mem.get("key:b")
        self.assertTrue(found)
        self.assertIsNone(val)

        # Test range scan
        scanned = mem.scan(start_key="key:a", end_key="key:c")
        self.assertEqual(len(scanned), 2)
        self.assertEqual(scanned[0][0], "key:a")


class TestSSTable(unittest.TestCase):
    """Tests for SSTable binary layout, sparse indexing, and readers/writers."""

    def test_sstable_write_and_read(self) -> None:
        vfs = MemoryVFS()
        writer = SSTableWriter(file_path="test.sst", vfs=vfs, block_size=256)

        entries = [
            (f"key:{i:04d}", f"value_{i:04d}".encode("utf-8")) for i in range(100)
        ]
        bytes_written = writer.write(entries)
        self.assertGreater(bytes_written, 0)

        reader = SSTableReader(file_path="test.sst", vfs=vfs)
        self.assertGreaterEqual(len(reader.sparse_index), 2)

        # Point lookups
        found, val = reader.get("key:0042")
        self.assertTrue(found)
        self.assertEqual(val, "value_0042")

        # Absent key check (Bloom filter fast reject)
        found, val = reader.get("nonexistent_key")
        self.assertFalse(found)
        self.assertIsNone(val)

        # Full scan
        scanned = reader.scan_all()
        self.assertEqual(len(scanned), 100)
        self.assertEqual(scanned[0][0], "key:0000")
        self.assertEqual(scanned[-1][0], "key:0099")

        reader.close()


class TestLSMTreeEngine(unittest.TestCase):
    """Tests for LSMTreeEngine, automatic flushes, and Compaction."""

    def test_lsm_engine_put_get_flush_and_compaction(self) -> None:
        vfs = MemoryVFS()
        engine = LSMTreeEngine(
            data_dir="lsm_data",
            vfs=vfs,
            max_memtable_bytes=512,  # Small threshold to trigger auto flushes
        )

        # 1. Insert 50 records to trigger multiple SSTable flushes
        for i in range(50):
            engine.put(f"arxiv:{i:03d}", {"id": i, "category": "cs.CR"})

        self.assertGreaterEqual(len(engine.sstables), 1)

        # Verify all records can be retrieved across SSTables and Active MemTable
        for i in range(50):
            val = engine.get(f"arxiv:{i:03d}")
            self.assertIsNotNone(val, f"Record arxiv:{i:03d} should be found")
            self.assertEqual(val["id"], i)

        # 2. Update some records and delete some records
        engine.put("arxiv:010", {"id": 10, "category": "cs.CR", "updated": True})
        engine.delete("arxiv:020")
        engine.delete("arxiv:030")

        # Verify updated and deleted states
        self.assertTrue(engine.get("arxiv:010")["updated"])
        self.assertIsNone(engine.get("arxiv:020"))
        self.assertIsNone(engine.get("arxiv:030"))

        # Flush active memtable
        engine.flush_memtable()
        sstable_count_before = len(engine.sstables)
        self.assertGreaterEqual(sstable_count_before, 2)

        # 3. Perform Compaction
        compacted_path = engine.compact()
        self.assertIsNotNone(compacted_path)
        self.assertEqual(len(engine.sstables), 1)

        # Verify data integrity after Compaction (48 active records, 2 deleted)
        all_records = engine.scan_all()
        self.assertEqual(len(all_records), 48)
        self.assertTrue(engine.get("arxiv:010")["updated"])
        self.assertIsNone(engine.get("arxiv:020"))
        self.assertIsNone(engine.get("arxiv:030"))
        self.assertEqual(engine.get("arxiv:049")["id"], 49)

        engine.close()


if __name__ == "__main__":
    unittest.main()
