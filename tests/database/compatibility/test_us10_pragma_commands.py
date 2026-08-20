#!/usr/bin/env python3
"""
US-10: Database Introspection, RBAC, and Catalog Diagnostics in src/database.
Tests TableCatalog metadata inspection, AccessController RBAC permissions,
and DatabaseProfiler metrics reporting.
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
    AccessController,
    DatabaseProfiler,
    DCLPermissionDeniedError,
    HNSWIndex,
    TableCatalog,
    VectorStorage,
)


class TestUS10PragmaCommands(unittest.TestCase):
    """Verifies database introspection, profiling, and access control."""

    def test_table_catalog_introspection_and_profiling(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            storage_path = os.path.join(tmpdir, "introspection.vdb")
            storage = VectorStorage(storage_path, dim=4)
            index = HNSWIndex(dim=4)
            catalog = TableCatalog(name="threat_nodes", storage=storage, index=index)

            self.assertEqual(catalog.name, "threat_nodes")
            self.assertEqual(catalog.storage.dim, 4)

            # DatabaseProfiler
            profiler = DatabaseProfiler()
            result = profiler.profile_callable(
                name="catalog_stats",
                fn=lambda: catalog.storage.count,
                iterations=20,
                warmup=2,
            )
            self.assertEqual(result.iterations, 20)
            self.assertGreaterEqual(result.throughput_ops_sec, 0.0)

    def test_access_controller_rbac_permissions(self) -> None:
        ctrl = AccessController()
        # Admin has full DDL/DML access
        self.assertTrue(ctrl.check_permission("admin", "*", "ALL"))
        self.assertTrue(ctrl.check_permission("admin", "threat_nodes", "INSERT"))

        # Readonly analyst is denied DROP
        with self.assertRaises(DCLPermissionDeniedError):
            ctrl.enforce_permission("analyst", "threat_nodes", "ADMIN")

        # Analyst has SELECT permission
        self.assertTrue(ctrl.check_permission("analyst", "threat_nodes", "SELECT"))


if __name__ == "__main__":
    unittest.main()
