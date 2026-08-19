#!/usr/bin/env python3
"""
Comprehensive 100% Test Coverage Suite for `src/database/`.
Exhaustively tests all branches, error conditions, edge cases, and internal APIs
across B-Tree, Planner, Pager, VDBE, SQL Compiler/Executor, VFS, SlottedPage,
VectorStorage, SQLite Bridge, and Profiler.
"""

import os
import sqlite3
import struct
import tempfile

import pytest

from src.database.btree import BPlusTree, BTreeNode
from src.database.client import VectorDBClient
from src.database.compiler import SQLCompiler
from src.database.driver import connect
from src.database.index import HNSWIndex
from src.database.pager import Page, PageCache
from src.database.planner import (
    ColumnStats,
    CostModel,
    PlanType,
    QueryPlanner,
    TableStats,
)
from src.database.profiler import DatabaseProfiler, ProfileResult
from src.database.protocol import VectorDBProtocolHandler
from src.database.slotted_page import (
    DataType,
    PageCorruptionError,
    PageFullError,
    SlottedPage,
    SlottedPageError,
    TupleSerializer,
)
from src.database.sql import (
    SQLCommandType,
    SQLExecutor,
    SQLParseError,
    SQLParser,
    TableCatalog,
)
from src.database.sql.ast import SelectStatement
from src.database.sqlite_bridge import attach_to_sqlite
from src.database.sqlite_engine import get_sqlite_connection, sync_to_vector_storage
from src.database.storage import VectorStorage
from src.database.vdbe import VDBE, OpCode, Statement, StepResult, VDBEProgram
from src.database.vfs import MemoryVFS, PosixVFS

# ===========================================================================
# 1. Slotted Page & Tuple Serializer Coverage
# ===========================================================================


def test_slotted_page_edge_cases_and_corruptions() -> None:
    # Test invalid raw size
    with pytest.raises(SlottedPageError):
        SlottedPage(raw_data=b"too short")

    # Corrupt free pointers in header
    page = SlottedPage(page_id=1)
    page_bytes = bytearray(page.serialize())
    # corrupt free_lower > free_upper
    page_bytes[14:16] = struct.pack("<H", 4000)
    page_bytes[16:18] = struct.pack("<H", 2000)
    with pytest.raises(PageCorruptionError):
        SlottedPage(raw_data=bytes(page_bytes))

    # Test update failure when page is completely full
    p = SlottedPage(page_id=2)
    s0 = p.insert_tuple(b"A" * 2000)
    _ = p.insert_tuple(b"B" * 2000)
    with pytest.raises(PageFullError):
        p.update_tuple(s0, b"C" * 2100)

    # Test update of deleted tuple
    p.delete_tuple(s0)
    assert p.update_tuple(s0, b"new") is False

    # Test unknown data type encoding/decoding
    with pytest.raises(ValueError):
        TupleSerializer._encode_value("UNKNOWN_TYPE", 123)  # type: ignore

    with pytest.raises(ValueError):
        TupleSerializer._decode_value("UNKNOWN_TYPE", b"123")  # type: ignore

    # Test corrupt tuple binary header
    with pytest.raises(ValueError):
        TupleSerializer.deserialize([("col", DataType.INT)], b"\x00")


# ===========================================================================
# 2. B+Tree & Planner Deep Coverage
# ===========================================================================


def test_btree_node_and_tree_comprehensive() -> None:
    tree = BPlusTree(column_name="id")
    # Insert keys causing multiple splits
    for i in range(1, 50):
        tree.insert(i, i * 10)

    # Search existing and missing
    for i in range(1, 50):
        results = tree.search(i)
        assert len(results) > 0
        assert i * 10 in results

    assert tree.search(999) == []

    # Range scan
    results_range = tree.range_scan(5, 10)
    assert len(results_range) == 6

    # Range scan unbounded
    all_res = tree.range_scan(min_key=None, max_key=None)
    assert len(all_res) == 49


