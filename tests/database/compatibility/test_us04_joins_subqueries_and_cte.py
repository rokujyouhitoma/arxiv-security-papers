#!/usr/bin/env python3
"""
US-04: Relational Query Execution and Join Iterators in src/database.
Tests Volcano Execution Engine (SeqScan, NestedLoopJoin, HashJoin,
Filter, Projection, Limit) with complex relational data flows.
"""

import os
import sys
import unittest
from typing import Any, Dict, List

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database import (
    FilterIterator,
    HashJoinIterator,
    LimitIterator,
    NestedLoopJoinIterator,
    ProjectionIterator,
    SeqScanIterator,
)


class TestUS04JoinsSubqueriesAndCTE(unittest.TestCase):
    """Verifies relational Volcano engine iterators and join algorithms."""

    def setUp(self) -> None:
        self.authors_data: List[Dict[str, Any]] = [
            {"author_id": 1, "name": "Alice"},
            {"author_id": 2, "name": "Bob"},
            {"author_id": 3, "name": "Charlie"},
        ]
        self.papers_data: List[Dict[str, Any]] = [
            {"paper_id": 101, "author_id": 1, "citations": 50},
            {"paper_id": 102, "author_id": 1, "citations": 30},
            {"paper_id": 103, "author_id": 2, "citations": 80},
        ]

    def test_nested_loop_join_and_projection(self) -> None:
        scan_authors = SeqScanIterator(self.authors_data)

        # Join on author_id
        join_iter = NestedLoopJoinIterator(
            left_child=scan_authors,
            right_child_factory=lambda: SeqScanIterator(self.papers_data),
            join_predicate=lambda a, p: a["author_id"] == p["author_id"],
        )

        # Project name and citations
        proj_iter = ProjectionIterator(
            child=join_iter,
            columns=["name", "citations"],
        )

        results: List[Dict[str, Any]] = []
        proj_iter.open()
        while True:
            row = proj_iter.next()
            if row is None:
                break
            results.append(row)
        proj_iter.close()

        self.assertEqual(len(results), 3)
        self.assertEqual(results[0], {"name": "Alice", "citations": 50})
        self.assertEqual(results[1], {"name": "Alice", "citations": 30})
        self.assertEqual(results[2], {"name": "Bob", "citations": 80})

    def test_hash_join_and_limit_filter(self) -> None:
        scan_authors = SeqScanIterator(self.authors_data)
        scan_papers = SeqScanIterator(self.papers_data)

        # Hash Join on author_id
        hash_join = HashJoinIterator(
            probe_child=scan_papers,
            build_child=scan_authors,
            probe_key="author_id",
            build_key="author_id",
        )

        # Filter citations >= 50
        filter_iter = FilterIterator(
            child=hash_join,
            predicate=lambda row: bool(row.get("citations", 0) >= 50),
        )

        # Limit 1
        limit_iter = LimitIterator(child=filter_iter, limit=1)

        results: List[Dict[str, Any]] = []
        limit_iter.open()
        while True:
            row = limit_iter.next()
            if row is None:
                break
            results.append(row)
        limit_iter.close()

        self.assertEqual(len(results), 1)
        self.assertGreaterEqual(results[0]["citations"], 50)


if __name__ == "__main__":
    unittest.main()
