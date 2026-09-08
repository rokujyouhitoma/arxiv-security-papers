#!/usr/bin/env python3
"""Tests for dynamic SHOW DATABASES and SHOW TABLES [FROM <db>] in SQLExecutor."""

import os
import unittest
from typing import Dict

from database.sql.executor import SQLExecutor


class TestShowStatements(unittest.TestCase):
    """Verifies that SHOW statements dynamically query registered databases and containers."""

    def setUp(self) -> None:
        self.workspace_dir = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..")
        )
        self.kg_path = os.path.join(
            self.workspace_dir, "outputs", "database", "knowledge_graph.vdb"
        )
        self.known_dbs: Dict[str, str] = {
            "graph_db": self.kg_path,
            "custom_mock_db": ":memory:",
        }

    def test_show_databases_default(self) -> None:
        executor = SQLExecutor()
        res = executor.execute("SHOW DATABASES;")
        self.assertEqual(res["status"], "ok")
        self.assertEqual(res["target"], "DATABASES")
        dbs = [r["Database"] for r in res["rows"]]
        self.assertIn("default_db", dbs)
        self.assertIn("main", dbs)

    def test_show_databases_with_injected_dbs(self) -> None:
        executor = SQLExecutor(known_databases=self.known_dbs)
        res = executor.execute("SHOW DATABASES;")
        self.assertEqual(res["status"], "ok")
        dbs = [r["Database"] for r in res["rows"]]
        self.assertIn("graph_db", dbs)
        self.assertIn("custom_mock_db", dbs)

    def test_register_database_dynamically(self) -> None:
        executor = SQLExecutor()
        executor.register_database("new_db", "/path/to/new.vdb")
        res = executor.execute("SHOW DATABASES;")
        dbs = [r["Database"] for r in res["rows"]]
        self.assertIn("new_db", dbs)

    def test_show_tables_from_graph_db(self) -> None:
        if not os.path.exists(self.kg_path):
            self.skipTest("knowledge_graph.vdb does not exist in outputs")
        executor = SQLExecutor(known_databases=self.known_dbs)
        res = executor.execute("SHOW TABLES FROM graph_db;")
        self.assertEqual(res["status"], "ok")
        self.assertEqual(res["target"], "TABLES")
        table_names = [r["Table"] for r in res["rows"]]
        self.assertIn("vertices", table_names)
        self.assertIn("edges", table_names)
        # Verify no imaginary tables
        self.assertNotIn("tbox_classes", table_names)
        self.assertNotIn("tbox_properties", table_names)

    def test_show_tables_with_like_filter(self) -> None:
        if not os.path.exists(self.kg_path):
            self.skipTest("knowledge_graph.vdb does not exist in outputs")
        executor = SQLExecutor(known_databases=self.known_dbs)
        res = executor.execute("SHOW TABLES FROM graph_db LIKE '%vert%';")
        self.assertEqual(res["status"], "ok")
        table_names = [r["Table"] for r in res["rows"]]
        self.assertEqual(table_names, ["vertices"])

    def test_register_database_invalid_identifier(self) -> None:
        from database.sql.executor import SQLExecutionError

        executor = SQLExecutor()
        for invalid_name in ["bad-db", "123num", "drop;table", "db.name", ""]:
            with self.assertRaises(SQLExecutionError):
                executor.register_database(invalid_name, "/tmp/dummy.vdb")

    def test_register_database_max_limit(self) -> None:
        from database.sql.executor import SQLExecutionError

        executor = SQLExecutor()
        for i in range(64):
            executor.register_database(f"db_{i}", f"/tmp/db_{i}.vdb")
        with self.assertRaises(SQLExecutionError):
            executor.register_database("db_overflow", "/tmp/overflow.vdb")

    def test_external_db_non_magic_rejection(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            fake_txt = os.path.join(tmpdir, "fake_secrets.txt")
            with open(fake_txt, "w") as f:
                f.write("root:x:0:0:root:/root:/bin/bash\n")

            executor = SQLExecutor()
            executor.register_database("fake_db", fake_txt)
            res = executor.execute("SHOW TABLES FROM fake_db;")
            self.assertEqual(res["status"], "ok")
            self.assertEqual(res["rows"], [])


if __name__ == "__main__":
    unittest.main()
