#!/usr/bin/env python3
"""
Unit and Integration Tests for Volcano Streaming Iterators and Vectorized Execution Engine.
Verifies open() / next() / close() pipeline execution, HashJoin / NLJ,
and 1024-row ColumnBatch vectorized filtering and aggregation.
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

from database.engine import (
    FilterIterator,
    HashJoinIterator,
    IndexScanIterator,
    LimitIterator,
    NestedLoopJoinIterator,
    ProjectionIterator,
    SeqScanIterator,
    VectorizedAggregation,
    VectorizedFilter,
    VectorizedProjection,
    VectorizedScan,
)


class TestVolcanoStreamingIterators(unittest.TestCase):
    """Tests for Volcano-style pull-based streaming execution model."""

    def setUp(self) -> None:
        self.papers = [
            {
                "id": 1,
                "title": "Zero-Trust Architecture",
                "year": 2024,
                "citations": 120,
            },
            {
                "id": 2,
                "title": "Post-Quantum Cryptography",
                "year": 2025,
                "citations": 85,
            },
            {"id": 3, "title": "Autonomous LLM Agents", "year": 2026, "citations": 230},
            {
                "id": 4,
                "title": "Hardware Security in IoT",
                "year": 2025,
                "citations": 45,
            },
            {"id": 5, "title": "Side-Channel Defense", "year": 2026, "citations": 310},
        ]
        self.authors = [
            {"author_id": 101, "paper_id": 2, "name": "Alice Smith"},
            {"author_id": 102, "paper_id": 3, "name": "Bob Jones"},
            {"author_id": 103, "paper_id": 5, "name": "Charlie Brown"},
        ]

    def test_seq_scan_filter_project_limit_pipeline(self) -> None:
        # Pipeline: SeqScan -> Filter(year >= 2025) -> Project([title, citations]) -> Limit(limit=2, offset=1)
        scan = SeqScanIterator(self.papers)
        filtered = FilterIterator(
            scan, predicate=lambda r: int(r.get("year", 0)) >= 2025
        )
        projected = ProjectionIterator(filtered, columns=["title", "citations"])
        limited = LimitIterator(projected, limit=2, offset=1)

        limited.open()
        rows = []
        while True:
            row = limited.next()
            if row is None:
                break
            rows.append(row)
        limited.close()

        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["title"], "Autonomous LLM Agents")
        self.assertEqual(rows[0]["citations"], 230)
        self.assertEqual(rows[1]["title"], "Hardware Security in IoT")
        self.assertEqual(rows[1]["citations"], 45)

    def test_index_scan_iterator(self) -> None:
        index_data = [
            {"key": 10, "val": "A"},
            {"key": 20, "val": "B"},
            {"key": 30, "val": "C"},
        ]
        scanner = IndexScanIterator(
            index_data, filter_func=lambda r: int(r["key"]) > 10
        )
        scanner.open()

        res = []
        while True:
            row = scanner.next()
            if row is None:
                break
            res.append(row)
        scanner.close()

        self.assertEqual(len(res), 2)
        self.assertEqual(res[0]["key"], 20)

    def test_hash_join_iterator(self) -> None:
        probe_scan = SeqScanIterator(self.papers)
        build_scan = SeqScanIterator(self.authors)

        join = HashJoinIterator(
            probe_child=probe_scan,
            build_child=build_scan,
            probe_key="id",
            build_key="paper_id",
        )

        join.open()
        joined_rows = []
        while True:
            row = join.next()
            if row is None:
                break
            joined_rows.append(row)
        join.close()

        self.assertEqual(len(joined_rows), 3)
        titles = [r["title"] for r in joined_rows]
        self.assertIn("Post-Quantum Cryptography", titles)
        self.assertIn("Autonomous LLM Agents", titles)
        self.assertIn("Side-Channel Defense", titles)

    def test_nested_loop_join_iterator(self) -> None:
        probe_scan = SeqScanIterator(self.papers)

        join = NestedLoopJoinIterator(
            left_child=probe_scan,
            right_child_factory=lambda: SeqScanIterator(self.authors),
            join_predicate=lambda left_r, right_r: left_r["id"] == right_r["paper_id"],
        )

        join.open()
        joined_rows = []
        while True:
            row = join.next()
            if row is None:
                break
            joined_rows.append(row)
        join.close()

        self.assertEqual(len(joined_rows), 3)


class TestVectorizedBatchExecution(unittest.TestCase):
    """Tests for 1024-row ColumnBatch vectorized execution and aggregation."""

    def setUp(self) -> None:
        # Create 2500 synthetic rows
        self.rows = [
            {
                "id": i,
                "score": float(i * 1.5),
                "status": "ACTIVE" if i % 2 == 0 else "INACTIVE",
            }
            for i in range(2500)
        ]

    def test_vectorized_scan_batches(self) -> None:
        scan = VectorizedScan(self.rows, batch_size=1024)
        scan.open()

        batches = []
        while True:
            b = scan.next_batch()
            if b is None:
                break
            batches.append(b)
        scan.close()

        self.assertEqual(len(batches), 3)
        self.assertEqual(batches[0].num_rows, 1024)
        self.assertEqual(batches[1].num_rows, 1024)
        self.assertEqual(batches[2].num_rows, 452)

    def test_vectorized_filter_and_projection(self) -> None:
        scan = VectorizedScan(self.rows, batch_size=1024)
        # Filter: score > 3000
        filtered = VectorizedFilter(
            scan,
            predicate=lambda batch: [s > 3000.0 for s in batch.get_column("score")],
        )
        projected = VectorizedProjection(filtered, columns=["id", "score"])

        projected.open()
        output_rows = []
        while True:
            b = projected.next_batch()
            if b is None:
                break
            output_rows.extend(b.to_rows())
        projected.close()

        # i * 1.5 > 3000 => i > 2000 => ids 2001 to 2499 => 499 rows
        self.assertEqual(len(output_rows), 499)
        self.assertTrue(all("status" not in r for r in output_rows))
        self.assertGreater(output_rows[0]["score"], 3000.0)

    def test_vectorized_aggregation(self) -> None:
        scan = VectorizedScan(self.rows, batch_size=1024)

        count = VectorizedAggregation.aggregate(scan, "id", "COUNT")
        self.assertEqual(count, 2500)

        min_val = VectorizedAggregation.aggregate(scan, "id", "MIN")
        self.assertEqual(min_val, 0)

        max_val = VectorizedAggregation.aggregate(scan, "id", "MAX")
        self.assertEqual(max_val, 2499)

        # Sum of 0..2499
        expected_sum = float(sum(i * 1.5 for i in range(2500)))
        actual_sum = VectorizedAggregation.aggregate(scan, "score", "SUM")
        self.assertAlmostEqual(actual_sum or 0.0, expected_sum, delta=1.0)


if __name__ == "__main__":
    unittest.main()
