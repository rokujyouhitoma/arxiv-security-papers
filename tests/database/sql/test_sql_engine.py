#!/usr/bin/env python3
"""
Unit tests for Pure Python SQL Engine (DDL, DQL, DML, DCL, TCL),
PEP 249 DB-API 2.0 Driver, and Python standard `sqlite3` Interoperability Bridge.
"""

import json
import os
import sqlite3
import sys
import tempfile

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

import pytest

from database import (
    DCLPermissionDeniedError,
    SQLExecutor,
    VectorStorage,
    attach_to_sqlite,
    connect,
)


def test_ddl_and_dml_and_dql_lifecycle():
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "test_sql.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        executor = SQLExecutor(default_storage=storage, default_table_name="papers")

        # 1. DML: INSERT
        res_ins1 = executor.execute(
            "INSERT INTO papers (id, title, category, vector) "
            "VALUES ('p1', 'Zero Trust Architecture', 'Zero-Trust', [1.0, 0.0, 0.0, 0.0])"
        )
        assert res_ins1["status"] == "ok"
        assert res_ins1["id"] == "p1"

        res_ins2 = executor.execute(
            "INSERT INTO papers (id, title, category, vector) "
            "VALUES ('p2', 'Quantum Key Distribution', 'Cryptography', [0.0, 1.0, 0.0, 0.0])"
        )
        assert res_ins2["status"] == "ok"

        # 2. DDL: CREATE INDEX
        res_idx = executor.execute(
            "CREATE INDEX hnsw_idx ON papers (vector) USING HNSW"
        )
        assert res_idx["status"] == "ok"

        # 3. DQL: SELECT with KNN
        res_sel_knn = executor.execute(
            "SELECT id, title, score FROM papers WHERE KNN(vector, [1.0, 0.0, 0.0, 0.0], 2)"
        )
        assert res_sel_knn["status"] == "ok"
        assert res_sel_knn["count"] == 2
        # Exact match p1 should be ranked 1st
        assert res_sel_knn["rows"][0]["id"] == "p1"
        assert res_sel_knn["rows"][0]["score"] == pytest.approx(1.0, abs=1e-3)

        # 4. DQL: SELECT with WHERE filter
        res_sel_cat = executor.execute(
            "SELECT id, title FROM papers WHERE category = 'Cryptography'"
        )
        assert res_sel_cat["status"] == "ok"
        assert res_sel_cat["count"] == 1
        assert res_sel_cat["rows"][0]["id"] == "p2"

        # 5. DML: UPDATE
        res_upd = executor.execute(
            "UPDATE papers SET title = 'Advanced Zero Trust' WHERE id = 'p1'"
        )
        assert res_upd["status"] == "ok"
        assert res_upd["updated_count"] == 1

        # Check updated
        res_sel_check = executor.execute("SELECT id, title FROM papers WHERE id = 'p1'")
        assert res_sel_check["rows"][0]["title"] == "Advanced Zero Trust"

        # 6. DML: DELETE
        res_del = executor.execute("DELETE FROM papers WHERE id = 'p2'")
        assert res_del["status"] == "ok"
        assert res_del["deleted_count"] == 1

        # Verify deleted
        res_after_del = executor.execute("SELECT id FROM papers")
        assert res_after_del["count"] == 1


def test_dcl_rbac_access_control():
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "dcl_test.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        executor = SQLExecutor(default_storage=storage, default_table_name="papers")

        # Guest role tries to insert without permission -> should fail
        with pytest.raises(DCLPermissionDeniedError):
            executor.execute(
                "INSERT INTO papers (id, title) VALUES ('g1', 'Guest Paper')",
                role="guest",
            )

        # Admin grants INSERT permission on papers to guest
        res_grant = executor.execute("GRANT INSERT ON papers TO guest", role="admin")
        assert res_grant["status"] == "ok"

        # Now guest role can insert
        res_guest_ins = executor.execute(
            "INSERT INTO papers (id, title) VALUES ('g1', 'Guest Paper')",
            role="guest",
        )
        assert res_guest_ins["status"] == "ok"

        # Admin revokes INSERT permission from guest
        res_revoke = executor.execute(
            "REVOKE INSERT ON papers FROM guest", role="admin"
        )
        assert res_revoke["status"] == "ok"

        # Guest role blocked again
        with pytest.raises(DCLPermissionDeniedError):
            executor.execute(
                "INSERT INTO papers (id, title) VALUES ('g2', 'Guest Paper 2')",
                role="guest",
            )


