#!/usr/bin/env python3
"""
Comprehensive Unit Test Suite for In-Memory Database Mode (:memory:).
Validates zero disk I/O, MemoryVFS integration, PEP 249 compliance,
VectorStorage memory buffer, and SQLExecutor in-memory table lifecycle.
"""

import os
import shutil
from typing import Any

import pytest

from src.database import (
    Connection,
    Pager,
    SQLExecutor,
    VectorStorage,
    connect,
    get_sqlite_connection,
)
from src.database.compat.sqlite_engine import sync_to_vector_storage
from src.database.storage.vfs import MemoryVFS


@pytest.fixture(autouse=True)
def clean_memory_artifacts() -> Any:
    """Ensure no :memory: physical artifacts exist before and after tests."""
    target_artifacts = [":memory:", ":memory:.tmp", ":memory:.vdb-wal"]
    for art in target_artifacts:
        if os.path.exists(art):
            if os.path.isdir(art):
                shutil.rmtree(art)
            else:
                os.remove(art)
    yield
    for art in target_artifacts:
        assert not os.path.exists(art), f"Physical file leaked to disk: {art}"


def test_sqlite_engine_in_memory() -> None:
    """Test standard sqlite3 connection with :memory: without creating disk file."""
    conn = get_sqlite_connection(":memory:", enable_wal=True)
    cur = conn.cursor()

    cur.execute("CREATE TABLE test_items (id INT, name TEXT)")
    cur.execute("INSERT INTO test_items VALUES (1, 'item1'), (2, 'item2')")
    conn.commit()

    rows = cur.execute("SELECT * FROM test_items ORDER BY id").fetchall()
    assert len(rows) == 2
    assert rows[0][1] == "item1"

    res = cur.execute("SELECT COSINE_SIM('[1,0]', '[1,0]')").fetchone()
    assert res is not None
    assert abs(float(res[0]) - 1.0) < 1e-5

    embed_res = cur.execute("SELECT EMBED('security')").fetchone()
    assert embed_res is not None
    assert isinstance(embed_res[0], str)
    assert embed_res[0].startswith("[")

    conn.close()
    assert not os.path.exists(":memory:")


def test_sqlite_engine_empty_string() -> None:
    """Test sqlite3 connection with empty string path resolves to in-memory."""
    conn = get_sqlite_connection("", enable_wal=False)
    cur = conn.cursor()
    cur.execute("CREATE TABLE t (x INT)")
    cur.execute("INSERT INTO t VALUES (42)")
    res = cur.execute("SELECT x FROM t").fetchone()
    assert res is not None and res[0] == 42
    conn.close()


def test_vector_storage_in_memory() -> None:
    """Test VectorStorage(:memory:) lifecycle, serialization, and retrieval."""
    storage = VectorStorage(":memory:", dim=4)
    assert storage.is_memory is True
    assert storage.file_path == ":memory:"
    assert storage.count == 0

    storage.open_mmap()

    v1 = [1.0, 0.0, 0.0, 0.0]
    idx1 = storage.append(v1, metadata={"id": "doc1", "title": "Paper 1"})
    assert idx1 == 0
    assert storage.count == 1

    v2 = [0.0, 1.0, 0.0, 0.0]
    v3 = [0.0, 0.0, 1.0, 0.0]
    indices = storage.append_batch(
        [v2, v3],
        metadata=[{"id": "doc2", "title": "P2"}, {"id": "doc3", "title": "P3"}],
    )
    assert indices == [1, 2]
    assert storage.count == 3

    vec_ret = storage.get_vector(0)
    assert tuple(vec_ret) == tuple(v1)

    by_id = storage.get_vector_by_id("doc2")
    assert by_id is not None
    assert tuple(by_id) == tuple(v2)

    all_vecs = storage.get_all_vectors()
    assert len(all_vecs) == 3

    meta1 = storage.get_metadata(0)
    assert meta1["title"] == "Paper 1"

    data_bytes = storage.to_bytes()
    assert len(data_bytes) > 32
    assert data_bytes[:8] == b"OKFVEC01"

    storage.close()
    assert storage.count == 0
    assert len(storage.get_all_vectors()) == 0
    assert not os.path.exists(":memory:")


def test_vector_storage_in_memory_validation() -> None:
    """Test dimension validation and bounds in VectorStorage(:memory:)."""
    storage = VectorStorage(":memory:", dim=3)
    with pytest.raises(ValueError):
        storage.append([1.0, 2.0])

    with pytest.raises(IndexError):
        storage.get_vector(0)

    with pytest.raises(IndexError):
        storage.get_metadata(0)

    assert storage.get_vector_by_id("non_existent") is None
    storage.close()


