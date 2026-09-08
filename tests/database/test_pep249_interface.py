#!/usr/bin/env python3
"""
Unit Tests for PEP 249 DB-API 2.0 Driver Interface with Multi-Table Containers.
Verifies connect, cursor, execute, executemany, fetchall, commit, and persistence
without requiring sqlite3 C-extensions.
"""

import os
import sys

import pytest

from database import Connection, connect


@pytest.fixture
def temp_vdb_path(tmp_path: pytest.TempPathFactory) -> str:
    return str(tmp_path / "test_pep249_graph.vdb")  # type: ignore[operator]


def test_zero_sqlite3_import() -> None:
    """Verifies that the PEP 249 pure-Python driver doesn't rely on sqlite3."""
    driver_mod = sys.modules.get("database.ipc.driver")
    assert driver_mod is not None
    assert "sqlite3" not in driver_mod.__dict__


def _populate_users(conn: Connection) -> None:
    cur = conn.cursor()
    cur.execute("CREATE TABLE users (id TEXT, name TEXT, role TEXT)")
    cur.execute("CREATE TABLE audits (id TEXT, action TEXT)")
    cur.execute(
        "INSERT INTO users (id, name, role) VALUES (?, ?, ?)",
        ("u1", "Alice", "admin"),
    )
    cur.execute(
        "INSERT INTO users (id, name, role) VALUES (?, ?, ?)",
        ("u2", "Bob", "analyst"),
    )


def test_pep249_memory_connection() -> None:
    """Tests in-memory DB-API 2.0 operations with multi-table support."""
    conn = connect(":memory:")
    _populate_users(conn)
    cursor = conn.cursor()
    cursor.execute("SELECT id, name, role FROM users")
    rows = cursor.fetchall()
    assert len(rows) == 2
    assert rows[0] == ("u1", "Alice", "admin")
    conn.close()


def test_pep249_executemany() -> None:
    """Tests executemany insertion and count."""
    with connect(":memory:") as conn:
        conn.execute("CREATE TABLE items (id TEXT, value INT)")
        items = [("i1", 100), ("i2", 200), ("i3", 300)]
        conn.executemany("INSERT INTO items (id, value) VALUES (?, ?)", items)
        cur = conn.execute("SELECT id, value FROM items")
        assert len(cur.fetchall()) == 3


def test_pep249_fetch_steps() -> None:
    """Tests fetchone and fetchmany progression."""
    with connect(":memory:") as conn:
        conn.execute("CREATE TABLE items (id TEXT, value INT)")
        items = [("i1", 100), ("i2", 200), ("i3", 300)]
        conn.executemany("INSERT INTO items (id, value) VALUES (?, ?)", items)
        cur = conn.execute("SELECT id, value FROM items")
        assert cur.fetchone() == ("i1", 100)
        assert len(cur.fetchmany(2)) == 2
        assert cur.fetchone() is None


def _init_persistent_graph(path: str) -> None:
    conn = connect(path)
    cur = conn.cursor()
    cur.execute("CREATE TABLE vertices (id TEXT, label TEXT)")
    cur.execute("CREATE TABLE edges (source TEXT, target TEXT, rel TEXT)")
    cur.execute(
        "INSERT INTO vertices (id, label) VALUES (?, ?)",
        ("node_a", "Service"),
    )
    cur.execute(
        "INSERT INTO vertices (id, label) VALUES (?, ?)",
        ("node_b", "Database"),
    )
    cur.execute(
        "INSERT INTO edges (source, target, rel) VALUES (?, ?, ?)",
        ("node_a", "node_b", "CONNECTS_TO"),
    )
    conn.commit()
    conn.close()


def test_pep249_persistent_file_header(temp_vdb_path: str) -> None:
    """Verifies OKFMTC01 header generation on persistent file."""
    _init_persistent_graph(temp_vdb_path)
    assert os.path.exists(temp_vdb_path)
    with open(temp_vdb_path, "rb") as f:
        assert f.read(8) == b"OKFMTC01"


def test_pep249_persistent_file_reload(temp_vdb_path: str) -> None:
    """Tests re-opening persisted container and reading multiple tables."""
    _init_persistent_graph(temp_vdb_path)
    with connect(temp_vdb_path) as conn:
        assert set(conn.tables) == {"vertices", "edges"}
        cur = conn.cursor()
        cur.execute("SELECT id, label FROM vertices")
        assert len(cur.fetchall()) == 2
        cur.execute("SELECT source, target, rel FROM edges")
        assert cur.fetchone() == ("node_a", "node_b", "CONNECTS_TO")


def test_pep249_drop_table(temp_vdb_path: str) -> None:
    """Tests dropping a table from multi-table container."""
    with connect(temp_vdb_path) as conn:
        conn.execute("CREATE TABLE t1 (id TEXT)")
        conn.execute("CREATE TABLE t2 (id TEXT)")
        conn.commit()
        conn.execute("DROP TABLE t1")
        conn.commit()

    with connect(temp_vdb_path) as conn_reopened:
        assert "t1" not in conn_reopened.tables
        assert "t2" in conn_reopened.tables
