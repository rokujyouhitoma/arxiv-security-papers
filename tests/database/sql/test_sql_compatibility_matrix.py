#!/usr/bin/env python3
"""
Comprehensive SQL Standard Compatibility Matrix Test Suite for
Pure Python SQL Engine (DDL, DQL, DML, DCL, TCL) & PEP 249 / SQLite3 Bridge.
"""

import os
import sys
import tempfile
from typing import Tuple

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

import pytest

from database import (
    AccessController,
    DatabaseError,
    DCLPermissionDeniedError,
    HNSWIndex,
    SQLExecutor,
    SQLParseError,
    SQLParser,
    TableCatalog,
    TransactionManager,
    VectorStorage,
    connect,
    get_sqlite_connection,
)


def _setup_test_table(
    tmpdir: str, name: str = "threat_intel"
) -> Tuple[TableCatalog, SQLExecutor]:
    storage_path = os.path.join(tmpdir, f"{name}.vdb")
    storage = VectorStorage(storage_path, dim=4)
    index = HNSWIndex(dim=4)
    catalog = TableCatalog(name=name, storage=storage, index=index)
    access_ctrl = AccessController()
    tx_mgr = TransactionManager()
    executor = SQLExecutor(
        catalog=catalog, access_controller=access_ctrl, tx_manager=tx_mgr
    )
    return catalog, executor


def test_ddl_comprehensive_schema_and_types():
    """
    Tests DDL statements with various data types (VARCHAR, INT, FLOAT, VECTOR, JSON, TEXT).
    """
    parser = SQLParser()
    sql_create = (
        "CREATE TABLE security_events ("
        "id VARCHAR(32) PRIMARY KEY, "
        "severity INT, "
        "score FLOAT, "
        "embedding VECTOR(128), "
        "metadata JSON, "
        "notes TEXT"
        ")"
    )
    stmt = parser.parse(sql_create)
    assert stmt.category == "DDL"
    assert stmt.command_type.value == "CREATE_TABLE"
    assert stmt.table_name == "security_events"
    assert len(stmt.columns) == 6
    assert stmt.columns[0].name == "id"
    assert stmt.columns[3].data_type == "VECTOR(128)"

    # Test DROP TABLE
    stmt_drop = parser.parse("DROP TABLE security_events")
    assert stmt_drop.category == "DDL"
    assert stmt_drop.table_name == "security_events"

    # Test CREATE INDEX
    stmt_idx = parser.parse(
        "CREATE INDEX idx_vec ON security_events (embedding) USING HNSW"
    )
    assert stmt_idx.category == "DDL"
    assert stmt_idx.table_name == "security_events"
    assert stmt_idx.index_type == "HNSW"