def test_tcl_transaction_management():
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "tcl_test.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        executor = SQLExecutor(default_storage=storage, default_table_name="papers")

        # 1. Start transaction
        res_begin = executor.execute("BEGIN TRANSACTION")
        assert res_begin["status"] == "ok"

        # 2. Stage mutation
        executor.execute("INSERT INTO papers (id, title) VALUES ('tx1', 'Tx Paper')")

        # 3. Rollback
        res_rb = executor.execute("ROLLBACK")
        assert res_rb["status"] == "ok"

        # 4. Commit flow
        executor.execute("BEGIN")
        executor.execute(
            "INSERT INTO papers (id, title) VALUES ('tx2', 'Committed Paper')"
        )
        res_commit = executor.execute("COMMIT")
        assert res_commit["status"] == "ok"


def test_pep249_db_api_driver_interface():
    """
    Verifies that standard PEP 249 DB-API 2.0
    (connect, cursor, execute, fetchall, params) works seamlessly.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "dbapi_test.vdb")
        conn = connect(vdb_path, dim=4)

        with conn.cursor() as cur:
            # 1. Insert with positional parameter binding (?)
            cur.execute(
                "INSERT INTO papers (id, title, category, vector) VALUES (?, ?, ?, ?)",
                [
                    "doc_1",
                    "Secure Multiparty Computation",
                    "Cryptography",
                    [0.0, 0.0, 1.0, 0.0],
                ],
            )

            # 2. Query with positional parameter binding (?)
            cur.execute(
                "SELECT id, title, category FROM papers WHERE category = ?",
                ["Cryptography"],
            )
            rows = cur.fetchall()
            assert len(rows) == 1
            assert rows[0][0] == "doc_1"
            assert rows[0][1] == "Secure Multiparty Computation"

            # 3. Check cursor description (column names)
            assert cur.description is not None
            col_names = [d[0] for d in cur.description]
            assert col_names == ["id", "title", "category"]

            # 4. KNN Query via PEP 249 Cursor
            cur.execute(
                "SELECT id, title, score FROM papers WHERE KNN(vector, ?, 1)",
                [[0.0, 0.0, 1.0, 0.0]],
            )
            row = cur.fetchone()
            assert row is not None
            assert row[0] == "doc_1"
            assert row[2] == pytest.approx(1.0, abs=1e-3)

        conn.commit()
        conn.close()


def test_python_standard_sqlite3_client_bridge():
    """
    Verifies that Python standard library `sqlite3` client can connect and query with custom KNN UDF.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "sqlite_bridge.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        storage.write_all(
            vectors=[[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0]],
            metadata=[
                {"id": "s1", "title": "Zero Trust Paper", "category": "Zero-Trust"},
                {"id": "s2", "title": "Quantum Paper", "category": "Quantum"},
            ],
        )

        # Connect with standard Python sqlite3 client!
        sqlite_conn = sqlite3.connect(":memory:")
        attach_to_sqlite(sqlite_conn, storage=storage, table_name="papers")

        cur = sqlite_conn.cursor()
        # Query standard SQLite table with custom COSINE_SIM function
        query_vec_json = "[1.0, 0.0, 0.0, 0.0]"
        cur.execute(
            """
            SELECT id, title, COSINE_SIM(vector, ?) AS similarity
            FROM papers
            ORDER BY similarity DESC
            LIMIT 1
            """,
            (query_vec_json,),
        )
        row = cur.fetchone()
        assert row is not None
        assert row[0] == "s1"
        assert row[1] == "Zero Trust Paper"
        assert row[2] == pytest.approx(1.0, abs=1e-3)

        sqlite_conn.close()