def test_bidirectional_sync_in_memory() -> None:
    """Test sync_from_vector_storage and sync_to_vector_storage in-memory."""
    storage = VectorStorage(":memory:", dim=2)
    storage.append([0.5, 0.5], metadata={"id": "p1", "title": "Sync Test"})

    conn = get_sqlite_connection(
        ":memory:", storage=storage, init_schema=True, table_name="papers"
    )
    cur = conn.cursor()
    row = cur.execute("SELECT id, title FROM papers WHERE id='p1'").fetchone()
    assert row is not None
    assert row["title"] == "Sync Test"

    cur.execute(
        "INSERT INTO papers (id, title, category, vector, metadata) "
        "VALUES ('p2', 'SQLite Paper', 'cs.CR', '[0.1, 0.9]', '{\"year\": 2026}')"
    )
    conn.commit()

    sync_to_vector_storage(conn, storage, table_name="papers")
    assert storage.count == 2
    assert storage.get_vector_by_id("p2") is not None

    conn.close()
    storage.close()
    assert not os.path.exists(":memory:")


def test_pager_in_memory() -> None:
    """Test Pager with :memory: automatically using MemoryVFS."""
    pager = Pager(":memory:", use_wal=True)
    assert isinstance(pager.vfs, MemoryVFS)

    page_data = bytearray(b"A" * 4096)
    pager.write_page(0, page_data)
    assert pager.page_count() >= 1

    read_back = pager.read_page(0)
    assert read_back == page_data

    pager.flush_all()
    pager.close()
    assert not os.path.exists(":memory:")
    assert not os.path.exists(":memory:.vdb-wal")


def test_sql_executor_in_memory() -> None:
    """Test SQLExecutor creating in-memory tables without creating .vdb files."""
    default_storage = VectorStorage(":memory:", dim=128)
    executor = SQLExecutor(default_storage=default_storage)

    create_res = executor.execute(
        "CREATE TABLE memory_metrics (id VARCHAR, metric_val FLOAT)"
    )
    assert create_res["status"] == "ok"
    assert "memory_metrics" in executor.tables
    assert executor.tables["memory_metrics"].storage.is_memory is True

    disk_vdb = os.path.join("outputs", "database", "memory_metrics.vdb")
    assert not os.path.exists(disk_vdb)

    executor.execute("INSERT INTO memory_metrics (id, metric_val) VALUES ('m1', 99.5)")
    sel_res = executor.execute("SELECT id, metric_val FROM memory_metrics")
    assert sel_res["status"] == "ok"
    assert len(sel_res["rows"]) == 1
    assert sel_res["rows"][0]["id"] == "m1"

    show_res = executor.execute("SHOW TABLES")
    assert show_res["status"] == "ok"
    assert any(r["Table"] == "memory_metrics" for r in show_res["rows"])

    drop_res = executor.execute("DROP TABLE memory_metrics")
    assert drop_res["status"] == "ok"
    assert "memory_metrics" not in executor.tables
    assert not os.path.exists(disk_vdb)

    default_storage.close()


def test_pep249_driver_in_memory() -> None:
    """Test PEP 249 connect(:memory:) driver operations."""
    conn = connect(database=":memory:", dim=128)
    assert isinstance(conn, Connection)

    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO papers (id, title, category) VALUES ('test_p1', 'PEEP Title', 'cs.CR')"
    )
    conn.commit()

    cursor.execute("SELECT id, title FROM papers WHERE id = 'test_p1'")
    one = cursor.fetchone()
    assert one is not None
    assert one[0] == "test_p1"
    assert one[1] == "PEEP Title"

    cursor.execute("SELECT id, title FROM papers")
    dicts = cursor.fetchall_dict()
    assert len(dicts) == 1
    assert dicts[0]["id"] == "test_p1"

    cursor.close()
    conn.close()
    assert not os.path.exists(":memory:")


def test_independent_memory_instances() -> None:
    """Verify independent memory spaces across multiple connections."""
    s1 = VectorStorage(":memory:", dim=4)
    s2 = VectorStorage(":memory:", dim=4)

    s1.append([1.0, 0.0, 0.0, 0.0], metadata={"id": "s1_p1"})
    assert s1.count == 1
    assert s2.count == 0

    s1.close()
    s2.close()

    c1 = get_sqlite_connection(":memory:")
    c2 = get_sqlite_connection(":memory:")
    try:
        c1.execute("CREATE TABLE t1 (val INT)")
        c1.execute("INSERT INTO t1 VALUES (100)")
        c1.commit()

        with pytest.raises(Exception):
            c2.execute("SELECT * FROM t1").fetchall()
    finally:
        c1.close()
        c2.close()


def test_security_path_traversal_protection() -> None:
    """Ensure non-exact :memory: paths are not treated as in-memory mode."""
    invalid_path = ":memory:/../test.db"
    storage = VectorStorage(invalid_path, dim=4)
    assert storage.is_memory is False
    assert storage.file_path != ":memory:"
    storage.close()


def test_security_bounds_enforcement() -> None:
    """Ensure MAX_VECTOR_COUNT and dimension bounds are enforced in memory mode."""
    storage = VectorStorage(":memory:", dim=4)
    with pytest.raises(ValueError):
        storage.write_all([[1.0, 2.0, 3.0, 4.0]] * (storage.MAX_VECTOR_COUNT + 1))
    storage.close()
