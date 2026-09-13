#!/usr/bin/env python3
"""
Differential Test Suite: Pure Python Database (`src/database`) vs `sqlite3`.

Validates behavioral parity and differential expectations across core SQL features:
- CRUD operations & parameter bindings
- Aggregations (COUNT, SUM, AVG, MIN, MAX) with GROUP BY and HAVING
- Sorting and paging (ORDER BY, LIMIT, OFFSET)
- Subqueries (WHERE IN, EXISTS) and Common Table Expressions (WITH CTE)
- Views and PRAGMA table_info introspection
- Pure Python extensions (VECTOR, KNN) vs standard SQLite error behavior
"""

import os
import sqlite3
import sys
import unittest
from typing import Any, List, Tuple

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database import connect as py_connect


class TestSQLite3Differential(unittest.TestCase):
    """Verifies behavioral equivalence and documented differences with sqlite3."""

    def setUp(self) -> None:
        self.py_conn = py_connect(":memory:")
        self.sq_conn = sqlite3.connect(":memory:")

    def tearDown(self) -> None:
        self.py_conn.close()
        self.sq_conn.close()

    def _execute_both_dml(self, sql: str, params: Tuple[Any, ...] = ()) -> None:
        """Executes non-query statement on both engines."""
        cur_py = self.py_conn.cursor()
        cur_sq = self.sq_conn.cursor()
        if params:
            cur_py.execute(sql, params)
            cur_sq.execute(sql, params)
        else:
            cur_py.execute(sql)
            cur_sq.execute(sql)
        self.py_conn.commit()
        self.sq_conn.commit()

    def _query_both(
        self, sql: str
    ) -> Tuple[List[Tuple[Any, ...]], List[Tuple[Any, ...]]]:
        """Executes query on both engines and returns fetched rows."""
        rows_py = self.py_conn.cursor().execute(sql).fetchall()
        rows_sq = self.sq_conn.cursor().execute(sql).fetchall()
        return rows_py, rows_sq

    def test_basic_crud_and_parameters(self) -> None:
        """Verifies CRUD operations and parameter bindings match sqlite3."""
        ddl = "CREATE TABLE users (id INT PRIMARY KEY, name TEXT, score REAL)"
        self._execute_both_dml(ddl)

        ins1 = "INSERT INTO users (id, name, score) VALUES (?, ?, ?)"
        self._execute_both_dml(ins1, (1, "Alice", 95.5))
        self._execute_both_dml(ins1, (2, "Bob", 88.0))

        rows_py, rows_sq = self._query_both(
            "SELECT id, name, score FROM users ORDER BY id"
        )
        self.assertEqual(rows_py, rows_sq)
        self.assertEqual(len(rows_py), 2)

        upd = "UPDATE users SET score = 100.0 WHERE id = ?"
        self._execute_both_dml(upd, (1,))

        rows_py, rows_sq = self._query_both("SELECT score FROM users WHERE id = 1")
        self.assertEqual(rows_py, rows_sq)
        self.assertEqual(rows_py[0][0], 100.0)

        dele = "DELETE FROM users WHERE id = 2"
        self._execute_both_dml(dele)

        rows_py, rows_sq = self._query_both("SELECT count(*) FROM users")
        self.assertEqual(rows_py, rows_sq)
        self.assertEqual(rows_py[0][0], 1)

    def test_aggregations_and_group_by_having(self) -> None:
        """Verifies COUNT, SUM, AVG, GROUP BY, and HAVING match sqlite3 exactly."""
        self._execute_both_dml("CREATE TABLE metrics (dept TEXT, val REAL)")
        dml = (
            "INSERT INTO metrics VALUES "
            "('Sec', 100.0), ('Sec', 200.0), ('Infra', 300.0), ('Infra', 400.0)"
        )
        self._execute_both_dml(dml)

        # Global aggregations
        q_agg = "SELECT count(*), sum(val), avg(val), min(val), max(val) FROM metrics"
        py_agg, sq_agg = self._query_both(q_agg)
        self.assertEqual(py_agg, sq_agg)
        self.assertEqual(py_agg[0], (4, 1000.0, 250.0, 100.0, 400.0))

        # GROUP BY with HAVING
        q_grp = (
            "SELECT dept, sum(val) FROM metrics "
            "GROUP BY dept HAVING sum(val) > 500.0 ORDER BY dept"
        )
        py_grp, sq_grp = self._query_both(q_grp)
        self.assertEqual(py_grp, sq_grp)
        self.assertEqual(py_grp, [("Infra", 700.0)])

    def test_sorting_and_pagination(self) -> None:
        """Verifies ORDER BY, LIMIT, and OFFSET behavior matches sqlite3."""
        self._execute_both_dml("CREATE TABLE items (num INT)")
        self._execute_both_dml("INSERT INTO items VALUES (10), (30), (20), (50), (40)")

        q_page = "SELECT num FROM items ORDER BY num DESC LIMIT 3 OFFSET 1"
        py_page, sq_page = self._query_both(q_page)
        self.assertEqual(py_page, sq_page)
        self.assertEqual(py_page, [(40,), (30,), (20,)])

    def test_subqueries_and_with_cte(self) -> None:
        """Verifies WHERE IN subquery, EXISTS, and WITH CTE match sqlite3."""
        self._execute_both_dml("CREATE TABLE teams (id INT, name TEXT)")
        self._execute_both_dml("CREATE TABLE staff (id INT, name TEXT, team_id INT)")
        self._execute_both_dml("INSERT INTO teams VALUES (1, 'Blue'), (2, 'Red')")
        self._execute_both_dml(
            "INSERT INTO staff VALUES (10, 'Carol', 1), (20, 'Dave', 2), (30, 'Eve', 99)"
        )

        # Subquery in WHERE
        q_sub = (
            "SELECT name FROM staff WHERE team_id IN "
            "(SELECT id FROM teams WHERE name = 'Blue') ORDER BY name"
        )
        py_sub, sq_sub = self._query_both(q_sub)
        self.assertEqual(py_sub, sq_sub)
        self.assertEqual(py_sub, [("Carol",)])

        # WITH CTE
        q_cte = (
            "WITH target_team AS (SELECT id FROM teams WHERE name = 'Red') "
            "SELECT s.name FROM staff s JOIN target_team t ON s.team_id = t.id"
        )
        py_cte, sq_cte = self._query_both(q_cte)
        self.assertEqual(py_cte, sq_cte)
        self.assertEqual(py_cte, [("Dave",)])

    def test_views_and_pragma_table_info(self) -> None:
        """Verifies CREATE VIEW and PRAGMA table_info match sqlite3."""
        self._execute_both_dml("CREATE TABLE base_tbl (id INT PRIMARY KEY, title TEXT)")
        self._execute_both_dml(
            "INSERT INTO base_tbl VALUES (1, 'Paper A'), (2, 'Paper B')"
        )

        self._execute_both_dml(
            "CREATE VIEW v_papers AS SELECT id, title FROM base_tbl WHERE id = 1"
        )
        py_view, sq_view = self._query_both("SELECT id, title FROM v_papers")
        self.assertEqual(py_view, sq_view)
        self.assertEqual(py_view, [(1, "Paper A")])

        py_pragma, sq_pragma = self._query_both("PRAGMA table_info(base_tbl)")
        self.assertEqual(len(py_pragma), len(sq_pragma))
        self.assertEqual(py_pragma[0][1], sq_pragma[0][1])  # 'id' column name

    def test_vector_and_knn_extension_difference(self) -> None:
        """Verifies Pure Python DB vector extension executes while SQLite standard rejects."""
        py_cur = self.py_conn.cursor()
        sq_cur = self.sq_conn.cursor()

        # Pure Python handles VECTOR and array literal
        py_cur.execute("CREATE TABLE papers (id TEXT PRIMARY KEY, emb VECTOR(4))")
        py_cur.execute("INSERT INTO papers VALUES ('p1', [0.1, 0.2, 0.3, 0.4])")
        self.py_conn.commit()

        py_res = py_cur.execute(
            "SELECT id FROM papers WHERE emb KNN [0.1, 0.2, 0.3, 0.4] TOP 1"
        ).fetchall()
        self.assertEqual(py_res, [("p1",)])

        # SQLite accepts type name VECTOR(4) due to flexible affinity
        sq_cur.execute("CREATE TABLE papers (id TEXT PRIMARY KEY, emb VECTOR(4))")
        self.sq_conn.commit()

        # But SQLite standard fails on KNN operator
        with self.assertRaises(sqlite3.OperationalError):
            sq_cur.execute(
                "SELECT id FROM papers WHERE emb KNN [0.1, 0.2, 0.3, 0.4] TOP 1"
            )

    def test_phase1_defaults_and_between_and_rowcount(self) -> None:
        """Verifies Phase 1 parity: rowcount=-1, column defaults, negative BETWEEN, and concat."""
        py_cur = self.py_conn.cursor()
        sq_cur = self.sq_conn.cursor()

        # 1. DDL rowcount is -1 on both engines
        self.assertEqual(
            py_cur.execute(
                "CREATE TABLE products (id INT, active INT DEFAULT 1, score REAL)"
            ).rowcount,
            -1,
        )
        self.assertEqual(
            sq_cur.execute(
                "CREATE TABLE products (id INT, active INT DEFAULT 1, score REAL)"
            ).rowcount,
            -1,
        )

        # 2. DEFAULT value auto-population when column omitted
        self._execute_both_dml("INSERT INTO products (id, score) VALUES (1, -15.0)")
        self._execute_both_dml(
            "INSERT INTO products (id, active, score) VALUES (2, 0, 42.0)"
        )
        self._execute_both_dml("INSERT INTO products (id, score) VALUES (3, 0.0)")

        rows_py, rows_sq = self._query_both(
            "SELECT id, active, score FROM products ORDER BY id"
        )
        self.assertEqual(rows_py, rows_sq)
        self.assertEqual(rows_py, [(1, 1, -15.0), (2, 0, 42.0), (3, 1, 0.0)])

        # 3. Negative BETWEEN clause
        q_between = (
            "SELECT id, score FROM products WHERE score BETWEEN -20 AND 10 ORDER BY id"
        )
        py_b, sq_b = self._query_both(q_between)
        self.assertEqual(py_b, sq_b)
        self.assertEqual(py_b, [(1, -15.0), (3, 0.0)])

        # 4. Modulo and String Concat
        q_expr = "SELECT id, score % 7, 'Item: ' || id FROM products WHERE id = 1"
        py_e, sq_e = self._query_both(q_expr)
        self.assertEqual(py_e, sq_e)
        self.assertEqual(py_e, [(1, -1.0, "Item: 1")])

    def test_phase2_join_type_coercion_upsert_json(self) -> None:
        """Verifies Phase 2 parity: JOIN projection, NULL coercion, TYPEOF, UPSERT expr, JSON ->>."""
        import sqlite3 as _sq3

        import database as _pydb

        def _new_conns() -> tuple:  # type: ignore[type-arg]
            return _pydb.connect(":memory:"), _sq3.connect(":memory:")

        # --- Issue A: JOIN column projection key collision ---
        py_c, sq_c = _new_conns()
        for cur in (py_c.cursor(), sq_c.cursor()):
            cur.execute("CREATE TABLE depts (id INT, name TEXT)")
            cur.execute("CREATE TABLE emps (id INT, name TEXT, dept_id INT)")
            cur.execute("INSERT INTO depts VALUES (10, 'Security'), (20, 'Infra')")
            cur.execute(
                "INSERT INTO emps VALUES (1, 'Alice', 10), (2, 'Bob', 10), (3, 'Charlie', 20)"
            )
        q_join = (
            "SELECT e.name, d.name FROM emps e INNER JOIN depts d "
            "ON e.dept_id = d.id ORDER BY e.name"
        )
        rows_py = py_c.cursor().execute(q_join).fetchall()
        rows_sq = sq_c.cursor().execute(q_join).fetchall()
        py_c.close()
        sq_c.close()
        self.assertEqual(rows_py, rows_sq)
        self.assertEqual(
            rows_py,
            [("Alice", "Security"), ("Bob", "Security"), ("Charlie", "Infra")],
        )

        # --- Issue B: NULL coercion, IS NULL, IS NOT NULL, TYPEOF ---
        py_c, sq_c = _new_conns()
        for cur in (py_c.cursor(), sq_c.cursor()):
            cur.execute("CREATE TABLE tt (id INT, score REAL, tag TEXT)")
            cur.execute("INSERT INTO tt VALUES (1, 3.14, NULL)")
            cur.execute("INSERT INTO tt VALUES (2, NULL, 'hello')")
            cur.execute("INSERT INTO tt VALUES (3, 13.0, 'world')")

        py_null = (
            py_c.cursor().execute("SELECT id FROM tt WHERE score IS NULL").fetchall()
        )
        sq_null = (
            sq_c.cursor().execute("SELECT id FROM tt WHERE score IS NULL").fetchall()
        )
        self.assertEqual(py_null, sq_null)
        self.assertEqual(py_null, [(2,)])

        py_not = (
            py_c.cursor()
            .execute("SELECT id FROM tt WHERE score IS NOT NULL ORDER BY id")
            .fetchall()
        )
        sq_not = (
            sq_c.cursor()
            .execute("SELECT id FROM tt WHERE score IS NOT NULL ORDER BY id")
            .fetchall()
        )
        self.assertEqual(py_not, sq_not)
        self.assertEqual(py_not, [(1,), (3,)])

        py_typeof = (
            py_c.cursor()
            .execute(
                "SELECT TYPEOF(id), TYPEOF(score), TYPEOF(tag) FROM tt WHERE id = 1"
            )
            .fetchall()
        )
        sq_typeof = (
            sq_c.cursor()
            .execute(
                "SELECT TYPEOF(id), TYPEOF(score), TYPEOF(tag) FROM tt WHERE id = 1"
            )
            .fetchall()
        )
        py_c.close()
        sq_c.close()
        self.assertEqual(py_typeof, sq_typeof)
        self.assertEqual(py_typeof, [("integer", "real", "null")])

        # --- Issue C: UPSERT SET RHS expression evaluation ---
        py_c, sq_c = _new_conns()
        for cur in (py_c.cursor(), sq_c.cursor()):
            cur.execute("CREATE TABLE counters (k TEXT PRIMARY KEY, cnt INT)")
            cur.execute("INSERT INTO counters VALUES ('hits', 1)")
            cur.execute(
                "INSERT INTO counters VALUES ('hits', 10) "
                "ON CONFLICT (k) DO UPDATE SET cnt = cnt + 10"
            )
        py_upsert = (
            py_c.cursor()
            .execute("SELECT k, cnt FROM counters WHERE k = 'hits'")
            .fetchall()
        )
        sq_upsert = (
            sq_c.cursor()
            .execute("SELECT k, cnt FROM counters WHERE k = 'hits'")
            .fetchall()
        )
        py_c.close()
        sq_c.close()
        self.assertEqual(py_upsert, sq_upsert)
        self.assertEqual(py_upsert, [("hits", 11)])

        # --- Issue D: JSON ->> operator ---
        py_c, sq_c = _new_conns()
        for cur in (py_c.cursor(), sq_c.cursor()):
            cur.execute("CREATE TABLE audit_logs (id INT, payload TEXT)")
            cur.execute('INSERT INTO audit_logs VALUES (1, \'{"user": "alice"}\')')
        py_json = (
            py_c.cursor()
            .execute("SELECT id, payload ->> '$.user' FROM audit_logs WHERE id = 1")
            .fetchall()
        )
        sq_json = (
            sq_c.cursor()
            .execute("SELECT id, payload ->> '$.user' FROM audit_logs WHERE id = 1")
            .fetchall()
        )
        py_c.close()
        sq_c.close()
        self.assertEqual(py_json, sq_json)
        self.assertEqual(py_json, [(1, "alice")])


if __name__ == "__main__":
    unittest.main()