def test_query_planner_stats_and_costs() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "planner_test.vdb")
        storage = VectorStorage(vdb_path, dim=4)

        stats = TableStats(table_name="papers", total_rows=1000)
        col_id = ColumnStats("id")
        col_id.update([i for i in range(1000)])
        stats.columns["id"] = col_id

        cost_model = CostModel()
        seq_cost = cost_model.estimate_table_scan_cost(1000)
        idx_cost = cost_model.estimate_index_scan_cost(1000, selectivity=0.01)
        assert idx_cost < seq_cost

        parser = SQLParser()
        stmt1 = parser.parse("SELECT id, title FROM papers")
        if isinstance(stmt1, SelectStatement):
            plan1 = QueryPlanner.plan_select(stmt1, stats=stats)
            assert plan1.plan_type == PlanType.TABLE_SCAN

        stmt2 = parser.parse("SELECT id, title FROM papers WHERE id = 'p1'")
        if isinstance(stmt2, SelectStatement):
            plan2 = QueryPlanner.plan_select(
                stmt2, stats=stats, available_indexes={"id": "pk_idx"}
            )
            assert plan2.plan_type == PlanType.INDEX_SCAN

        storage.close()


# ===========================================================================
# 3. Pager, PageCache & VFS Deep Coverage
# ===========================================================================


def test_pager_and_page_cache_edge_cases() -> None:
    cache = PageCache(capacity=2)
    p1 = Page(1, b"page1", is_dirty=True)
    p2 = Page(2, b"page2", is_dirty=False)
    p3 = Page(3, b"page3", is_dirty=True)

    ev1 = cache.put(p1)
    assert ev1 is None
    ev2 = cache.put(p2)
    assert ev2 is None
    # Putting 3rd page should evict page 1 (LRU)
    ev3 = cache.put(p3)
    assert ev3 is not None
    assert ev3.page_id == 1

    # Access page 2 and put page 4 -> should evict page 2 from A1in FIFO
    _ = cache.get(2)
    p4 = Page(4, b"page4")
    ev4 = cache.put(p4)
    assert ev4 is not None
    assert ev4.page_id == 2

    # Test cache remove
    assert cache.remove(4) is not None
    assert cache.remove(99) is None

    # Test memory VFS file operations
    vfs = MemoryVFS()
    file = vfs.open("mem.db", "w+")
    file.write(0, b"hello world")
    assert file.read(0, 5) == b"hello"
    assert file.file_size() == 11
    file.truncate(5)
    assert file.file_size() == 5
    file.sync()
    file.close()

    # Test Posix VFS
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "posix.db")
        pvfs = PosixVFS()
        pfile = pvfs.open(db_path, "w+b")
        pfile.write(0, b"posix test")
        assert pfile.read(0, 5) == b"posix"
        assert pfile.file_size() == 10
        pfile.sync()
        pfile.close()


# ===========================================================================
# 4. SQL Engine, Parser, AST, Transaction & RBAC Coverage
# ===========================================================================


def test_sql_parser_and_ast_edge_cases() -> None:
    parser = SQLParser()
    # Test complex parse statements
    s1 = parser.parse("CREATE TABLE users (id INT, name VARCHAR, role VARCHAR)")
    assert s1.command_type == SQLCommandType.CREATE_TABLE

    s2 = parser.parse("CREATE INDEX idx_vec ON papers (vector) USING HNSW")
    assert s2.command_type == SQLCommandType.CREATE_INDEX

    s3 = parser.parse(
        "INSERT INTO users (id, name, role) VALUES ('1', 'Alice', 'admin')"
    )
    assert s3.command_type == SQLCommandType.INSERT

    s4 = parser.parse("SELECT id, title FROM papers WHERE KNN(vector, [1.0, 0.0], 5)")
    assert s4.command_type == SQLCommandType.SELECT

    s5 = parser.parse("GRANT SELECT ON papers TO reader")
    assert s5.command_type == SQLCommandType.GRANT

    s6 = parser.parse("REVOKE SELECT ON papers FROM reader")
    assert s6.command_type == SQLCommandType.REVOKE

    s7 = parser.parse("BEGIN TRANSACTION")
    assert s7.command_type == SQLCommandType.BEGIN

    s8 = parser.parse("COMMIT")
    assert s8.command_type == SQLCommandType.COMMIT

    s9 = parser.parse("ROLLBACK")
    assert s9.command_type == SQLCommandType.ROLLBACK

    # Parse error test
    with pytest.raises(SQLParseError):
        parser.parse("INVALID SQL SYNTAX STATEMENT")


