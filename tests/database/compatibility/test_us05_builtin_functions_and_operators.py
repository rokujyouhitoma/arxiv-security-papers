#!/usr/bin/env python3
"""
US-05: Built-in Functions, KNN Vector Similarity, and Operators in src/database.
Tests SQLExecutor with custom vector distance functions (KNN),
LIKE pattern matching, and complex boolean expressions.
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

from database import HNSWIndex, SQLExecutor, TableCatalog, VectorStorage


class TestUS05BuiltinFunctionsAndOperators(unittest.TestCase):
    """Verifies vector functions and expression evaluations in SQLExecutor."""

    def test_knn_similarity_function_and_like_operator(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            storage_path = os.path.join(tmpdir, "functions.vdb")
            storage = VectorStorage(storage_path, dim=4)
            index = HNSWIndex(dim=4)
            catalog = TableCatalog(name="papers", storage=storage, index=index)
            executor = SQLExecutor(catalog=catalog)

            # Insert sample papers with embeddings
            executor.execute(
                "INSERT INTO papers (id, title, category, vector) "
                "VALUES ('p1', 'Quantum Key Distribution', 'Cryptography', [1.0, 0.0, 0.0, 0.0])"
            )
            executor.execute(
                "INSERT INTO papers (id, title, category, vector) "
                "VALUES ('p2', 'Zero-Knowledge Proofs', 'Cryptography', [0.9, 0.1, 0.0, 0.0])"
            )
            executor.execute(
                "INSERT INTO papers (id, title, category, vector) "
                "VALUES ('p3', 'Side-Channel Hardware Attack', 'Hardware', [0.0, 1.0, 0.0, 0.0])"
            )

            # 1. LIKE pattern search
            res_like = executor.execute(
                "SELECT id, title FROM papers WHERE title LIKE '%Quantum%'"
            )
            self.assertEqual(res_like["count"], 1)
            self.assertEqual(res_like["rows"][0]["id"], "p1")

            # 2. KNN Vector Similarity Function
            res_knn = executor.execute(
                "SELECT id, title, score FROM papers WHERE KNN(vector, [1.0, 0.0, 0.0, 0.0], 2)"
            )
            self.assertEqual(res_knn["count"], 2)
            # Most similar should be p1 (distance 0 / sim ~ 1.0)
            self.assertEqual(res_knn["rows"][0]["id"], "p1")
            self.assertAlmostEqual(res_knn["rows"][0]["score"], 1.0, places=2)


if __name__ == "__main__":
    unittest.main()
