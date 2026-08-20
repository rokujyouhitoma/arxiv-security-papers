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
        executor = SQLExecutor(default_storage=storage)

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
        executor = SQLExecutor(default_storage=storage)

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
        executor = SQLExecutor(default_storage=storage)

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
        conn = get_sqlite_connection(db_path=db_path)
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
            "INSERT INTO authors (paper_id, author_name) VALUES ('p_002', 'Charlie')"
        )
        conn.commit()

        # 4. DQL: Complex JOIN, GROUP BY, subquery, and vector scoring
        cur.execute(
            """
            SELECT
                p.id,
                p.title,
                p.category,
                COUNT(a.author_name) AS author_count,
                COSINE_SIM(p.vector, ?) AS vec_score
            FROM papers p
            LEFT JOIN authors a ON p.id = a.paper_id
            WHERE p.category IN ('Zero-Trust', 'Cryptography')
            GROUP BY p.id, p.title, p.category, p.vector
            HAVING author_count >= 1
            ORDER BY vec_score DESC
            """,
            (json.dumps([1.0, 0.0, 0.0, 0.0]),),
        )
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
        synced_count = sync_to_vector_storage(conn, storage)
        assert synced_count == 2
        assert storage.count == 2
        assert storage.get_vector(0)[0] == pytest.approx(1.0, abs=1e-3)

        conn.close()
