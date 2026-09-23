#!/usr/bin/env python3
"""
Integration and E2E tests for baseline database migration (0001_baseline).
Verifies Dual-Backend compatibility across Primary (src.database / PyDB)
and Secondary (sqlite3) engines.
Conforms to DSN-30 Section 8 and Issue #387 DoD.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, List

from src.database.migrations import (
    BackendType,
    MigrationManager,
    MigrationStatus,
    get_adapter,
)

EXPECTED_BASELINE_TABLES: List[str] = [
    "threat_trends",
    "strategic_kpis",
    "metrics_history",
    "latest_snapshot",
    "spider_execution_logs",
    "cti_tactics",
    "cti_techniques",
    "cti_mitigations",
    "cti_relationships",
    "cti_cwes",
    "cti_cwe_relationships",
    "cisa_kev_vulnerabilities",
]


def _get_migrations_dir() -> Path:
    return Path(__file__).resolve().parent.parent / "migrations"


def _verify_tables_exist(adapter: Any) -> None:
    rows = adapter.execute_query("SELECT name FROM sqlite_master WHERE type='table'")
    names = {r[0] for r in rows}
    for expected in EXPECTED_BASELINE_TABLES:
        assert expected in names
    assert "schema_migrations" in names


def _verify_tables_absent(adapter: Any) -> None:
    rows = adapter.execute_query("SELECT name FROM sqlite_master WHERE type='table'")
    names = {r[0] for r in rows}
    for expected in EXPECTED_BASELINE_TABLES:
        assert expected not in names


def _insert_kpi(adapter: Any) -> None:
    conn = adapter.connect()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO strategic_kpis (kpi_key, kpi_category, num_value, updated_at) "
        "VALUES (?, ?, ?, ?)",
        ("kpi_1", "SEC", 99.5, "2026-09-23T00:00:00Z"),
    )
    conn.commit()


def _assert_kpi_record(adapter: Any) -> None:
    rows = adapter.execute_query(
        "SELECT kpi_key, num_value FROM strategic_kpis WHERE kpi_key = ?",
        ("kpi_1",),
    )
    assert len(rows) == 1
    assert rows[0][0] == "kpi_1"
    assert rows[0][1] == 99.5


def test_pydb_baseline_initial_status(tmp_path: Path) -> None:
    db_path = tmp_path / "test_pydb_init.vdb"
    mig_dir = _get_migrations_dir()
    mgr = MigrationManager(
        db_path=db_path, migrations_dir=mig_dir, backend=BackendType.PYDB
    )
    statuses = mgr.status()
    baseline = statuses[0]
    assert baseline["version"] == "0001"
    assert baseline["status"] == MigrationStatus.PENDING.value
    mgr.close()


def test_pydb_baseline_apply_and_dml(tmp_path: Path) -> None:
    db_path = tmp_path / "test_pydb_apply.vdb"
    mig_dir = _get_migrations_dir()
    mgr = MigrationManager(
        db_path=db_path, migrations_dir=mig_dir, backend=BackendType.PYDB
    )
    applied = mgr.up()
    assert applied[0].version == "0001"
    assert mgr.status()[0]["status"] == MigrationStatus.APPLIED.value
    mgr.close()

    adapter = get_adapter(backend=BackendType.PYDB, db_path=db_path)
    _insert_kpi(adapter)
    _assert_kpi_record(adapter)
    adapter.close()


def test_pydb_baseline_rollback_and_reapply(tmp_path: Path) -> None:
    db_path = tmp_path / "test_pydb_reapply.vdb"
    mig_dir = _get_migrations_dir()
    mgr = MigrationManager(
        db_path=db_path, migrations_dir=mig_dir, backend=BackendType.PYDB
    )
    mgr.up()
    assert mgr.down(steps=1) == ["0001"]
    assert mgr.status()[0]["status"] == MigrationStatus.PENDING.value
    reapplied = mgr.up()
    assert reapplied[0].version == "0001"
    mgr.close()


def test_sqlite_baseline_apply_and_verify_tables(tmp_path: Path) -> None:
    db_path = tmp_path / "test_sqlite_apply.db"
    mig_dir = _get_migrations_dir()
    mgr = MigrationManager(
        db_path=db_path, migrations_dir=mig_dir, backend=BackendType.SQLITE
    )
    applied = mgr.up()
    assert applied[0].version == "0001"
    mgr.close()

    adapter = get_adapter(backend=BackendType.SQLITE, db_path=db_path)
    _verify_tables_exist(adapter)
    adapter.close()


def test_sqlite_baseline_dml_and_rollback(tmp_path: Path) -> None:
    db_path = tmp_path / "test_sqlite_rollback.db"
    mig_dir = _get_migrations_dir()
    mgr = MigrationManager(
        db_path=db_path, migrations_dir=mig_dir, backend=BackendType.SQLITE
    )
    mgr.up()
    adapter = get_adapter(backend=BackendType.SQLITE, db_path=db_path)
    _verify_tables_exist(adapter)

    assert mgr.down(steps=1) == ["0001"]
    _verify_tables_absent(adapter)
    adapter.close()
    mgr.close()
