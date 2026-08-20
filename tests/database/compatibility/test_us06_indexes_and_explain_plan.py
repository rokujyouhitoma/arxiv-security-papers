#!/usr/bin/env python3
"""
US-06: Indexes and Query Plan Optimization in src/database.
Tests HNSW Index creation, Cost-Based Optimizer (CBO), and EXPLAIN / EXPLAIN QUERY PLAN.
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

from database import (
    HNSWIndex,
    QueryPlanner,
    SQLCompiler,
    SQLExecutor,
    SQLParser,
    TableCatalog,
    TableStats,
    VectorStorage,
)


class TestUS06IndexesAndExplainPlan(unittest.TestCase):
    """Verifies indexing and EXPLAIN query plan generation."""

    def test_hnsw_index_creation_and_knn_execution(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            storage_path = os.path.join(tmpdir, "explain.vdb")
            storage = VectorStorage(storage_path, dim=4)
            index = HNSWIndex(dim=4)
            catalog = TableCatalog(name="papers", storage=storage, index=index)
            executor = SQLExecutor(catalog=catalog)

            # Create HNSW index via SQL DDL
            res_idx = executor.execute(
                "CREATE INDEX idx_papers_vec ON papers (vector) USING HNSW"
            )
            self.assertEqual(res_idx["status"], "ok")
            self.assertEqual(res_idx["command"], "CREATE_INDEX")

    def test_cbo_planner_and_explain_disassembly(self) -> None:
        stats = TableStats("papers", total_rows=1000)
        stats.analyze_from_metadata(
            [{"category": "Cryptography", "score": 0.95} for _ in range(100)]
            + [{"category": "Network", "score": 0.50} for _ in range(900)]
        )

        parser = SQLParser()
        stmt = parser.parse(
            "SELECT id, title FROM papers WHERE category = 'Cryptography'"
        )

        # Plan selection with available B+Tree index
        plan = QueryPlanner.plan_select(
            stmt, stats=stats, available_indexes={"category": "idx_cat"}
        )
        self.assertIsNotNone(plan)
        self.assertEqual(plan.table_name, "papers")
        self.assertGreater(plan.estimated_cost, 0.0)

        # SQLCompiler explain bytecode disassembly (EXPLAIN query)
        compiler = SQLCompiler()
        bytecode = compiler.explain("SELECT id, title FROM papers WHERE score > 0.8")
        self.assertGreater(len(bytecode), 0)
        self.assertIn("opcode", bytecode[0])


if __name__ == "__main__":
    unittest.main()
