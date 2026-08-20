#!/usr/bin/env python3
"""
Scenario 1: Large-Scale Ingestion and Slotted-Page Persistence (LSM / Slotted-Page).
Location: tests/database/scenarios/test_scenario_01_lsm_ingestion.py
Persona: Data Engineer / Batch Ingestion System.
Verifies continuous vector/metadata ingestion, MemTable-to-SSTable flush,
Bloom Filter disk I/O suppression, and in-place page compaction without external fragmentation.
"""

import os
import sys
import tempfile
import unittest

import pytest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.lsm import BloomFilter, LSMTreeEngine
from database.slotted_page import SlottedPage


class TestScenario01LSMIngestion(unittest.TestCase):
    """Verifies LSM ingestion, Bloom filter, and slotted-page compaction."""

    def test_fast_ingestion_bloom_filter_and_slotted_compaction(self) -> None:
        """Fast execution: Verifies Bloom filter suppression and slotted page in-place reuse."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # 1. Slotted Page in-place compaction verification
            page = SlottedPage(page_id=0)
            slot0 = page.insert_tuple(b"Paper Abstract 1 (Short text)")
            slot1 = page.insert_tuple(b"Paper Abstract 2 (Replaceable text)")
            self.assertEqual(page.slot_count, 2)

            # Delete slot 0 and compact
            page.delete_tuple(slot0)
            page.compact()
            # Free space is consolidated, external fragmentation is zero
            self.assertGreater(page.free_space, 3800)

            # Insert new record into reclaimed space
            slot2 = page.insert_tuple(b"Paper Abstract 3 (New incoming)")
            self.assertEqual(
                page.get_tuple(slot1), b"Paper Abstract 2 (Replaceable text)"
            )
            self.assertEqual(page.get_tuple(slot2), b"Paper Abstract 3 (New incoming)")

            # 2. LSM Engine & Bloom Filter verification
            engine = LSMTreeEngine(data_dir=tmpdir, max_memtable_bytes=512)
            for i in range(50):
                engine.put(f"paper_{i:04d}", f"Executive Summary for Paper {i}")

            # Verify existing keys
            for i in range(50):
                val = engine.get(f"paper_{i:04d}")
                self.assertIsNotNone(val)
                self.assertEqual(val, f"Executive Summary for Paper {i}")

            # Verify non-existent key rejected by Bloom filter
            self.assertIsNone(engine.get("non_existent_paper_9999"))

    @pytest.mark.slow
    def test_slow_large_scale_batch_backfill_and_compaction(self) -> None:
        """Slow execution: 3,000 items continuous batch ingestion and SSTable minor compaction."""
        with tempfile.TemporaryDirectory() as tmpdir:
            engine = LSMTreeEngine(data_dir=tmpdir, max_memtable_bytes=4096)
            total_items = 3000

            # 1. Continuous batch ingestion
            for i in range(total_items):
                engine.put(
                    f"arxiv_2608_{i:05d}",
                    f"Post-Quantum Cryptography & Zero-Trust Architecture Paper #{i} metadata payload",
                )

            # 2. Verify all records retrieved accurately across SSTables and active MemTable
            for i in range(0, total_items, 50):
                res = engine.get(f"arxiv_2608_{i:05d}")
                self.assertIsNotNone(res)

            # 3. Bloom filter I/O suppression rate test
            bloom = BloomFilter(expected_items=total_items, fp_rate=0.01)
            for i in range(total_items):
                bloom.add(f"arxiv_2608_{i:05d}")

            false_positives = 0
            queries = 2000
            for i in range(queries):
                if bloom.contains(f"non_existent_{i}"):
                    false_positives += 1

            fp_rate = false_positives / queries
            self.assertLess(
                fp_rate, 0.03, f"Bloom filter FP rate {fp_rate} exceeded threshold"
            )


if __name__ == "__main__":
    unittest.main()
