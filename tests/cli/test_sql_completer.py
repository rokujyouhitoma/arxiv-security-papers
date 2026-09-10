#!/usr/bin/env python3
"""tests/cli/test_sql_completer.py

Unit tests for SQLCompleter (Tab Autocompletion Engine) conforming to DSN-24 Section 4.6.
"""

from __future__ import annotations

import unittest

from cli.completer import SQLCompleter
from database.sql.executor import SQLExecutor
from database.storage.storage import VectorStorage


class TestSQLCompleter(unittest.TestCase):
    """Verifies context-aware SQL and meta-command autocompletion."""

    def setUp(self) -> None:
        self.executor = SQLExecutor(default_storage=VectorStorage(":memory:", dim=4))
        self.executor.execute(
            "CREATE TABLE IF NOT EXISTS okf_papers ("
            "clean_id TEXT PRIMARY KEY, title TEXT, tags TEXT, body_markdown TEXT"
            ")"
        )
        self.executor.execute(
            "CREATE TABLE IF NOT EXISTS processed_papers ("
            "clean_id TEXT PRIMARY KEY, title TEXT, okf_path TEXT, sha256 TEXT"
            ")"
        )
        self.completer = SQLCompleter(self.executor)

    def test_meta_command_completion(self) -> None:
        """Verifies dot commands are suggested when line starts with dot."""
        cand_tbl = self.completer._determine_candidates(".ta", ".ta")
        self.assertIn(".tables", cand_tbl)

        cand_schema = self.completer._determine_candidates(".sc", ".sc")
        self.assertIn(".schema", cand_schema)

        cand_sync = self.completer._determine_candidates(".sy", ".sy")
        self.assertIn(".sync", cand_sync)

        cand_help = self.completer._determine_candidates(".h", ".h")
        self.assertIn(".help", cand_help)

    def test_table_name_completion(self) -> None:
        """Verifies mounted table names are suggested after FROM or JOIN."""
        from_cand = self.completer._determine_candidates("SELECT * FROM ok", "ok")
        self.assertIn("okf_papers", from_cand)

        join_cand = self.completer._determine_candidates(
            "SELECT * FROM okf_papers JOIN pr", "pr"
        )
        self.assertIn("processed_papers", join_cand)

    def test_column_name_completion(self) -> None:
        """Verifies table columns are suggested in SELECT and WHERE clauses."""
        sel_cand = self.completer._determine_candidates("SELECT cl", "cl")
        self.assertIn("clean_id", sel_cand)

        where_cand = self.completer._determine_candidates(
            "SELECT * FROM okf_papers WHERE ti", "ti"
        )
        self.assertIn("title", where_cand)

    def test_keyword_completion(self) -> None:
        """Verifies standard SQL keywords are suggested as default fallback."""
        kw_cand = self.completer._determine_candidates("sel", "sel")
        self.assertIn("SELECT", kw_cand)

        where_kw = self.completer._determine_candidates("wh", "wh")
        self.assertIn("WHERE", where_kw)

    def test_complete_state_iteration(self) -> None:
        """Verifies complete callback handles sequential state queries."""
        first = self.completer.complete("sel", 0)
        self.assertEqual(first, "SELECT")
        second = self.completer.complete("sel", 1)
        self.assertIsNone(second)


if __name__ == "__main__":
    unittest.main()
