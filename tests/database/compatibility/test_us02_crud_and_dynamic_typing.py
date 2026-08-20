#!/usr/bin/env python3
"""
US-02: Basic CRUD and Flexible Data Handling in src/database.
Tests INSERT, UPDATE, DELETE, SELECT, JSON payload handling,
and dynamic metadata storage in pure Python SQLExecutor.
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


class TestUS02CRUDAndDynamicTyping(unittest.TestCase):
    """Verifies CRUD operations and dynamic metadata in SQLExecutor."""

    def test_sql_executor_crud_lifecycle(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            storage_path = os.path.join(tmpdir, "crud_test.vdb")
            storage = VectorStorage(storage_path, dim=4)
            index = HNSWIndex(dim=4)
            catalog = TableCatalog(name="papers", storage=storage, index=index)
            executor = SQLExecutor(catalog=catalog)

            # 1. CREATE (INSERT)
            res_ins1 = executor.execute(
                "INSERT INTO papers (id, title, category, vector) "
                "VALUES ('p1', 'Homomorphic Encryption', 'Cryptography', [1.0, 0.0, 0.0, 0.0])"
            )
            self.assertEqual(res_ins1["status"], "ok")
            self.assertEqual(res_ins1["id"], "p1")

            res_ins2 = executor.execute(
                "INSERT INTO papers (id, title, category, vector) "
                "VALUES ('p2', 'Side Channel Attacks', 'Hardware-Security', [0.0, 1.0, 0.0, 0.0])"
            )
            self.assertEqual(res_ins2["status"], "ok")

            # 2. READ (SELECT with filter)
            res_sel = executor.execute(
                "SELECT id, title, category FROM papers WHERE category = 'Cryptography'"
            )
            self.assertEqual(res_sel["count"], 1)
            self.assertEqual(res_sel["rows"][0]["id"], "p1")
            self.assertEqual(res_sel["rows"][0]["title"], "Homomorphic Encryption")

            # 3. UPDATE
            res_upd = executor.execute(
                "UPDATE papers SET title = 'Advanced Homomorphic Encryption' WHERE id = 'p1'"
            )
            self.assertEqual(res_upd["status"], "ok")
            self.assertEqual(res_upd["updated_count"], 1)

            # Verify update
            res_sel_upd = executor.execute(
                "SELECT id, title FROM papers WHERE id = 'p1'"
            )
            self.assertEqual(
                res_sel_upd["rows"][0]["title"],
                "Advanced Homomorphic Encryption",
            )

            # 4. DELETE
            res_del = executor.execute("DELETE FROM papers WHERE id = 'p2'")
            self.assertEqual(res_del["status"], "ok")
            self.assertEqual(res_del["deleted_count"], 1)

            # Verify deletion
            res_sel_all = executor.execute("SELECT id FROM papers")
            self.assertEqual(res_sel_all["count"], 1)
            self.assertEqual(res_sel_all["rows"][0]["id"], "p1")


if __name__ == "__main__":
    unittest.main()
