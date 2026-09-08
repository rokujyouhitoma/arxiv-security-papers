#!/usr/bin/env python3
"""
Comprehensive Validation Tests for VDB Migration (Issue 218).
Verifies:
1. Migration of cti_catalog.db to cti_catalog.vdb without data loss.
2. Migration of analytics.db to analytics.vdb without data loss.
3. Transparent reading and writing via CTICatalogStorage and AnalyticsStorage.
4. Fast direct table introspection from .vdb containers via get_sqlite_table_counts.
5. Bidirectional synchronization and schema persistence in .vdb containers.
"""

from __future__ import annotations

import os
import sys
import tempfile

sys.path.insert(0, "src")

from database.compat.sqlite_engine import (  # noqa: E402
    get_sqlite_connection,
    get_sqlite_table_counts,
)
from database.storage.multi_storage import MultiTableVectorStorage  # noqa: E402


def test_migrated_cti_catalog_vdb_integrity() -> None:
    """Verifies that the live cti_catalog.vdb contains all expected tables and records."""
    vdb_path = "outputs/database/catalog/cti_catalog.vdb"
    assert os.path.exists(vdb_path)

    # 1. Fast table count inspection
    counts = get_sqlite_table_counts(vdb_path)
    assert counts.get("cti_tactics") == 15
    assert counts.get("cti_techniques") == 697
    assert counts.get("cti_mitigations") == 44
    assert counts.get("cti_relationships") == 1923
    assert counts.get("cisa_kev_vulnerabilities") == 6

    # 2. Container inspection
    storage = MultiTableVectorStorage(vdb_path)
    storage.load()
    assert storage.has_table("_schemas")
    assert storage.get_table("cti_techniques").count == 697
    storage.close()


def test_migrated_analytics_vdb_integrity() -> None:
    """Verifies that the live analytics.vdb contains all expected tables and records."""
    vdb_path = "outputs/database/analytics/analytics.vdb"
    assert os.path.exists(vdb_path)

    # 1. Fast table count inspection
    counts = get_sqlite_table_counts(vdb_path)
    assert counts.get("threat_trends") == 6
    assert counts.get("strategic_kpis") == 13
    assert counts.get("metrics_history") == 6
    assert counts.get("latest_snapshot") == 1

    # 2. Container inspection
    storage = MultiTableVectorStorage(vdb_path)
    storage.load()
    assert storage.has_table("_schemas")
    assert storage.get_table("strategic_kpis").count == 13
    storage.close()


def test_cti_catalog_storage_operations_on_vdb() -> None:
    """Tests that CTICatalogStorage operates seamlessly on cti_catalog.vdb."""
    from domain.security.cti.storage import CTICatalogStorage

    storage = CTICatalogStorage()
    assert storage.db_path.endswith("cti_catalog.vdb")

    # Read technique
    t = storage.get_technique("T1059")
    assert t is not None
    assert t["technique_id"] == "T1059"

    # Count summary
    counts = storage.count_summary()
    assert counts["tactics"] == 15
    assert counts["techniques"] == 697
    assert counts["mitigations"] == 44
    assert counts["relationships"] == 1923

    # CISA KEV count
    assert storage.get_cisa_kev_count() == 6

    # Introspection metadata
    meta = storage.get_introspection_metadata()
    assert meta["file_path"].endswith("cti_catalog.vdb")
    assert any(item["table_name"] == "cti_techniques" for item in meta["tables"])


def test_analytics_storage_operations_on_vdb() -> None:
    """Tests that AnalyticsStorage operates seamlessly on analytics.vdb."""
    from analytics.storage import AnalyticsStorage

    storage = AnalyticsStorage()
    assert storage.db_path.endswith("analytics.vdb")

    # Load latest snapshot
    metrics = storage.load_latest_metrics()
    assert metrics is not None

    # Export dataset
    dataset = storage.export_analytics_dataset()
    assert "strategic_kpis" in dataset
    assert len(dataset["strategic_kpis"]) == 13
    assert "threat_trends" in dataset
    assert len(dataset["threat_trends"]) == 6

    # Introspection metadata
    meta = storage.get_introspection_metadata()
    assert meta["file_path"].endswith("analytics.vdb")
    assert any(item["table_name"] == "strategic_kpis" for item in meta["tables"])


def test_vdb_managed_connection_persistence() -> None:
    """Tests that modifying tables via VDBManagedConnection persists data to .vdb."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_vdb = os.path.join(tmpdir, "test_lifecycle.vdb")

        # 1. Create table and insert records
        conn1 = get_sqlite_connection(test_vdb)
        cur1 = conn1.cursor()
        cur1.execute("CREATE TABLE sample_items (id TEXT PRIMARY KEY, value INT)")
        cur1.execute("INSERT INTO sample_items VALUES (?, ?)", ("item_1", 100))
        cur1.execute("INSERT INTO sample_items VALUES (?, ?)", ("item_2", 200))
        conn1.commit()
        conn1.close()

        # 2. Verify file header and table count
        assert os.path.exists(test_vdb)
        counts = get_sqlite_table_counts(test_vdb)
        assert counts.get("sample_items") == 2

        # 3. Re-open and verify content
        conn2 = get_sqlite_connection(test_vdb, init_schema=False, read_only=True)
        cur2 = conn2.cursor()
        cur2.execute("SELECT value FROM sample_items WHERE id = ?", ("item_2",))
        row = cur2.fetchone()
        assert row is not None
        assert row[0] == 200
        conn2.close()


if __name__ == "__main__":
    print("Starting test 1...")
    test_migrated_cti_catalog_vdb_integrity()
    print("1. test_migrated_cti_catalog_vdb_integrity PASSED")
    print("Starting test 2...")
    test_migrated_analytics_vdb_integrity()
    print("2. test_migrated_analytics_vdb_integrity PASSED")
    print("Starting test 3...")
    test_cti_catalog_storage_operations_on_vdb()
    print("3. test_cti_catalog_storage_operations_on_vdb PASSED")
    print("Starting test 4...")
    test_analytics_storage_operations_on_vdb()
    print("4. test_analytics_storage_operations_on_vdb PASSED")
    print("Starting test 5...")
    test_vdb_managed_connection_persistence()
    print("5. test_vdb_managed_connection_persistence PASSED")
    print("ALL TESTS PASSED SUCCESSFULLY!")
