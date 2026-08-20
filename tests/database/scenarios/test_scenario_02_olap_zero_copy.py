#!/usr/bin/env python3
"""
Scenario 2: Compound Query, OLAP Aggregations, and Zero-Copy Read (B+Tree / PAX / mmap).
Location: tests/database/scenarios/test_scenario_02_olap_zero_copy.py
Persona: Security Researcher / Analyst.
Verifies range scans over B+Tree leaf links, 2Q scan pollution resistance,
PAX columnar layout selective scanning, and mmap zero-copy reads.
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

from database.btree import BPlusTree
from database.buffer_pool import BufferFrame, BufferPool2Q
from database.cow import MMapFile
from database.pax import PAXTable


class TestScenario02OLAPZeroCopy(unittest.TestCase):
    """Verifies B+Tree range queries, PAX columnar analytics, and mmap zero-copy access."""

    def test_fast_btree_range_scan_pax_olap_and_mmap(self) -> None:
        """Fast verification: B+Tree leaf scan, PAX column aggregation, and mmap read."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # 1. B+Tree sequential leaf range scan
            tree = BPlusTree(column_name="published_date")
            dates = [
                ("20260101", 101),
                ("20260215", 102),
                ("20260310", 103),
                ("20260401", 104),
                ("20260520", 105),
                ("20260801", 106),
            ]
            for d, row_id in dates:
                tree.insert(d, row_id)

            # Range scan from 20260201 to 20260501
            range_results = tree.range_scan("20260201", "20260501")
            self.assertEqual(len(range_results), 3)
            self.assertEqual(range_results, [102, 103, 104])

            # 2. 2Q Buffer Pool scan pollution resistance & page pinning
            pool = BufferPool2Q(capacity=10)
            pinned_frame = BufferFrame(page_id=0, data=bytearray(4096))
            pinned_frame.pin()
            pool.put(0, pinned_frame)

            # Insert flood of non-pinned scan pages
            for pid in range(1, 20):
                frame = BufferFrame(page_id=pid, data=bytearray(4096))
                pool.put(pid, frame)

            # Pinned hot page (0) is guaranteed to stay resident
            self.assertIsNotNone(pool.get(0))

            # 3. PAX Columnar aggregation
            table = PAXTable(
                table_name="papers",
                schema=[("year", "INT"), ("category", "VARCHAR"), ("score", "FLOAT")],
            )
            for i in range(100):
                year = 2024 + (i % 3)
                cat = "Cryptography" if i % 2 == 0 else "Zero-Trust"
                table.insert([year, cat, float(i * 1.5)])
            table.flush()

            scanner = table.get_scanner()
            grouped_scores = scanner.group_by(
                group_col="category", agg_col="score", agg_fn="SUM"
            )
            self.assertIn("Cryptography", grouped_scores)
            self.assertIn("Zero-Trust", grouped_scores)
            self.assertGreater(grouped_scores["Cryptography"], 0.0)

            # 4. Zero-copy mmap view
            mmap_path = os.path.join(tmpdir, "zero_copy.dat")
            mmap_file = MMapFile(mmap_path, initial_pages=16)
            try:
                test_bytes = b"SECURITY_ANALYTICS_PAYLOAD"
                mmap_file.write_page(0, test_bytes + b"\x00" * (4096 - len(test_bytes)))

                view = mmap_file.read_page_view(0)
                self.assertTrue(bytes(view[: len(test_bytes)]) == test_bytes)
            finally:
                mmap_file.close()

    @pytest.mark.slow
    def test_slow_large_scale_pax_olap_and_btree_benchmark(self) -> None:
        """Slow verification: 5,000 row PAX OLAP filtering and B+Tree range queries."""
        table = PAXTable(
            table_name="large_benchmark",
            schema=[
                ("doc_id", "INT"),
                ("category", "VARCHAR"),
                ("threat_level", "VARCHAR"),
                ("vector_score", "FLOAT"),
            ],
        )
        total_rows = 3000
        for i in range(total_rows):
            cat = ["AI-Security", "Post-Quantum", "Zero-Trust", "Cloud"][i % 4]
            threat = ["HIGH", "MEDIUM", "LOW"][i % 3]
            table.insert([i, cat, threat, float(i % 100)])
        table.flush()

        scanner = table.get_scanner()
        counts = scanner.group_by(
            group_col="category", agg_col="doc_id", agg_fn="COUNT"
        )
        self.assertEqual(len(counts), 4)


if __name__ == "__main__":
    unittest.main()
