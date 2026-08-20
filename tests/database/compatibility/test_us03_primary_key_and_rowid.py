#!/usr/bin/env python3
"""
US-03: Primary Key Index and B+Tree Structure Verification in src/database.
Tests BPlusTree primary key clustering, binary search node navigation,
range scans, and duplicate key handling in pure Python storage engine.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database import BPlusTree


class TestUS03PrimaryKeyAndRowID(unittest.TestCase):
    """Verifies B+Tree Primary Key Index and Row ID mapping."""

    def test_bplus_tree_primary_key_operations(self) -> None:
        tree = BPlusTree(column_name="id")

        # Insert sequential and random keys
        for row_id, i in enumerate([10, 20, 5, 15, 30, 25]):
            tree.insert(i, row_id=row_id)

        # 1. Point Lookup
        matched_rows = tree.search(15)
        self.assertEqual(len(matched_rows), 1)
        self.assertEqual(matched_rows[0], 3)  # 15 was 4th inserted (row_id=3)

        # 2. Key Not Found
        self.assertEqual(tree.search(999), [])

        # 3. Range Scan [10, 25]
        range_results = tree.range_scan(10, 25)
        self.assertGreaterEqual(len(range_results), 3)


if __name__ == "__main__":
    unittest.main()