def test_100_percent_standard_sqlite3_client_compatibility():
    """
    Verifies 100% compatibility with Python's standard `sqlite3` client.
    Tests complex standard SQL (DDL, DQL, DML, TCL, aggregations, JOINs, subqueries, EMBED UDF)
    and bidirectional synchronization with binary VectorStorage (.vdb).
    """
    from database import get_sqlite_connection, sync_to_vector_storage

    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "native_sqlite.db")
        vdb_path = os.path.join(tmpdir, "native_vector.vdb")

        storage = VectorStorage(vdb_path, dim=4)

        # 1. Connect via Python standard sqlite3 client
        conn = get_sqlite_connection(db_path=db_path, table_name="papers")
        cur = conn.cursor()

        # 2. DDL: Create related table (authors)
        cur.execute("""
            CREATE TABLE authors (
                paper_id TEXT,
                author_name TEXT,
                FOREIGN KEY (paper_id) REFERENCES papers(id)
            )
            """)

        # 3. DML: Insert into papers using standard SQLite client
        cur.execute(
            """
            INSERT INTO papers (id, title, description, category, vector, metadata)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                "p_001",
                "Advanced Zero Trust",
                "Network zero-trust architecture",
                "Zero-Trust",
                json.dumps([1.0, 0.0, 0.0, 0.0]),
                json.dumps({"id": "p_001", "title": "Advanced Zero Trust"}),
            ),
        )

        cur.execute(
            """
            INSERT INTO papers (id, title, description, category, vector, metadata)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                "p_002",
                "Post-Quantum Cryptography",
                "Lattice-based cryptography",
                "Cryptography",
                json.dumps([0.0, 1.0, 0.0, 0.0]),
                json.dumps({"id": "p_002", "title": "Post-Quantum Cryptography"}),
            ),
        )

        cur.execute(
            "INSERT INTO authors (paper_id, author_name) VALUES ('p_001', 'Alice')"
        )
        cur.execute(
            "INSERT INTO authors (paper_id, author_name) VALUES ('p_001', 'Bob')"
        )
        cur.execute(
            "INSERT INTO authors (paper_id, author_name) VALUES ('p_002', 'Carol')"
        )
        conn.commit()

        # 4. Complex Query: JOIN + Aggregate + Vector Similarity UDF (KNN_SCORE)
        cur.execute("""
            SELECT
                p.id,
                p.title,
                COUNT(a.author_name) AS author_count,
                KNN_SCORE(p.vector, '[1.0, 0.0, 0.0, 0.0]') AS vec_score
            FROM papers p
            JOIN authors a ON p.id = a.paper_id
            GROUP BY p.id, p.title
            ORDER BY vec_score DESC
            """)
        results = [dict(row) for row in cur.fetchall()]
        assert len(results) == 2
        assert results[0]["id"] == "p_001"
        assert results[0]["author_count"] == 2
        assert results[0]["vec_score"] == pytest.approx(1.0, abs=1e-3)

        # 5. Test automatic EMBED UDF inside SQL
        cur.execute("SELECT EMBED('Zero Trust Security') AS embedded_vec")
        embed_row = cur.fetchone()
        assert embed_row is not None
        embedded_list = json.loads(embed_row["embedded_vec"])
        assert len(embedded_list) == 128

        # 6. Bidirectional synchronization: Sync SQLite records to binary .vdb
        synced_count = sync_to_vector_storage(conn, storage, table_name="papers")
        assert synced_count == 2
        assert storage.count == 2
        assert storage.get_vector(0)[0] == pytest.approx(1.0, abs=1e-3)

        conn.close()


def test_group_by_and_having_pure_python_executor():
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "test_group_by.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        executor = SQLExecutor(default_storage=storage, default_table_name="papers")

        # Insert test records
        items = [
            ("p1", "Zero Trust 1", "Zero-Trust", 10.0),
            ("p2", "Zero Trust 2", "Zero-Trust", 20.0),
            ("p3", "Zero Trust 3", "Zero-Trust", 30.0),
            ("p4", "Crypto 1", "Cryptography", 15.0),
            ("p5", "Network 1", "Network", 5.0),
        ]
        for pid, title, cat, score in items:
            executor.execute(
                f"INSERT INTO papers (id, title, category, score) "
                f"VALUES ('{pid}', '{title}', '{cat}', {score})"
            )

        # 1. Simple GROUP BY
        res1 = executor.execute(
            "SELECT category, COUNT(*) FROM papers GROUP BY category"
        )
        assert res1["status"] == "ok"
        assert res1["count"] == 3
        cat_counts = {r["category"]: r["COUNT(*)"] for r in res1["rows"]}
        assert cat_counts["Zero-Trust"] == 3
        assert cat_counts["Cryptography"] == 1
        assert cat_counts["Network"] == 1

        # 2. GROUP BY + HAVING (COUNT(*) > 1)
        res2 = executor.execute(
            "SELECT category, COUNT(*) FROM papers GROUP BY category HAVING COUNT(*) > 1"
        )
        assert res2["status"] == "ok"
        assert res2["count"] == 1
        assert res2["rows"][0]["category"] == "Zero-Trust"
        assert res2["rows"][0]["COUNT(*)"] == 3

        # 3. Aggregation functions: SUM, AVG, MIN, MAX
        res3 = executor.execute(
            "SELECT category, SUM(score), AVG(score), MIN(score), MAX(score) "
            "FROM papers WHERE category = 'Zero-Trust' GROUP BY category"
        )
        assert res3["status"] == "ok"
        row = res3["rows"][0]
        assert row["SUM(score)"] == 60.0
        assert row["AVG(score)"] == 20.0
        assert row["MIN(score)"] == 10.0
        assert row["MAX(score)"] == 30.0

        # 4. Complex pipeline: WHERE + GROUP BY + HAVING + ORDER BY + LIMIT
        res4 = executor.execute(
            "SELECT category, COUNT(*) FROM papers "
            "WHERE score >= 10.0 "
            "GROUP BY category "
            "HAVING COUNT(*) >= 1 "
            "ORDER BY category ASC LIMIT 2"
        )
        assert res4["status"] == "ok"
        assert res4["count"] == 2


