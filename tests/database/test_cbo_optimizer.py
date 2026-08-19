#!/usr/bin/env python3
"""
Unit and Integration Tests for Advanced CBO (Cost-Based Optimizer).
Verifies Equi-Depth Histograms for skewed distributions, HyperLogLog NDV estimation,
and Dynamic Programming (DP) Join Order Optimization.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from database.planner import (
    ColumnStats,
    DPJoinOptimizer,
    EquiDepthHistogram,
    HyperLogLog,
    JoinPhysicalOperator,
    QueryPlanner,
    TableStats,
)


class TestEquiDepthHistogram(unittest.TestCase):
    """Tests for Equi-Depth histogram construction and selectivity estimation."""

    def test_skewed_distribution_selectivity(self) -> None:
        # Skewed distribution: mostly 2026 (70%), some 2025 (20%), few 2024 (10%)
        years = [2026] * 700 + [2025] * 200 + [2024] * 100
        hist = EquiDepthHistogram(num_buckets=5)
        hist.build(years)

        self.assertEqual(len(hist.buckets), 5)
        self.assertEqual(hist.total_count, 1000)

        # Equality selectivity for dominant value 2026
        sel_2026 = hist.estimate_selectivity("=", 2026)
        self.assertGreaterEqual(sel_2026, 0.40)  # Much higher than naive 1/3 = 0.33

        # Range selectivity
        sel_lt_2025 = hist.estimate_selectivity("<", 2025)
        self.assertAlmostEqual(sel_lt_2025, 0.10, delta=0.05)


class TestHyperLogLog(unittest.TestCase):
    """Tests for HyperLogLog probabilistic cardinality estimation."""

    def test_hll_cardinality_estimation(self) -> None:
        hll = HyperLogLog(p=8)  # 256 registers, ~6.5% standard error

        # Insert 1000 unique keys
        actual_cardinality = 1000
        for i in range(actual_cardinality):
            hll.add(f"paper-uuid-{i}")

        estimated = hll.estimate_cardinality()
        relative_error = abs(estimated - actual_cardinality) / actual_cardinality
        self.assertLess(relative_error, 0.10)  # Error within 10%

    def test_hll_merge(self) -> None:
        hll1 = HyperLogLog(p=8)
        hll2 = HyperLogLog(p=8)

        for i in range(500):
            hll1.add(f"key-{i}")
        for i in range(400, 1000):
            hll2.add(f"key-{i}")

        merged = hll1.merge(hll2)
        estimated = merged.estimate_cardinality()
        # Total unique keys = 1000
        relative_error = abs(estimated - 1000) / 1000
        self.assertLess(relative_error, 0.10)


class TestDPJoinOptimizer(unittest.TestCase):
    """Tests for Dynamic Programming Join Order Enumeration."""

    def setUp(self) -> None:
        self.stats_papers = TableStats("papers", total_rows=10000)
        self.stats_authors = TableStats("authors", total_rows=500)
        self.stats_paper_authors = TableStats("paper_authors", total_rows=20000)

        self.table_stats = {
            "papers": self.stats_papers,
            "authors": self.stats_authors,
            "paper_authors": self.stats_paper_authors,
        }

        self.join_conditions = [
            {
                "left_table": "papers",
                "left_column": "id",
                "right_table": "paper_authors",
                "right_column": "paper_id",
            },
            {
                "left_table": "authors",
                "left_column": "id",
                "right_table": "paper_authors",
                "right_column": "author_id",
            },
        ]

    def test_dp_3_table_join_ordering(self) -> None:
        plan = DPJoinOptimizer.optimize_join(
            tables=["papers", "authors", "paper_authors"],
            join_conditions=self.join_conditions,
            table_stats=self.table_stats,
            available_indexes={"paper_authors": {"paper_id", "author_id"}},
        )

        self.assertIsNotNone(plan)
        self.assertIsInstance(plan.operator, JoinPhysicalOperator)
        self.assertGreater(plan.cost, 0.0)

        # Plan dictionary serialization
        plan_dict = plan.to_dict()
        self.assertIn("operator", plan_dict)
        self.assertIn("cost", plan_dict)

    def test_query_planner_plan_join_api(self) -> None:
        plan = QueryPlanner.plan_join(
            tables=["papers", "authors"],
            join_conditions=[
                {
                    "left_table": "papers",
                    "left_column": "author_id",
                    "right_table": "authors",
                    "right_column": "id",
                }
            ],
            table_stats=self.table_stats,
            available_indexes={"authors": {"id"}},
        )
        self.assertIsNotNone(plan)
        self.assertGreater(plan.estimated_rows, 0)


class TestColumnStatsIntegration(unittest.TestCase):
    """Tests for ColumnStats integration with Histogram and HLL."""

    def test_column_stats_update(self) -> None:
        col = ColumnStats("category")
        values = ["crypto"] * 50 + ["network"] * 30 + ["zero-trust"] * 20
        col.update(values)

        self.assertEqual(col.total_count, 100)
        self.assertEqual(col.distinct_count, 3)
        self.assertIsNotNone(col.histogram)
        self.assertIsNotNone(col.hll)

        sel = col.estimate_selectivity("=", "crypto")
        self.assertGreaterEqual(sel, 0.30)


if __name__ == "__main__":
    unittest.main()