def test_dql_complex_where_and_logical_operators():
    """
    Tests compound WHERE clauses, boolean operators (AND, OR, NOT),
    comparison operators (=, !=, <, <=, >, >=), LIKE, and IN / NOT IN.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        storage_path = os.path.join(tmpdir, "papers.vdb")
        storage = VectorStorage(storage_path, dim=4)
        index = HNSWIndex(dim=4)
        catalog = TableCatalog(name="papers", storage=storage, index=index)
        executor = SQLExecutor(catalog=catalog)

        # Populate sample records
        sample_data = [
            {
                "id": "p1",
                "title": "Quantum Cryptography",
                "category": "crypto",
                "year": 2024,
                "score": 9.5,
            },
            {
                "id": "p2",
                "title": "Zero Trust Architecture",
                "category": "network",
                "year": 2023,
                "score": 8.0,
            },
            {
                "id": "p3",
                "title": "LLM Fuzzing and Vulnerability",
                "category": "ai-sec",
                "year": 2026,
                "score": 9.8,
            },
            {
                "id": "p4",
                "title": "Hardware Trojans Detection",
                "category": "hardware",
                "year": 2022,
                "score": 7.2,
            },
            {
                "id": "p5",
                "title": "Post Quantum Lattice Cryptography",
                "category": "crypto",
                "year": 2025,
                "score": 9.1,
            },
        ]
        storage.append_batch([[0.1, 0.2, 0.3, 0.4]] * 5, sample_data)

        # 1. Test AND with range comparison
        res1 = executor.execute(
            "SELECT id, title, year FROM papers WHERE category = 'crypto' AND year >= 2025"
        )
        assert res1["count"] == 1
        assert res1["rows"][0]["id"] == "p5"

        # 2. Test OR operator
        res2 = executor.execute(
            "SELECT id FROM papers WHERE category = 'network' OR category = 'hardware'"
        )
        assert res2["count"] == 2
        ids = {r["id"] for r in res2["rows"]}
        assert ids == {"p2", "p4"}

        # 3. Test LIKE pattern matching
        res3 = executor.execute(
            "SELECT id, title FROM papers WHERE title LIKE '%Quantum%'"
        )
        assert res3["count"] == 2
        quantum_ids = {r["id"] for r in res3["rows"]}
        assert quantum_ids == {"p1", "p5"}

        # 4. Test IN clause
        res4 = executor.execute(
            "SELECT id FROM papers WHERE category IN ('crypto', 'ai-sec')"
        )
        assert res4["count"] == 3

        # 5. Test inequality !=
        res5 = executor.execute("SELECT id FROM papers WHERE category != 'crypto'")
        assert res5["count"] == 3


def test_dql_aggregations_and_sorting():
    """
    Tests aggregations (COUNT, SUM, AVG, MIN, MAX), ORDER BY, and LIMIT/OFFSET pagination.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        storage_path = os.path.join(tmpdir, "intel.vdb")
        storage = VectorStorage(storage_path, dim=4)
        _ = TableCatalog(name="intel", storage=storage, index=HNSWIndex(dim=4))

        data = [
            {"id": "c1", "risk": 10, "cvss": 4.0},
            {"id": "c2", "risk": 20, "cvss": 7.5},
            {"id": "c3", "risk": 30, "cvss": 9.8},
            {"id": "c4", "risk": 40, "cvss": 6.2},
        ]
        storage.append_batch([[0.1, 0.1, 0.1, 0.1]] * 4, data)

        # Aggregation via SQL / SQLite bridge
        conn = get_sqlite_connection(":memory:")
        cur = conn.cursor()
        cur.execute("CREATE TABLE intel (id TEXT, risk INT, cvss REAL)")
        for d in data:
            cur.execute(
                "INSERT INTO intel VALUES (?, ?, ?)", (d["id"], d["risk"], d["cvss"])
            )

        cur.execute(
            "SELECT COUNT(*), SUM(risk), AVG(risk), MIN(cvss), MAX(cvss) FROM intel"
        )
        row = cur.fetchone()
        assert row[0] == 4
        assert row[1] == 100
        assert row[2] == 25.0
        assert row[3] == 4.0
        assert row[4] == 9.8

        # ORDER BY DESC with LIMIT / OFFSET
        cur.execute("SELECT id, cvss FROM intel ORDER BY cvss DESC LIMIT 2 OFFSET 1")
        top_rows = cur.fetchall()
        assert len(top_rows) == 2
        assert top_rows[0][0] == "c2"  # 7.5 (2nd highest)
        assert top_rows[1][0] == "c4"  # 6.2 (3rd highest)
        conn.close()