def test_dql_phase1_distinct_offset_between_null_glob():
    """
    Tests Phase 1 DQL Foundations:
    DISTINCT, OFFSET (LIMIT n OFFSET m and LIMIT m, n), BETWEEN, IS [NOT] NULL, GLOB, LIKE ESCAPE.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "test_p1.vdb")
        executor = SQLExecutor()
        create_sql = (
            "CREATE TABLE records (id VARCHAR PRIMARY KEY, tag VARCHAR, score FLOAT, note TEXT) "
            f"USING binary_vdb LOCATION '{db_path}'"
        )
        executor.execute(create_sql)
        executor.execute(
            "INSERT INTO records (id, tag, score, note) VALUES ('r1', 'alpha', 10.0, 'first sample')"
        )
        executor.execute(
            "INSERT INTO records (id, tag, score, note) VALUES ('r2', 'alpha', 20.0, 'second sample')"
        )
        executor.execute(
            "INSERT INTO records (id, tag, score, note) VALUES ('r3', 'beta', 30.0, 'third sample')"
        )
        executor.execute(
            "INSERT INTO records (id, tag, score, note) VALUES ('r4', 'beta', 40.0, 'special 100% discount')"
        )
        executor.execute(
            "INSERT INTO records (id, tag, score, note) VALUES ('r5', 'gamma', 50.0, '')"
        )

        # 1. DISTINCT
        res_distinct = executor.execute("SELECT DISTINCT tag FROM records")
        assert res_distinct["status"] == "ok"
        assert res_distinct["count"] == 3
        tags = {r["tag"] for r in res_distinct["rows"]}
        assert tags == {"alpha", "beta", "gamma"}

        # 2. OFFSET (LIMIT n OFFSET m)
        res_offset1 = executor.execute(
            "SELECT id, tag FROM records ORDER BY id ASC LIMIT 2 OFFSET 1"
        )
        assert res_offset1["status"] == "ok"
        assert res_offset1["count"] == 2
        assert [r["id"] for r in res_offset1["rows"]] == ["r2", "r3"]

        # 3. OFFSET comma syntax (LIMIT offset, count)
        res_offset2 = executor.execute(
            "SELECT id, tag FROM records ORDER BY id ASC LIMIT 2, 2"
        )
        assert res_offset2["status"] == "ok"
        assert res_offset2["count"] == 2
        assert [r["id"] for r in res_offset2["rows"]] == ["r3", "r4"]

        # 4. BETWEEN
        res_between = executor.execute(
            "SELECT id, score FROM records WHERE score BETWEEN 20.0 AND 40.0 ORDER BY id ASC"
        )
        assert res_between["status"] == "ok"
        assert [r["id"] for r in res_between["rows"]] == ["r2", "r3", "r4"]

        # 5. NOT BETWEEN
        res_not_between = executor.execute(
            "SELECT id, score FROM records WHERE score NOT BETWEEN 20.0 AND 40.0 ORDER BY id ASC"
        )
        assert res_not_between["status"] == "ok"
        assert [r["id"] for r in res_not_between["rows"]] == ["r1", "r5"]

        # 6. IS NULL / IS NOT NULL
        res_null = executor.execute("SELECT id FROM records WHERE note IS NULL")
        assert res_null["status"] == "ok"
        assert res_null["count"] == 1
        assert res_null["rows"][0]["id"] == "r5"

        res_not_null = executor.execute("SELECT id FROM records WHERE note IS NOT NULL")
        assert res_not_null["status"] == "ok"
        assert res_not_null["count"] == 4

        # 7. GLOB
        res_glob = executor.execute("SELECT id FROM records WHERE tag GLOB 'al*'")
        assert res_glob["status"] == "ok"
        assert res_glob["count"] == 2

        # 8. LIKE with ESCAPE
        res_like_esc = executor.execute(
            r"SELECT id FROM records WHERE note LIKE '%100\%%' ESCAPE '\'"
        )
        assert res_like_esc["status"] == "ok"
        assert res_like_esc["count"] == 1
        assert res_like_esc["rows"][0]["id"] == "r4"


def test_dml_phase2_multi_insert_upsert_returning():
    """
    Tests Phase 2 DML extensions:
    Multi-row INSERT, INSERT SELECT, UPSERT (DO UPDATE / DO NOTHING), RETURNING, UPDATE/DELETE ORDER BY LIMIT.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "test_p2.vdb")
        executor = SQLExecutor()
        create_sql = (
            "CREATE TABLE items (id VARCHAR PRIMARY KEY, category VARCHAR, qty INT) "
            f"USING binary_vdb LOCATION '{db_path}'"
        )
        executor.execute(create_sql)

        # 1. Multi-row INSERT with RETURNING
        res_multi = executor.execute(
            "INSERT INTO items (id, category, qty) VALUES "
            "('i1', 'fruit', 10), ('i2', 'fruit', 20), ('i3', 'veggie', 30) RETURNING *"
        )
        assert res_multi["status"] == "ok"
        assert res_multi["inserted_count"] == 3
        assert len(res_multi["rows"]) == 3
        assert [r["id"] for r in res_multi["rows"]] == ["i1", "i2", "i3"]

        # 2. UPSERT ON CONFLICT DO NOTHING
        res_do_nothing = executor.execute(
            "INSERT INTO items (id, category, qty) VALUES ('i1', 'fruit', 99) "
            "ON CONFLICT(id) DO NOTHING"
        )
        assert res_do_nothing["status"] == "ok"
        assert res_do_nothing["inserted_count"] == 0

        # Verify i1 qty remains 10
        sel_i1 = executor.execute("SELECT qty FROM items WHERE id = 'i1'")
        assert sel_i1["rows"][0]["qty"] == 10

        # 3. UPSERT ON CONFLICT DO UPDATE
        res_do_update = executor.execute(
            "INSERT INTO items (id, category, qty) VALUES ('i1', 'fruit', 99) "
            "ON CONFLICT(id) DO UPDATE SET qty = 99 RETURNING id, qty"
        )
        assert res_do_update["status"] == "ok"
        assert res_do_update["inserted_count"] == 1
        assert res_do_update["rows"][0]["qty"] == 99

        # 4. INSERT INTO ... SELECT ...
        res_ins_sel = executor.execute(
            "INSERT INTO items (id, category, qty) "
            "SELECT 'i4', category, 40 FROM items WHERE id = 'i2'"
        )
        assert res_ins_sel["status"] == "ok"
        assert res_ins_sel["inserted_count"] == 1

        sel_i4 = executor.execute("SELECT id, category, qty FROM items WHERE id = 'i4'")
        assert sel_i4["count"] == 1
        assert sel_i4["rows"][0]["category"] == "fruit"
        assert sel_i4["rows"][0]["qty"] == 40

        # 5. UPDATE ... ORDER BY ... LIMIT ... RETURNING
        res_upd_lim = executor.execute(
            "UPDATE items SET qty = 500 WHERE category = 'fruit' "
            "ORDER BY qty DESC LIMIT 1 RETURNING id, qty"
        )
        assert res_upd_lim["status"] == "ok"
        assert res_upd_lim["updated_count"] == 1
        assert res_upd_lim["rows"][0]["id"] == "i1"
        assert res_upd_lim["rows"][0]["qty"] == 500

        # 6. DELETE ... ORDER BY ... LIMIT ... RETURNING
        res_del_lim = executor.execute(
            "DELETE FROM items WHERE category = 'fruit' "
            "ORDER BY qty ASC LIMIT 1 RETURNING id"
        )
        assert res_del_lim["status"] == "ok"
        assert res_del_lim["deleted_count"] == 1
        assert res_del_lim["rows"][0]["id"] == "i2"


