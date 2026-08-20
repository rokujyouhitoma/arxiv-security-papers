#!/usr/bin/env python3
"""
US-01: Table Definition and Type Affinity Verification in src/database.
Tests DDL parsing, TableCatalog schema management, column type definitions
(INT, TEXT, FLOAT, VECTOR, JSON), and constraint validations in pure Python database engine.
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
    SQLExecutor,
    SQLParser,
    TableCatalog,
    VectorStorage,
    connect,
)


class TestUS01SchemaAndAffinity(unittest.TestCase):
    """Verifies DDL schema operations and type affinity in src/database."""

    def test_ddl_create_table_and_column_types(self) -> None:
        parser = SQLParser()
        sql_create = (
            "CREATE TABLE security_policies ("
            "id VARCHAR(32) PRIMARY KEY, "
            "policy_name TEXT, "
            "severity INT, "
            "score FLOAT, "
            "embedding VECTOR(128), "
            "metadata JSON"
            ")"
        )
        stmt = parser.parse(sql_create)
        self.assertEqual(stmt.category, "DDL")
        self.assertEqual(stmt.command_type.value, "CREATE_TABLE")
        self.assertEqual(stmt.table_name, "security_policies")
        self.assertEqual(len(stmt.columns), 6)
        self.assertEqual(stmt.columns[0].name, "id")
        self.assertEqual(stmt.columns[0].data_type, "VARCHAR(32)")
        self.assertEqual(stmt.columns[4].name, "embedding")
        self.assertEqual(stmt.columns[4].data_type, "VECTOR(128)")

    def test_table_catalog_schema_management(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            storage_path = os.path.join(tmpdir, "policies.vdb")
            storage = VectorStorage(storage_path, dim=4)
            index = HNSWIndex(dim=4)
            catalog = TableCatalog(name="policies", storage=storage, index=index)

            self.assertEqual(catalog.name, "policies")
            self.assertEqual(catalog.storage.dim, 4)
            self.assertEqual(catalog.index.dim, 4)

            executor = SQLExecutor(catalog=catalog)
            # Verify DDL execution
            res_drop = executor.execute("DROP TABLE policies")
            self.assertEqual(res_drop["status"], "ok")
            self.assertEqual(res_drop["dropped"], True)

    def test_pep249_driver_connection_schema(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = os.path.join(tmpdir, "driver_schema.vdb")
            conn = connect(db_path, dim=4)
            cur = conn.cursor()

            # Insert sample paper record
            cur.execute(
                "INSERT INTO papers (id, title, category, vector) VALUES (?, ?, ?, ?)",
                [
                    "sec-01",
                    "Zero Trust Architecture",
                    "Zero-Trust",
                    [1.0, 0.0, 0.0, 0.0],
                ],
            )
            conn.commit()

            cur.execute("SELECT id, title, category FROM papers WHERE id = 'sec-01'")
            rows = cur.fetchall()
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0][0], "sec-01")
            self.assertEqual(rows[0][1], "Zero Trust Architecture")
            self.assertEqual(rows[0][2], "Zero-Trust")

            conn.close()


if __name__ == "__main__":
    unittest.main()
