#!/usr/bin/env python3
"""Tests for real database introspection in Web Gateway."""

import os
import unittest
from typing import Any, Dict

from web.gateway.handlers import (
    _collect_database_tables,
    _introspect_graph_database,
    _resolve_graph_file_size,
    _run_sql_introspection,
)


class TestDatabaseRealIntrospection(unittest.TestCase):
    """Verifies that database introspection returns real container data without mocks."""

    def setUp(self) -> None:
        self.workspace_dir = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..")
        )
        self.kg_path = os.path.join(
            self.workspace_dir, "outputs", "database", "knowledge_graph.vdb"
        )

    def test_resolve_graph_file_size(self) -> None:
        size = _resolve_graph_file_size(self.workspace_dir)
        if os.path.exists(self.kg_path):
            expected = os.path.getsize(self.kg_path)
            self.assertEqual(size, expected)
        else:
            self.assertEqual(size, 0)

    def test_introspect_graph_database_has_no_mock_tables(self) -> None:
        kpis: Dict[str, Any] = {"read_iops": 100, "avg_latency_ms": 0.1}
        res = _introspect_graph_database(self.workspace_dir, None, kpis)
        self.assertEqual(res["name"], "graph_db")
        self.assertEqual(res["table_count"], 2)

        table_names = [t["table_name"] for t in res["tables"]]
        self.assertEqual(table_names, ["vertices", "edges"])
        self.assertNotIn("tbox_classes", table_names)
        self.assertNotIn("tbox_properties", table_names)
        self.assertNotIn("reified_claims", table_names)
        self.assertNotIn("evidences", table_names)

    def test_graph_sql_introspection_status(self) -> None:
        kpis: Dict[str, Any] = {}
        res = _introspect_graph_database(self.workspace_dir, None, kpis)
        sql_info = res["sql_introspection"]
        self.assertIn("show_databases", sql_info)
        self.assertIn("show_tables", sql_info)

        show_tables = sql_info["show_tables"]
        self.assertEqual(show_tables["query"], "SHOW TABLES FROM graph_db;")
        self.assertIn(show_tables["status"], ("ok", "fallback"))
        self.assertGreaterEqual(show_tables.get("latency_ms", 0.0), 0.0)

    def test_collect_database_tables_has_no_graph_leak(self) -> None:
        tables, tot_rows, tot_size, ge, p_rows = _collect_database_tables(
            self.workspace_dir
        )
        table_names = [t["table_name"] for t in tables]
        # Ensure arxiv_security_db contains only settings.py defined virtual tables
        self.assertEqual(table_names, ["okf_papers", "processed_papers", "raw_papers"])
        self.assertNotIn("paper_metadata", table_names)
        self.assertNotIn("papers_vector", table_names)
        self.assertNotIn("search_inverted_index", table_names)
        self.assertNotIn("analytics_metrics", table_names)
        self.assertNotIn("vertices", table_names)
        self.assertNotIn("edges", table_names)

    def test_run_sql_introspection_databases(self) -> None:
        dbs_res = _run_sql_introspection(self.workspace_dir, [])
        show_dbs = dbs_res["show_databases"]
        self.assertEqual(show_dbs["status"], "ok")
        self.assertIn("graph_db", show_dbs["databases"])
        self.assertIn("arxiv_security_db", show_dbs["databases"])

    def test_cti_catalog_tables_reconciliation(self) -> None:
        from domain.security.cti.storage import CTICatalogStorage

        res = CTICatalogStorage.get_introspection_metadata(self.workspace_dir)
        self.assertEqual(res["table_count"], 5)
        self.assertEqual(res["total_rows"], 2685)
        names = [t["table_name"] for t in res["tables"]]
        self.assertEqual(
            names,
            [
                "cisa_kev_vulnerabilities",
                "cti_mitigations",
                "cti_relationships",
                "cti_tactics",
                "cti_techniques",
            ],
        )
        self.assertNotIn("cti_techniques_fts", names)

    def test_analytics_tables_reconciliation(self) -> None:
        from analytics.storage import AnalyticsStorage

        res = AnalyticsStorage.get_introspection_metadata(self.workspace_dir)
        self.assertEqual(res["table_count"], 5)
        self.assertEqual(res["total_rows"], 26)
        names = [t["table_name"] for t in res["tables"]]
        self.assertEqual(
            names,
            [
                "latest_snapshot",
                "metrics_history",
                "papers",
                "strategic_kpis",
                "threat_trends",
            ],
        )


if __name__ == "__main__":
    unittest.main()