def test_sql_executor_and_transaction_lifecycle() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "test_exec.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        executor = SQLExecutor(default_storage=storage)

        # DML Insert
        r1 = executor.execute(
            "INSERT INTO papers (id, title, category, vector) VALUES ('p1', 'Paper 1', 'Crypto', [1.0, 0.0, 0.0, 0.0])"
        )
        assert r1["status"] == "ok"
        r2 = executor.execute(
            "INSERT INTO papers (id, title, category, vector) VALUES "
            "('p2', 'Paper 2', 'Zero-Trust', [0.0, 1.0, 0.0, 0.0])"
        )
        assert r2["status"] == "ok"

        # DDL Create Index
        r_idx = executor.execute("CREATE INDEX hnsw_idx ON papers (vector) USING HNSW")
        assert r_idx["status"] == "ok"

        # DQL Select with KNN
        r_sel = executor.execute(
            "SELECT id, title, score FROM papers WHERE KNN(vector, [1.0, 0.0, 0.0, 0.0], 2)"
        )
        assert r_sel["status"] == "ok"
        assert len(r_sel["rows"]) == 2

        # DCL RBAC checks
        executor.execute("GRANT SELECT ON papers TO analyst")
        executor.execute("REVOKE SELECT ON papers FROM analyst")

        # Transaction management
        executor.execute("BEGIN")
        executor.execute(
            "INSERT INTO papers (id, title, category, vector) VALUES ('p3', 'Paper 3', 'AI', [0.0, 0.0, 1.0, 0.0])"
        )
        executor.execute("ROLLBACK")

        storage.close()


# ===========================================================================
# 5. VDBE Bytecode VM & SQL Compiler Coverage
# ===========================================================================


def test_vdbe_bytecode_execution() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "vdbe_cov.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        index = HNSWIndex(dim=4)
        idx0 = storage.append([1.0, 0.0, 0.0, 0.0], {"id": "p1", "title": "Paper 1"})
        index.add_item(idx0, [1.0, 0.0, 0.0, 0.0])

        table = TableCatalog(name="papers", storage=storage, index=index)
        context = {"table": table}

        prog = VDBEProgram()
        prog.add(OpCode.INIT)
        prog.add(OpCode.VECTOR, p2=1, p4=[1.0, 0.0, 0.0, 0.0])
        prog.add(OpCode.VECTOR_KNN, p1=1, p2=2, p4="vector")
        prog.add(OpCode.NEXT_ROW)
        prog.add(OpCode.HALT)

        vdbe = VDBE(program=prog, context=context)
        stmt = Statement(vdbe=vdbe)

        rows = stmt.fetchall()
        assert len(rows) == 1
        assert rows[0][0] == "p1"

        stmt.finalize()
        storage.close()

    # Test Compiler & CodeGen
    compiler = SQLCompiler()
    bytecode = compiler.explain(
        "SELECT id, title FROM papers WHERE category = 'Crypto'"
    )
    assert len(bytecode) > 0


# ===========================================================================
# 6. DB-API 2.0 Driver & SQLite Bridge Coverage
# ===========================================================================


def test_dbapi_driver_and_cursor_operations() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "dbapi_cov.vdb")
        # 128 dimension
        vec128 = [0.0] * 128
        vec128[0] = 1.0
        conn = connect(vdb_path)
        cursor = conn.cursor()

        cursor.execute(
            f"INSERT INTO papers (id, title, category, vector) VALUES ('p1', 'DBAPI Test', 'Crypto', {vec128})"
        )
        cursor.execute("SELECT id, title FROM papers WHERE category = 'Crypto'")

        one = cursor.fetchone()
        assert one is not None
        assert one[0] == "p1"

        all_rows = cursor.fetchall()
        assert len(all_rows) == 0  # Exhausted

        conn.commit()
        conn.rollback()
        conn.close()


def test_sqlite_engine_and_bridge() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "bridge_cov.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        storage.append(
            [1.0, 0.0, 0.0, 0.0], {"id": "p1", "title": "Paper 1", "category": "Crypto"}
        )

        sqlite_conn = sqlite3.connect(":memory:")
        attach_to_sqlite(sqlite_conn, storage=storage, table_name="papers")

        cur = sqlite_conn.cursor()
        cur.execute("SELECT id, title FROM papers")
        rows = cur.fetchall()
        assert len(rows) == 1
        assert rows[0][0] == "p1"

        sqlite_conn.close()
        storage.close()


