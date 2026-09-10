#!/usr/bin/env python3
"""tests/cli/test_manage_dbshell.py

Comprehensive tests for manage.py CLI, dbshell, tables, inspect, and dbsync commands.
Conforms to DSN-24, zero external dependencies, 100% assertions.
"""

from __future__ import annotations

import io
import json
import os
import shutil
import tempfile
import unittest
from contextlib import redirect_stdout

from cli.commands.dbshell import (
    DBShellSession,
    _execute_meta_command,
    detect_table_scope,
    detect_table_type,
    execute_single_query,
)
from cli.commands.dbsync import synchronize_database_catalog
from cli.commands.inspect import InspectTableCommand
from cli.commands.tables import ShowTablesCommand
from cli.dispatcher import CommandDispatcher
from cli.formatter import format_ascii_table, format_query_result
from database.sql.executor import SQLExecutor
from database.storage.storage import VectorStorage


class TestManageCLISuite(unittest.TestCase):
    """Verifies core manage.py commands and utilities."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp(prefix="test_manage_cli_")
        self.okf_dir = os.path.join(self.temp_dir, "outputs", "okf_papers")
        self.db_dir = os.path.join(self.temp_dir, "outputs", "database")
        os.makedirs(self.okf_dir, exist_ok=True)
        os.makedirs(self.db_dir, exist_ok=True)

        # Create a sample OKF markdown file
        sample_md = os.path.join(self.okf_dir, "2501.00001.md")
        with open(sample_md, "w", encoding="utf-8") as f:
            f.write(
                "---\n"
                "title: 'Zero Trust Agent Architecture'\n"
                "description: 'Formal verification of agent security.'\n"
                "tags: ['zero-trust', 'agent']\n"
                "---\n\n"
                "# Content\n"
                "Sample body text here.\n"
            )

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_formatter_ascii_table(self) -> None:
        """Verifies ASCII table rendering with boundaries and null handling."""
        headers = ["ID", "Name", "Score"]
        rows = [["1", "Alice", 95.5], ["2", "Bob", None]]
        table = format_ascii_table(headers, rows)
        self.assertIn("+------+-------+-------+", table)
        self.assertIn("| ID   | Name  | Score |", table)
        self.assertIn("| 1    | Alice | 95.5  |", table)
        self.assertIn("| 2    | Bob   | NULL  |", table)

    def test_formatter_empty(self) -> None:
        """Verifies empty rows return zero rows indication."""
        self.assertEqual(format_query_result([]), "(0 rows)")

    def test_dbsync_and_catalog_healing(self) -> None:
        """Verifies dbsync detects physical paper and complements the catalog."""
        added, total = synchronize_database_catalog(self.temp_dir)
        self.assertEqual(added, 1)
        self.assertEqual(total, 1)

        cat_file = os.path.join(self.db_dir, "papers_catalog.json")
        self.assertTrue(os.path.exists(cat_file))
        with open(cat_file, "r", encoding="utf-8") as f:
            data = json.load(f)
            self.assertIn("2501.00001", data)
            self.assertEqual(
                data["2501.00001"]["title"], "Zero Trust Agent Architecture"
            )

        # Idempotency check: 2nd sync should add 0
        added_again, total_again = synchronize_database_catalog(self.temp_dir)
        self.assertEqual(added_again, 0)
        self.assertEqual(total_again, 1)

    def test_dispatcher_help(self) -> None:
        """Verifies manage.py --help prints usage."""
        dispatcher = CommandDispatcher(workspace_dir=self.temp_dir)
        buf = io.StringIO()
        with redirect_stdout(buf):
            ret = dispatcher.run(["--help"])
        self.assertEqual(ret, 0)
        self.assertIn("usage:", buf.getvalue())
        self.assertIn("dbshell", buf.getvalue())
        self.assertIn("dbsync", buf.getvalue())

    def test_tables_command(self) -> None:
        """Verifies manage.py tables displays mounted tables."""
        cmd = ShowTablesCommand(workspace_dir=self.temp_dir)
        buf = io.StringIO()
        with redirect_stdout(buf):
            ret = cmd.handle(cmd.create_parser().parse_args([]))
        self.assertEqual(ret, 0)
        self.assertIn("okf_papers", buf.getvalue())

    def test_inspect_command(self) -> None:
        """Verifies manage.py inspect okf_papers displays table schema."""
        cmd = InspectTableCommand(workspace_dir=self.temp_dir)
        buf = io.StringIO()
        with redirect_stdout(buf):
            ret = cmd.handle(cmd.create_parser().parse_args(["okf_papers"]))
        self.assertEqual(ret, 0)
        self.assertIn("Table: okf_papers", buf.getvalue())
        self.assertIn("title", buf.getvalue())

    def test_dbshell_one_liner_query(self) -> None:
        """Verifies dbshell -c executes single query and displays result."""
        executor = SQLExecutor(default_storage=VectorStorage(":memory:", dim=4))
        executor.execute("CREATE TABLE test_tbl (id TEXT PRIMARY KEY, val INTEGER)")
        executor.execute("INSERT INTO test_tbl (id, val) VALUES ('1', 42)")

        buf = io.StringIO()
        with redirect_stdout(buf):
            ret = execute_single_query(executor, "SELECT * FROM test_tbl;")
        self.assertEqual(ret, 0)
        self.assertIn("42", buf.getvalue())
        self.assertIn("1 rows in set", buf.getvalue())

    def test_dbshell_meta_commands(self) -> None:
        """Verifies .tables, .schema, .indexes, .sync, .databases, .use, and .help meta-commands."""
        executor = SQLExecutor(default_storage=VectorStorage(":memory:", dim=4))
        executor.execute("CREATE TABLE demo_tbl (id TEXT PRIMARY KEY, num INTEGER)")
        executor.execute("CREATE INDEX idx_demo_num ON demo_tbl (num) USING BTREE;")
        session = DBShellSession(engine=executor, ws=self.temp_dir)

        buf = io.StringIO()
        with redirect_stdout(buf):
            self.assertTrue(_execute_meta_command(session, ".tables"))
            self.assertTrue(_execute_meta_command(session, ".schema demo_tbl"))
            self.assertTrue(_execute_meta_command(session, ".indexes"))
            self.assertTrue(_execute_meta_command(session, ".sync"))
            self.assertTrue(_execute_meta_command(session, ".databases"))
            self.assertTrue(_execute_meta_command(session, ".use cti_catalog_db"))
            self.assertEqual(session.scope, "cti_catalog_db")
            self.assertTrue(_execute_meta_command(session, ".help"))

        out = buf.getvalue()
        self.assertIn("demo_tbl", out)
        self.assertIn("CREATE TABLE demo_tbl (", out)
        self.assertIn("    id   TEXT PRIMARY KEY", out)
        self.assertIn("CREATE UNIQUE INDEX pk_demo_tbl_id", out)
        self.assertIn("CREATE INDEX idx_demo_num", out)
        self.assertIn("idx_demo_num", out)
        self.assertIn("Synchronizing", out)
        self.assertIn("Database Scope", out)
        self.assertIn("cti_catalog_db", out)
        self.assertIn("Meta-commands:", out)

    def test_dbshell_use_statement(self) -> None:
        """Verifies USE <scope>; command switches session scope."""
        executor = SQLExecutor(default_storage=VectorStorage(":memory:", dim=4))
        session = DBShellSession(engine=executor, ws=self.temp_dir)
        buf = io.StringIO()
        with redirect_stdout(buf):
            res = session.switch_scope("graph_db")
        self.assertTrue(res)
        self.assertEqual(session.scope, "graph_db")
        self.assertIn("Switched database scope to 'graph_db'", buf.getvalue())

    def test_table_type_and_scope_detection(self) -> None:
        """Verifies table scope and table type introspection."""
        self.assertEqual(detect_table_scope("cti_techniques"), "cti_catalog_db")
        self.assertEqual(detect_table_scope("vertices"), "graph_db")
        self.assertEqual(detect_table_scope("threat_trends"), "analytics_db")
        self.assertEqual(detect_table_scope("okf_papers"), "arxiv_security_db")

        # In-memory check
        mem_storage = VectorStorage(":memory:", dim=4)
        self.assertEqual(detect_table_type(mem_storage), "In-Memory")


if __name__ == "__main__":
    unittest.main()
