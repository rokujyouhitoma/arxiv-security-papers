#!/usr/bin/env python3
"""
Dual-Backend Differential Test Suite for Database Migrations (DSN-30 Phase 5).
Validates schema definition, index structure, DML execution, rollback parity,
and re-apply idempotency between Primary (src.database / PyDB) and Secondary (sqlite3).
Conforms to DSN-30 Section 8, Section 10, and Issue #388 DoD.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, List, Tuple

from src.database.migrations import BackendType, MigrationManager


def _get_migrations_dir() -> Path:
    return Path(__file__).resolve().parent.parent / "migrations"


def _init_dual_managers(
    tmp_path: Path,
) -> Tuple[MigrationManager, MigrationManager]:
    mig_dir = _get_migrations_dir()
    pydb_mgr = MigrationManager(
        db_path=tmp_path / "diff_pydb.vdb",
        migrations_dir=mig_dir,
        backend=BackendType.PYDB,
    )
    sqlite_mgr = MigrationManager(
        db_path=tmp_path / "diff_sqlite.db",
        migrations_dir=mig_dir,
        backend=BackendType.SQLITE,
    )
    return pydb_mgr, sqlite_mgr


def _extract_table_names(conn: Any) -> List[str]:
    if hasattr(conn, "tables") and isinstance(conn.tables, list):
        return sorted(list(conn.tables))
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    return [str(row[0]) for row in cur.fetchall()]


def _extract_column_defs(conn: Any, table: str) -> List[Tuple[str, str]]:
    cur = conn.cursor()
    cur.execute(f"PRAGMA table_info({table})")
    # PRAGMA returns (cid, name, type, notnull, dflt_value, pk)
    # Validate column name and normalized data type parity
    return [(str(row[1]), str(row[2]).upper()) for row in cur.fetchall()]


def _extract_table_indexes(conn: Any, table: str) -> List[str]:
    cur = conn.cursor()
    cur.execute(f"PRAGMA index_list({table})")
    rows = cur.fetchall()
    return sorted(
        [str(r[1]) for r in rows if not str(r[1]).startswith("sqlite_autoindex_")]
    )


def _verify_single_table_schema(py_conn: Any, sq_conn: Any, tbl: str) -> None:
    py_cols = _extract_column_defs(py_conn, tbl)
    sq_cols = _extract_column_defs(sq_conn, tbl)
    assert py_cols == sq_cols, f"Column mismatch on table: {tbl}"

    py_indexes = _extract_table_indexes(py_conn, tbl)
    sq_indexes = _extract_table_indexes(sq_conn, tbl)
    assert py_indexes == sq_indexes, f"Index mismatch on table: {tbl}"


def _verify_schema_equality(py_conn: Any, sq_conn: Any) -> None:
    py_tables = _extract_table_names(py_conn)
    sq_tables = _extract_table_names(sq_conn)
    assert py_tables == sq_tables
    assert "schema_migrations" in py_tables

    for tbl in py_tables:
        _verify_single_table_schema(py_conn, sq_conn, tbl)


def _insert_kpi_sample(conn: Any) -> None:
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO strategic_kpis (kpi_key, kpi_category, num_value, text_value, metadata_json, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        ("kpi_sec_1", "security", 98.5, "HIGH", '{"level": 1}', "2026-09-23T00:00:00Z"),
    )


def _insert_threat_sample(conn: Any) -> None:
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO threat_trends (name, category, count, prev_count, growth_pct, sample_ids, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        ("Ransomware", "Malware", 42, 30, 40.0, "2609.001", "2026-09-23T00:00:00Z"),
    )


def _insert_spider_sample(conn: Any) -> None:
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO spider_execution_logs ("
        "job_id, spider_name, status, started_at, finished_at, "
        "duration_seconds, item_count, http_status_counts, error_message, params"
        ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            "job_001",
            "arxiv_spider",
            "SUCCESS",
            "2026-09-23T00:00:00Z",
            "2026-09-23T00:01:00Z",
            60.0,
            10,
            '{"200": 10}',
            None,
            "{}",
        ),
    )


def _insert_cti_sample(conn: Any) -> None:
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO cti_tactics (tactic_id, shortname, name, description, external_url) "
        "VALUES (?, ?, ?, ?, ?)",
        (
            "TA0001",
            "initial-access",
            "Initial Access",
            "Adversary entry point",
            "https://attack.mitre.org/tactics/TA0001",
        ),
    )


def _insert_kev_sample(conn: Any) -> None:
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO cisa_kev_vulnerabilities ("
        "cve_id, vendor_project, product, vulnerability_name, date_added, "
        "short_description, required_action, due_date, known_ransomware_campaign_use, notes"
        ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            "CVE-2026-9999",
            "VendorA",
            "ProdB",
            "RCE",
            "2026-09-23",
            "Desc",
            "Apply patch",
            "2026-10-01",
            "Known",
            "Notes",
        ),
    )


def _insert_differential_samples(conn: Any) -> None:
    _insert_kpi_sample(conn)
    _insert_threat_sample(conn)
    _insert_spider_sample(conn)
    _insert_cti_sample(conn)
    _insert_kev_sample(conn)
    conn.commit()


def _query_and_compare(py_conn: Any, sq_conn: Any, query: str) -> None:
    py_rows = py_conn.cursor().execute(query).fetchall()
    sq_rows = sq_conn.cursor().execute(query).fetchall()
    assert py_rows == sq_rows, f"Query result divergence on: {query}"


def _verify_dml_equality(py_conn: Any, sq_conn: Any) -> None:
    _query_and_compare(
        py_conn,
        sq_conn,
        "SELECT kpi_key, kpi_category, num_value FROM strategic_kpis ORDER BY kpi_key",
    )
    _query_and_compare(
        py_conn,
        sq_conn,
        "SELECT name, category, count, growth_pct FROM threat_trends ORDER BY name",
    )
    _query_and_compare(
        py_conn,
        sq_conn,
        "SELECT job_id, spider_name, status, duration_seconds FROM spider_execution_logs ORDER BY job_id",
    )
    _query_and_compare(
        py_conn,
        sq_conn,
        "SELECT tactic_id, shortname, name FROM cti_tactics ORDER BY tactic_id",
    )
    _query_and_compare(
        py_conn,
        sq_conn,
        "SELECT cve_id, vendor_project, product FROM cisa_kev_vulnerabilities ORDER BY cve_id",
    )


def test_differential_migration_up_and_schema_parity(tmp_path: Path) -> None:
    """Verifies that running 'up' produces 100% identical schemas on PyDB and SQLite."""
    pydb_mgr, sqlite_mgr = _init_dual_managers(tmp_path)
    try:
        py_applied = pydb_mgr.up()
        sq_applied = sqlite_mgr.up()

        assert [m.version for m in py_applied] == [m.version for m in sq_applied]
        assert [m.name for m in py_applied] == [m.name for m in sq_applied]

        py_conn = pydb_mgr.adapter.connect()
        sq_conn = sqlite_mgr.adapter.connect()
        _verify_schema_equality(py_conn, sq_conn)
    finally:
        pydb_mgr.close()
        sqlite_mgr.close()


def test_differential_dml_and_query_parity(tmp_path: Path) -> None:
    """Verifies that inserting and querying data produces identical row tuples."""
    pydb_mgr, sqlite_mgr = _init_dual_managers(tmp_path)
    try:
        pydb_mgr.up()
        sqlite_mgr.up()

        py_conn = pydb_mgr.adapter.connect()
        sq_conn = sqlite_mgr.adapter.connect()

        _insert_differential_samples(py_conn)
        _insert_differential_samples(sq_conn)
        _verify_dml_equality(py_conn, sq_conn)
    finally:
        pydb_mgr.close()
        sqlite_mgr.close()


def test_differential_rollback_parity(tmp_path: Path) -> None:
    """Verifies that running 'down' rolls back baseline symmetrically on both engines."""
    pydb_mgr, sqlite_mgr = _init_dual_managers(tmp_path)
    try:
        pydb_mgr.up()
        sqlite_mgr.up()

        py_rolled = pydb_mgr.down(steps=1)
        sq_rolled = sqlite_mgr.down(steps=1)
        assert py_rolled == sq_rolled == ["0001"]

        py_conn = pydb_mgr.adapter.connect()
        sq_conn = sqlite_mgr.adapter.connect()

        py_tables = _extract_table_names(py_conn)
        sq_tables = _extract_table_names(sq_conn)
        assert py_tables == sq_tables == ["schema_migrations"]

        py_count = (
            py_conn.cursor()
            .execute("SELECT COUNT(*) FROM schema_migrations")
            .fetchone()[0]
        )
        sq_count = (
            sq_conn.cursor()
            .execute("SELECT COUNT(*) FROM schema_migrations")
            .fetchone()[0]
        )
        assert py_count == sq_count == 0
    finally:
        pydb_mgr.close()
        sqlite_mgr.close()


def test_differential_reapply_idempotency(tmp_path: Path) -> None:
    """Verifies that re-applying 'up' after 'down' restores identical schema."""
    pydb_mgr, sqlite_mgr = _init_dual_managers(tmp_path)
    try:
        pydb_mgr.up()
        sqlite_mgr.up()

        pydb_mgr.down(steps=1)
        sqlite_mgr.down(steps=1)

        py_reapplied = pydb_mgr.up()
        sq_reapplied = sqlite_mgr.up()
        assert (
            [m.version for m in py_reapplied]
            == [m.version for m in sq_reapplied]
            == ["0001"]
        )

        py_conn = pydb_mgr.adapter.connect()
        sq_conn = sqlite_mgr.adapter.connect()
        _verify_schema_equality(py_conn, sq_conn)
    finally:
        pydb_mgr.close()
        sqlite_mgr.close()