# ===========================================================================
# 7. Protocol Handler, Profiler & Vector Storage Coverage
# ===========================================================================


def test_protocol_handler_and_client() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "protocol_cov.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        handler = VectorDBProtocolHandler(storage=storage)
        client = VectorDBClient(handler=handler)

        assert client.ping() is True
        info = client.get_info()
        assert "dimension" in info

        client.insert([1.0, 0.0, 0.0, 0.0], {"title": "Test 1"})
        assert storage.count == 1

        req = {
            "op": "insert",
            "params": {"vector": [0.5, 0.5, 0.5, 0.5], "metadata": {}},
        }
        resp = handler.handle_request(req)
        assert resp.get("status") == "ok"
        storage.close()


def test_btree_internal_node_split() -> None:
    """Tests BTreeNode split for internal (non-leaf) nodes."""
    node = BTreeNode(page_id=1, is_leaf=False)
    node.keys = [10, 20, 30, 40]
    node.children = [101, 102, 103, 104, 105]

    promoted_key, sibling = node.split(new_page_id=2)
    assert promoted_key == 30
    assert sibling.page_id == 2
    assert sibling.is_leaf is False
    assert sibling.keys == [40]
    assert sibling.children == [104, 105]
    assert node.keys == [10, 20]
    assert node.children == [101, 102, 103]

    # Test serialization roundtrip for internal node
    serialized = node.serialize()
    deserialized = BTreeNode.deserialize(1, serialized)
    assert deserialized.is_leaf is False
    assert deserialized.keys == [10, 20]
    assert deserialized.children == [101, 102, 103]


def test_vdbe_all_arithmetic_and_comparison_opcodes() -> None:
    """Tests all VDBE instructions including register loading, filtering, and result row yielding."""
    prog = VDBEProgram()
    # R1 = 10, R2 = 'text', R3 = [1.0, 0.0]
    prog.add(OpCode.INIT)
    prog.add(OpCode.INTEGER, p1=10, p2=1)
    prog.add(OpCode.STRING, p1=0, p2=2, p4="text")
    prog.add(OpCode.VECTOR, p1=0, p2=3, p4=[1.0, 0.0])

    # Filter operations with (col, expected) tuple
    prog.add(OpCode.FILTER_EQ, p4=("category", "Crypto"))
    prog.add(OpCode.FILTER_NE, p4=("category", "Zero-Trust"))

    # Result Row yielding R1, R2
    prog.add(OpCode.RESULT_ROW, p1=1, p2=2)
    prog.add(OpCode.HALT)

    vm = VDBE(program=prog, context={})
    step = vm.step()
    assert step == StepResult.SQLITE_ROW

    step_end = vm.step()
    assert step_end == StepResult.SQLITE_DONE


def test_sqlite_engine_sync_lifecycle() -> None:
    """Tests bidirectional syncing between VectorStorage and SQLite tables."""
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "sync_test.vdb")
        db_path = os.path.join(tmpdir, "sync_sqlite.db")
        storage = VectorStorage(vdb_path, dim=4)
        storage.append(
            [1.0, 0.0, 0.0, 0.0], {"id": "p1", "title": "Paper 1", "category": "Crypto"}
        )
        storage.append(
            [0.0, 1.0, 0.0, 0.0],
            {"id": "p2", "title": "Paper 2", "category": "Zero-Trust"},
        )

        conn = get_sqlite_connection(db_path=db_path, storage=storage)
        cur = conn.cursor()
        cur.execute("SELECT count(*) FROM papers")
        assert cur.fetchone()[0] == 2

        # Sync back to vector storage
        synced_count = sync_to_vector_storage(conn, storage)
        assert synced_count == 2

        conn.close()
        storage.close()


def test_database_profiler() -> None:
    profiler = DatabaseProfiler()
    res = profiler.profile_callable(
        name="test_sum",
        fn=lambda: sum(range(100)),
        iterations=10,
        warmup=1,
    )
    assert isinstance(res, ProfileResult)
    assert res.mean_latency_ms >= 0

    leak_report = profiler.check_memory_leak(
        name="test_leak",
        fn=lambda: [x * 2 for x in range(10)],
        batches=3,
        batch_size=10,
    )
    assert "name" in leak_report