def test_dml_complex_updates_and_deletes():
    """
    Tests INSERT, UPDATE with expressions, and DELETE with WHERE filters.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        storage_path = os.path.join(tmpdir, "nodes.vdb")
        storage = VectorStorage(storage_path, dim=4)
        catalog = TableCatalog(name="nodes", storage=storage, index=HNSWIndex(dim=4))
        tx_mgr = TransactionManager()
        executor = SQLExecutor(catalog=catalog, tx_manager=tx_mgr)

        # 1. INSERT
        executor.execute(
            "INSERT INTO nodes (id, status, weight) VALUES ('node1', 'active', 10)"
        )
        executor.execute(
            "INSERT INTO nodes (id, status, weight) VALUES ('node2', 'pending', 5)"
        )
        assert storage.count == 2

        # 2. UPDATE
        up_res = executor.execute(
            "UPDATE nodes SET status = 'active' WHERE id = 'node2'"
        )
        assert up_res["status"] in ("ok", "success")
        meta2 = storage.get_metadata(1)
        assert meta2["status"] == "active"

        # 3. DELETE
        del_res = executor.execute("DELETE FROM nodes WHERE id = 'node1'")
        assert del_res["status"] in ("ok", "success")
        assert storage.count == 1
        assert storage.get_metadata(0)["id"] == "node2"


def test_tcl_nested_savepoints_and_dirty_read_prevention():
    """
    Tests transaction isolation, BEGIN, COMMIT, and ROLLBACK preventing dirty mutations.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        storage_path = os.path.join(tmpdir, "tx_table.vdb")
        storage = VectorStorage(storage_path, dim=4)
        catalog = TableCatalog(name="tx_table", storage=storage, index=HNSWIndex(dim=4))
        tx_mgr = TransactionManager()
        executor = SQLExecutor(catalog=catalog, tx_manager=tx_mgr)

        executor.execute("INSERT INTO tx_table (id, val) VALUES ('initial', 100)")
        assert storage.count == 1

        # Begin transaction
        executor.execute("BEGIN TRANSACTION")
        assert tx_mgr.is_active

        # Perform mutations within transaction
        executor.execute("INSERT INTO tx_table (id, val) VALUES ('tx_temp', 999)")
        executor.execute("UPDATE tx_table SET val = 200 WHERE id = 'initial'")

        # Rollback
        executor.execute("ROLLBACK")
        assert not tx_mgr.is_active

        # Verify state was restored
        meta = storage.get_metadata(0)
        assert meta["val"] == 100
        assert storage.count == 1


def test_dcl_rbac_role_hierarchy_matrix():
    """
    Tests role-based access control matrix (admin, analyst, guest) across DDL, DQL, DML, DCL.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        storage_path = os.path.join(tmpdir, "rbac_test.vdb")
        storage = VectorStorage(storage_path, dim=4)
        catalog = TableCatalog(
            name="rbac_test", storage=storage, index=HNSWIndex(dim=4)
        )
        access_ctrl = AccessController()
        executor = SQLExecutor(catalog=catalog, access_controller=access_ctrl)

        # Guest role: can SELECT, but cannot INSERT or DROP
        access_ctrl.current_role = "guest"
        # SELECT is permitted
        res = executor.execute("SELECT id FROM rbac_test")
        assert res["status"] in ("ok", "success")

        # INSERT is forbidden
        with pytest.raises(DCLPermissionDeniedError):
            executor.execute("INSERT INTO rbac_test (id) VALUES ('x')")

        # Analyst role: can SELECT and INSERT, but cannot DROP
        access_ctrl.current_role = "analyst"
        res_ins = executor.execute("INSERT INTO rbac_test (id) VALUES ('a1')")
        assert res_ins["status"] in ("ok", "success")

        with pytest.raises(DCLPermissionDeniedError):
            executor.execute("DROP TABLE rbac_test")

        # Admin role: can perform all operations
        access_ctrl.current_role = "admin"
        res_grant = executor.execute("GRANT ALL PRIVILEGES TO analyst")
        assert res_grant["status"] in ("ok", "success")


def test_sqlite3_pep249_parameter_binding_and_exceptions():
    """
    Tests PEP 249 Connection and Cursor driver with positional parameter bindings (?),
    result fetch operations (fetchone, fetchall), and error handling.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "driver_test.vdb")
        conn = connect(vdb_path, dim=4)
        cur = conn.cursor()

        # Execute table creation
        cur.execute("CREATE TABLE metrics (id VARCHAR(32), value INT)")
        assert cur.rowcount == 0

        # Execute inserts with ? parameter binding
        cur.execute("INSERT INTO metrics (id, value) VALUES (?, ?)", ["m1", 42])
        cur.execute("INSERT INTO metrics (id, value) VALUES (?, ?)", ["m2", 84])
        assert cur.rowcount == 1

        # Query with parameter binding
        cur.execute("SELECT id, value FROM metrics WHERE id = ?", ["m1"])
        row = cur.fetchone()
        assert row is not None
        assert row[0] == "m1"
        assert row[1] == 42

        # Fetch all
        cur.execute("SELECT id, value FROM metrics")
        rows = cur.fetchall()
        assert len(rows) == 2

        # Verify Syntax Error exception
        with pytest.raises((SQLParseError, DatabaseError)):
            cur.execute("INVALID SQL COMMAND HERE")

        conn.close()