def test_ddl_phase3_alter_table_view_lifecycle():
    """
    Tests Phase 3 DDL Lifecycle & VIEW:
    ALTER TABLE (RENAME TO, ADD COLUMN, RENAME COLUMN, DROP COLUMN),
    CREATE/DROP INDEX, REINDEX, CREATE/DROP VIEW.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "test_p3.vdb")
        executor = SQLExecutor()
        executor.execute(
            f"CREATE TABLE users (id VARCHAR PRIMARY KEY, name VARCHAR, age INT) USING binary_vdb LOCATION '{db_path}'"
        )
        executor.execute("INSERT INTO users (id, name, age) VALUES ('u1', 'Alice', 25)")
        executor.execute("INSERT INTO users (id, name, age) VALUES ('u2', 'Bob', 30)")

        # 1. ALTER TABLE ADD COLUMN with DEFAULT
        res_add = executor.execute(
            "ALTER TABLE users ADD COLUMN status VARCHAR DEFAULT 'active'"
        )
        assert res_add["status"] == "ok"
        rows = executor.execute("SELECT id, name, status FROM users ORDER BY id ASC")[
            "rows"
        ]
        assert rows[0]["status"] == "active"
        assert rows[1]["status"] == "active"

        # 2. ALTER TABLE RENAME COLUMN
        res_ren_col = executor.execute(
            "ALTER TABLE users RENAME COLUMN name TO full_name"
        )
        assert res_ren_col["status"] == "ok"
        rows_ren = executor.execute(
            "SELECT id, full_name, status FROM users ORDER BY id ASC"
        )["rows"]
        assert rows_ren[0]["full_name"] == "Alice"

        # 3. ALTER TABLE DROP COLUMN
        res_drop_col = executor.execute("ALTER TABLE users DROP COLUMN age")
        assert res_drop_col["status"] == "ok"
        rows_drop = executor.execute("SELECT * FROM users ORDER BY id ASC")["rows"]
        assert "age" not in rows_drop[0]

        # 4. ALTER TABLE RENAME TO
        res_ren_tbl = executor.execute("ALTER TABLE users RENAME TO members")
        assert res_ren_tbl["status"] == "ok"
        rows_tbl = executor.execute(
            "SELECT id, full_name FROM members ORDER BY id ASC"
        )["rows"]
        assert len(rows_tbl) == 2

        # 5. CREATE INDEX, REINDEX, DROP INDEX
        res_idx = executor.execute(
            "CREATE INDEX idx_members_name ON members(full_name) USING BTREE"
        )
        assert res_idx["status"] == "ok"

        res_reindex = executor.execute("REINDEX members")
        assert res_reindex["status"] == "ok"
        assert res_reindex["reindexed_count"] >= 1

        res_drop_idx = executor.execute("DROP INDEX idx_members_name")
        assert res_drop_idx["status"] == "ok"
        assert res_drop_idx["dropped"] is True

        res_drop_idx_exists = executor.execute("DROP INDEX IF EXISTS idx_members_name")
        assert res_drop_idx_exists["status"] == "ok"
        assert res_drop_idx_exists["dropped"] is False

        # 6. CREATE VIEW and query through view
        res_view = executor.execute(
            "CREATE VIEW v_active_members AS SELECT id, full_name FROM members WHERE status = 'active'"
        )
        assert res_view["status"] == "ok"

        res_view_sel = executor.execute(
            "SELECT id, full_name FROM v_active_members ORDER BY id ASC"
        )
        assert res_view_sel["status"] == "ok"
        assert res_view_sel["count"] == 2
        assert res_view_sel["rows"][0]["full_name"] == "Alice"

        # 7. DROP VIEW
        res_drop_v = executor.execute("DROP VIEW v_active_members")
        assert res_drop_v["status"] == "ok"
        assert res_drop_v["dropped"] is True

        res_drop_v_exists = executor.execute("DROP VIEW IF EXISTS v_active_members")
        assert res_drop_v_exists["status"] == "ok"
        assert res_drop_v_exists["dropped"] is False


def test_phase4_builtin_functions_and_case() -> None:
    """Verify Phase 4 built-in functions (String, Math, Control, Date, JSON) and CASE expressions."""
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "test_p4.vdb")
        executor = SQLExecutor()

        # Setup tables
        executor.execute(
            "CREATE TABLE students ("
            "id INT PRIMARY KEY, name VARCHAR, score FLOAT, role VARCHAR, meta VARCHAR"
            f") USING binary_vdb LOCATION '{db_path}'"
        )
        executor.execute(
            "INSERT INTO students (id, name, score, role, meta) "
            "VALUES (1, 'Alice', 95.5, 'admin', '{\"city\": \"Tokyo\", \"active\": true}')"
        )
        executor.execute(
            "INSERT INTO students (id, name, score, role, meta) "
            "VALUES (2, 'Bob', 72.0, 'member', '{\"city\": \"Osaka\", \"active\": false}')"
        )
        executor.execute(
            "INSERT INTO students (id, name, score, role, meta) "
            "VALUES (3, 'Charlie', 48.0, 'guest', '{\"city\": \"Nagoya\", \"active\": true}')"
        )

        # 1. CASE WHEN expressions
        res_case = executor.execute(
            "SELECT id, "
            "CASE WHEN score >= 90 THEN 'Grade_A' WHEN score >= 70 THEN 'Grade_B' ELSE 'Grade_C' END AS grade, "
            "CASE role WHEN 'admin' THEN 'SuperUser' ELSE 'NormalUser' END AS role_label "
            "FROM students ORDER BY id ASC"
        )
        assert res_case["status"] == "ok"
        assert res_case["rows"][0]["grade"] == "Grade_A"
        assert res_case["rows"][0]["role_label"] == "SuperUser"
        assert res_case["rows"][1]["grade"] == "Grade_B"
        assert res_case["rows"][1]["role_label"] == "NormalUser"
        assert res_case["rows"][2]["grade"] == "Grade_C"

        # 2. String functions
        res_str = executor.execute(
            "SELECT id, UPPER(name) AS up, LOWER(name) AS low, LENGTH(name) AS len, "
            "SUBSTR(name, 1, 3) AS sub, REPLACE(name, 'ice', 'icia') AS rep, INSTR(name, 'li') AS inst "
            "FROM students WHERE id = 1"
        )
        assert res_str["status"] == "ok"
        assert res_str["rows"][0]["up"] == "ALICE"
        assert res_str["rows"][0]["low"] == "alice"
        assert res_str["rows"][0]["len"] == 5
        assert res_str["rows"][0]["sub"] == "Ali"
        assert res_str["rows"][0]["rep"] == "Alicia"
        assert res_str["rows"][0]["inst"] == 2

        # 3. Math functions
        res_math = executor.execute(
            "SELECT ROUND(score, 0) AS rnd, CEIL(score) AS c, FLOOR(score) AS f, "
            "ABS(-42) AS a, POWER(2, 3) AS p, SQRT(16) AS s, SIGN(-5) AS sgn "
            "FROM students WHERE id = 1"
        )
        assert res_math["status"] == "ok"
        assert res_math["rows"][0]["rnd"] == 96.0
        assert res_math["rows"][0]["c"] == 96
        assert res_math["rows"][0]["f"] == 95
        assert res_math["rows"][0]["a"] == 42
        assert res_math["rows"][0]["p"] == 8.0
        assert res_math["rows"][0]["s"] == 4.0
        assert res_math["rows"][0]["sgn"] == -1

        # 4. Control functions
        res_ctrl = executor.execute(
            "SELECT COALESCE(NULL, NULL, 'first_val') AS c_val, "
            "NULLIF(10, 10) AS n_null, NULLIF(10, 20) AS n_val, "
            "IIF(score > 90, 'excellent', 'regular') AS eval, "
            "IFNULL(NULL, 'fallback') AS ifn, "
            "TYPEOF(name) AS t_name, TYPEOF(score) AS t_score "
            "FROM students WHERE id = 1"
        )
        assert res_ctrl["status"] == "ok"
        assert res_ctrl["rows"][0]["c_val"] == "first_val"
        assert res_ctrl["rows"][0]["n_null"] is None
        assert res_ctrl["rows"][0]["n_val"] == 10
        assert res_ctrl["rows"][0]["eval"] == "excellent"
        assert res_ctrl["rows"][0]["ifn"] == "fallback"
        assert res_ctrl["rows"][0]["t_name"] == "text"
        assert res_ctrl["rows"][0]["t_score"] == "real"

        # 5. Date/Time functions
        res_dt = executor.execute(
            "SELECT DATE('2026-09-12 14:30:00') AS d, "
            "TIME('2026-09-12 14:30:00') AS t, "
            "DATETIME('2026-09-12 14:30:00') AS dt, "
            "STRFTIME('%Y/%m', '2026-09-12 14:30:00') AS fmt, "
            "UNIXEPOCH('1970-01-01 00:00:00') AS ep "
            "FROM students WHERE id = 1"
        )
        assert res_dt["status"] == "ok"
        assert res_dt["rows"][0]["d"] == "2026-09-12"
        assert res_dt["rows"][0]["t"] == "14:30:00"
        assert res_dt["rows"][0]["dt"] == "2026-09-12 14:30:00"
        assert res_dt["rows"][0]["fmt"] == "2026/09"
        assert res_dt["rows"][0]["ep"] == 0

        # 6. JSON functions
        res_json = executor.execute(
            "SELECT JSON_EXTRACT(meta, '$.city') AS city, "
            "JSON_EXTRACT(meta, '$.active') AS active, "
            "JSON_VALID(meta) AS valid, "
            "JSON_ARRAY(1, 2, 'three') AS arr, "
            "JSON_OBJECT('status', 'ok') AS obj "
            "FROM students WHERE id = 1"
        )
        assert res_json["status"] == "ok"
        assert res_json["rows"][0]["city"] == "Tokyo"
        assert res_json["rows"][0]["active"] is True
        assert res_json["rows"][0]["valid"] == 1
        assert res_json["rows"][0]["arr"] == '[1, 2, "three"]'
        assert res_json["rows"][0]["obj"] == '{"status": "ok"}'

        # 7. Aggregate GROUP_CONCAT / STRING_AGG
        res_gc = executor.execute(
            "SELECT GROUP_CONCAT(name, '; ') AS all_names FROM students"
        )
        assert res_gc["status"] == "ok"
        assert res_gc["rows"][0]["all_names"] == "Alice; Bob; Charlie"


def test_phase5_set_operations_subqueries_and_window_functions() -> None:
    """Verify Phase 5 set operations (INTERSECT, EXCEPT), subqueries, and window functions."""
    with tempfile.TemporaryDirectory() as tmpdir:
        db1 = os.path.join(tmpdir, "p5_t1.vdb")
        db2 = os.path.join(tmpdir, "p5_t2.vdb")
        executor = SQLExecutor()

        executor.execute(
            f"CREATE TABLE employees (id INT PRIMARY KEY, name VARCHAR, dept VARCHAR, score INT) "
            f"USING binary_vdb LOCATION '{db1}'"
        )
        executor.execute(
            f"CREATE TABLE managers (id INT PRIMARY KEY, title VARCHAR) USING binary_vdb LOCATION '{db2}'"
        )

        executor.execute(
            "INSERT INTO employees (id, name, dept, score) VALUES (1, 'Alice', 'ENG', 100)"
        )
        executor.execute(
            "INSERT INTO employees (id, name, dept, score) VALUES (2, 'Bob', 'ENG', 90)"
        )
        executor.execute(
            "INSERT INTO employees (id, name, dept, score) VALUES (3, 'Charlie', 'ENG', 90)"
        )
        executor.execute(
            "INSERT INTO employees (id, name, dept, score) VALUES (4, 'Dave', 'SALES', 80)"
        )
        executor.execute(
            "INSERT INTO employees (id, name, dept, score) VALUES (5, 'Eve', 'SALES', 95)"
        )

        executor.execute("INSERT INTO managers (id, title) VALUES (1, 'Lead Engineer')")
        executor.execute("INSERT INTO managers (id, title) VALUES (4, 'Sales Lead')")
        executor.execute("INSERT INTO managers (id, title) VALUES (99, 'CEO')")

        # 1. Set operations: INTERSECT, EXCEPT, UNION
        res_intersect = executor.execute(
            "SELECT id FROM employees INTERSECT SELECT id FROM managers ORDER BY id ASC"
        )
        assert res_intersect["status"] == "ok"
        assert [r["id"] for r in res_intersect["rows"]] == [1, 4]

        res_except = executor.execute(
            "SELECT id FROM employees EXCEPT SELECT id FROM managers ORDER BY id ASC"
        )
        assert res_except["status"] == "ok"
        assert [r["id"] for r in res_except["rows"]] == [2, 3, 5]

        res_union = executor.execute(
            "SELECT id FROM employees UNION SELECT id FROM managers ORDER BY id ASC"
        )
        assert res_union["status"] == "ok"
        assert [r["id"] for r in res_union["rows"]] == [1, 2, 3, 4, 5, 99]

        # 2. Subqueries: IN, NOT IN, EXISTS
        res_in = executor.execute(
            "SELECT id, name FROM employees WHERE id IN (SELECT id FROM managers) ORDER BY id ASC"
        )
        assert res_in["status"] == "ok"
        assert [r["id"] for r in res_in["rows"]] == [1, 4]

        res_not_in = executor.execute(
            "SELECT id, name FROM employees WHERE id NOT IN (SELECT id FROM managers) ORDER BY id ASC"
        )
        assert res_not_in["status"] == "ok"
        assert [r["id"] for r in res_not_in["rows"]] == [2, 3, 5]

        res_exists = executor.execute(
            "SELECT id, name FROM employees WHERE EXISTS (SELECT id FROM managers WHERE id = 99) ORDER BY id ASC"
        )
        assert res_exists["status"] == "ok"
        assert res_exists["count"] == 5

        # 3. Window functions: ROW_NUMBER, RANK, DENSE_RANK, SUM OVER
        res_win = executor.execute(
            "SELECT id, name, dept, score, "
            "ROW_NUMBER() OVER (PARTITION BY dept ORDER BY score DESC) AS rn, "
            "RANK() OVER (PARTITION BY dept ORDER BY score DESC) AS rk, "
            "DENSE_RANK() OVER (PARTITION BY dept ORDER BY score DESC) AS drk, "
            "SUM(score) OVER (PARTITION BY dept ORDER BY score ASC) AS running_sum "
            "FROM employees ORDER BY dept ASC, rn ASC"
        )
        assert res_win["status"] == "ok"
        eng_rows = [r for r in res_win["rows"] if r["dept"] == "ENG"]
        assert eng_rows[0]["name"] == "Alice"
        assert eng_rows[0]["rn"] == 1
        assert eng_rows[0]["rk"] == 1
        assert eng_rows[0]["drk"] == 1

        assert eng_rows[1]["rn"] == 2
        assert eng_rows[1]["rk"] == 2
        assert eng_rows[1]["drk"] == 2

        assert eng_rows[2]["rn"] == 3
        assert eng_rows[2]["rk"] == 2  # Same score 90 as Bob
        assert eng_rows[2]["drk"] == 2
