#!/usr/bin/env python3
"""
Pure Python Database (`src/database`) vs `sqlite3` Differential Evaluator.

Executes a comprehensive 75-case comparative SQL suite across 12 functional categories,
classifies differences (MATCH, EQUIVALENT, BEHAVIORAL_DIFF, EXTENSION, SQLITE_ONLY),
and displays real-time execution logs with summary metrics and markdown tables.

Usage:
    python3 scripts/compare_sqlite3_differential.py
    make differential_audit
"""

import os
import sqlite3
import sys
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence, Tuple

# Ensure repository src is in sys.path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC_DIR = os.path.join(REPO_ROOT, "src")
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

from database import connect as py_connect  # noqa: E402


@dataclass
class TestCaseResult:
    """Stores the comparative outcome of a single SQL test case."""

    category: str
    name: str
    sql: str
    py_success: bool
    py_output: Any
    py_error: Optional[str]
    sq_success: bool
    sq_output: Any
    sq_error: Optional[str]
    classification: str
    notes: str


def _normalize_scalar(val: Any) -> Any:
    if isinstance(val, float) and val.is_integer():
        return int(val)
    return val


def _normalize_value(val: Any) -> Any:
    """Normalizes compound and scalar values for semantic equivalence checking."""
    if isinstance(val, (list, tuple)):
        return [_normalize_value(x) for x in val]
    if isinstance(val, dict):
        return {k: _normalize_value(v) for k, v in val.items()}
    return _normalize_scalar(val)


def _classify_success(py_res: Any, sq_res: Any) -> Tuple[str, str]:
    """Classifies when both database engines succeed."""
    norm_py = _normalize_value(py_res)
    norm_sq = _normalize_value(sq_res)
    if norm_py == norm_sq:
        if type(py_res) is type(sq_res):
            return "MATCH", "Exact match in values and types"
        type_str = f"{type(py_res).__name__} vs {type(sq_res).__name__}"
        return "EQUIVALENT", f"Semantic equivalence with container nuance ({type_str})"
    return (
        "BEHAVIORAL_DIFF",
        f"Different outputs: Py={py_res!r} vs Sq={sq_res!r}",
    )


def _classify_extension(py_ok: bool, sq_ok: bool) -> Optional[Tuple[str, str]]:
    if py_ok and not sq_ok:
        return "EXTENSION", "Pure Python DB extension (e.g. VECTOR/KNN/NoSQL)"
    if not py_ok and sq_ok:
        return "SQLITE_EXCLUSIVE", "SQLite-exclusive behavior not in Pure Python"
    return None


def _classify_single_success(
    py_ok: bool, py_err: Optional[str], sq_err: Optional[str]
) -> Tuple[str, str]:
    if py_ok:
        return "PY_ONLY_SUCCESS", f"Pure Python succeeded, SQLite failed: {sq_err}"
    return "SQ_ONLY_SUCCESS", f"SQLite succeeded, Pure Python failed: {py_err}"


def _classify_non_extension(
    py_ok: bool,
    py_res: Any,
    py_err: Optional[str],
    sq_ok: bool,
    sq_res: Any,
    sq_err: Optional[str],
) -> Tuple[str, str]:
    if py_ok and sq_ok:
        return _classify_success(py_res, sq_res)
    if py_ok or sq_ok:
        return _classify_single_success(py_ok, py_err, sq_err)
    return "BOTH_ERROR", f"Both rejected: Py={py_err}, Sq={sq_err}"


def _classify_outcome(
    py_ok: bool,
    py_res: Any,
    py_err: Optional[str],
    sq_ok: bool,
    sq_res: Any,
    sq_err: Optional[str],
    is_extension: bool = False,
) -> Tuple[str, str]:
    """Determines comparative classification category."""
    if is_extension:
        ext = _classify_extension(py_ok, sq_ok)
        if ext is not None:
            return ext
    return _classify_non_extension(py_ok, py_res, py_err, sq_ok, sq_res, sq_err)


class DifferentialHarness:
    """Harness executing identical SQL test suites against Pure Python DB and sqlite3."""

    def __init__(self) -> None:
        self.results: List[TestCaseResult] = []

    def reset_connections(self) -> Tuple[Any, sqlite3.Connection]:
        """Creates fresh in-memory database connections for both engines."""
        py_conn = py_connect(":memory:")
        sq_conn = sqlite3.connect(":memory:")
        return py_conn, sq_conn

    def _exec_py(
        self,
        conn: Any,
        sql: str,
        params: Optional[Sequence[Any]],
        is_query: bool,
    ) -> Tuple[bool, Any, Optional[str]]:
        try:
            cur = conn.cursor()
            if params:
                cur.execute(sql, params)
            else:
                cur.execute(sql)
            if is_query:
                return True, cur.fetchall(), None
            conn.commit()
            rc = getattr(cur, "rowcount", 0)
            return True, f"rowcount={rc}", None
        except Exception as e:
            return False, None, f"{type(e).__name__}: {str(e)}"

    def _exec_sq(
        self,
        conn: sqlite3.Connection,
        sql: str,
        params: Optional[Sequence[Any]],
        is_query: bool,
    ) -> Tuple[bool, Any, Optional[str]]:
        try:
            cur = conn.cursor()
            if params:
                cur.execute(sql, params)
            else:
                cur.execute(sql)
            if is_query:
                return True, cur.fetchall(), None
            conn.commit()
            return True, f"rowcount={cur.rowcount}", None
        except Exception as e:
            return False, None, f"{type(e).__name__}: {str(e)}"

    def run_case(
        self,
        py_conn: Any,
        sq_conn: sqlite3.Connection,
        category: str,
        name: str,
        sql: str,
        params: Optional[Sequence[Any]] = None,
        is_query: bool = True,
        is_extension: bool = False,
    ) -> TestCaseResult:
        """Executes a single test case across both engines and records difference."""
        py_ok, py_res, py_err = self._exec_py(py_conn, sql, params, is_query)
        sq_ok, sq_res, sq_err = self._exec_sq(sq_conn, sql, params, is_query)

        classification, notes = _classify_outcome(
            py_ok, py_res, py_err, sq_ok, sq_res, sq_err, is_extension
        )

        display_sql = sql if not params else f"{sql} with {params}"
        res = TestCaseResult(
            category=category,
            name=name,
            sql=display_sql,
            py_success=py_ok,
            py_output=py_res,
            py_error=py_err,
            sq_success=sq_ok,
            sq_output=sq_res,
            sq_error=sq_err,
            classification=classification,
            notes=notes,
        )
        self.results.append(res)
        return res


def _run_ddl_crud_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "1. DDL & Basic DML"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Create Basic Table",
        "CREATE TABLE users (id INT PRIMARY KEY, name TEXT NOT NULL, score REAL, active INT DEFAULT 1)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Insert Single Row",
        "INSERT INTO users (id, name, score) VALUES (1, 'Alice', 95.5)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Insert Parameterized",
        "INSERT INTO users (id, name, score, active) VALUES (?, ?, ?, ?)",
        params=(2, "Bob", 88.0, 0),
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Insert Multi-Row VALUES",
        "INSERT INTO users (id, name, score) VALUES (3, 'Charlie', 72.3), (4, 'Diana', 91.0)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Select All Rows",
        "SELECT id, name, score, active FROM users ORDER BY id",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Update with WHERE",
        "UPDATE users SET score = score + 5.0 WHERE id = 1",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Verify Update",
        "SELECT id, name, score FROM users WHERE id = 1",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Delete with WHERE",
        "DELETE FROM users WHERE id = 2",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Verify Delete",
        "SELECT id, name FROM users ORDER BY id",
        is_query=True,
    )


def _run_types_null_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "2. Types & NULL Handling"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Create Table with Types",
        "CREATE TABLE items (id INT, val TEXT, num REAL, flag INT)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Insert NULL and values",
        "INSERT INTO items VALUES (1, NULL, 3.14, 1), (2, 'two', NULL, 0), (3, '3', 3, NULL)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Select IS NULL",
        "SELECT id FROM items WHERE val IS NULL",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Select IS NOT NULL",
        "SELECT id FROM items WHERE num IS NOT NULL ORDER BY id",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Arithmetic with NULL",
        "SELECT id, num + 10 FROM items ORDER BY id",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "TYPEOF builtin function",
        "SELECT typeof(id), typeof(val), typeof(num) FROM items WHERE id = 1",
        is_query=True,
    )


def _run_operators_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "3. Operators & Functions"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Setup Table",
        "CREATE TABLE sample (id INT, txt TEXT, val INT)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Populate Table",
        "INSERT INTO sample VALUES (1, '  Hello World  ', -15), (2, 'Security Testing', 42), (3, 'arXiv Papers', 0)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Arithmetic Operators",
        "SELECT id, val * 2, val + 10, val % 7 FROM sample ORDER BY id",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "BETWEEN Operator",
        "SELECT id, val FROM sample WHERE val BETWEEN -20 AND 10 ORDER BY id",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "IN List Operator",
        "SELECT id, val FROM sample WHERE id IN (1, 3) ORDER BY id",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "LIKE Pattern Matching",
        "SELECT id, txt FROM sample WHERE txt LIKE '%Security%'",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "String Concatenation ||",
        "SELECT id || ': ' || txt FROM sample WHERE id = 2",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "ABS and ROUND",
        "SELECT id, abs(val), round(val / 2.0, 1) FROM sample ORDER BY id",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "LOWER, UPPER, LENGTH, TRIM",
        "SELECT length(txt), lower(trim(txt)), upper(trim(txt)) FROM sample WHERE id = 1",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "COALESCE and NULLIF",
        "SELECT coalesce(null, null, 'third'), nullif(val, 0) FROM sample WHERE id = 3",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "CASE Expression",
        "SELECT id, CASE WHEN val < 0 THEN 'NEG' WHEN val = 0 THEN 'ZERO' ELSE 'POS' END FROM sample ORDER BY id",
        is_query=True,
    )


def _run_aggregations_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "4. Aggregations & Grouping"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Setup Sales Table",
        "CREATE TABLE sales (id INT, dept TEXT, amount REAL, category TEXT)",
        is_query=False,
    )
    dml = (
        "INSERT INTO sales VALUES "
        "(1, 'Engineering', 1000.0, 'Hardware'), "
        "(2, 'Engineering', 1500.0, 'Software'), "
        "(3, 'Research', 2000.0, 'Hardware'), "
        "(4, 'Research', 3000.0, 'Software'), "
        "(5, 'Sales', 800.0, 'Hardware')"
    )
    h.run_case(py_c, sq_c, cat, "Populate Sales", dml, is_query=False)
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Basic Aggregates",
        "SELECT count(*), count(dept), sum(amount), avg(amount), min(amount), max(amount) FROM sales",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "GROUP BY Single Column",
        "SELECT dept, count(*), sum(amount) FROM sales GROUP BY dept ORDER BY dept",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "GROUP BY with HAVING",
        "SELECT dept, sum(amount) FROM sales GROUP BY dept HAVING sum(amount) > 2000 ORDER BY dept",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "GROUP BY Multiple Columns",
        "SELECT dept, category, sum(amount) FROM sales GROUP BY dept, category ORDER BY dept, category",
        is_query=True,
    )


def _run_paging_set_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "5. Paging & Set Operations"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Setup Numbers Table",
        "CREATE TABLE nums (val INT)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Populate Numbers",
        "INSERT INTO nums VALUES (10), (30), (20), (50), (40)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "ORDER BY DESC with LIMIT & OFFSET",
        "SELECT val FROM nums ORDER BY val DESC LIMIT 3 OFFSET 1",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "UNION (Deduplicating)",
        "SELECT 1 AS x UNION SELECT 2 UNION SELECT 1 ORDER BY x",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "UNION ALL",
        "SELECT 1 AS x UNION ALL SELECT 2 UNION ALL SELECT 1",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "INTERSECT",
        "SELECT 1 AS x UNION SELECT 2 INTERSECT SELECT 2 AS x UNION SELECT 3",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "EXCEPT",
        "SELECT 1 AS x UNION SELECT 2 UNION SELECT 3 EXCEPT SELECT 2",
        is_query=True,
    )


def _run_joins_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "6. Joins"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Setup Departments",
        "CREATE TABLE departments (id INT PRIMARY KEY, name TEXT)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Setup Employees",
        "CREATE TABLE employees (id INT PRIMARY KEY, name TEXT, dept_id INT)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Populate Departments",
        "INSERT INTO departments VALUES (10, 'Security'), (20, 'Infra'), (30, 'Design')",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Populate Employees",
        "INSERT INTO employees VALUES (1, 'Alice', 10), (2, 'Bob', 10), (3, 'Charlie', 20), (4, 'David', 99)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "INNER JOIN with ON",
        "SELECT e.name, d.name FROM employees e INNER JOIN departments d ON e.dept_id = d.id ORDER BY e.name",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "LEFT JOIN with NULL",
        "SELECT e.name, d.name FROM employees e LEFT JOIN departments d ON e.dept_id = d.id ORDER BY e.name",
        is_query=True,
    )


def _run_subqueries_cte_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "7. Subqueries & CTEs"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Setup Departments",
        "CREATE TABLE departments (id INT PRIMARY KEY, name TEXT)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Setup Employees",
        "CREATE TABLE employees (id INT PRIMARY KEY, name TEXT, dept_id INT)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Populate Departments",
        "INSERT INTO departments VALUES (10, 'Security'), (20, 'Infra')",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Populate Employees",
        "INSERT INTO employees VALUES (1, 'Alice', 10), (2, 'Bob', 10), (3, 'Charlie', 20)",
        is_query=False,
    )
    q_sub = (
        "SELECT name FROM employees WHERE dept_id IN "
        "(SELECT id FROM departments WHERE name = 'Security') ORDER BY name"
    )
    h.run_case(py_c, sq_c, cat, "Subquery in WHERE (IN)", q_sub, is_query=True)

    q_exists = (
        "SELECT d.name FROM departments d WHERE EXISTS "
        "(SELECT 1 FROM employees e WHERE e.dept_id = d.id) ORDER BY d.name"
    )
    h.run_case(py_c, sq_c, cat, "EXISTS Subquery", q_exists, is_query=True)

    q_derived = (
        "SELECT sub.dept_id, count(*) FROM "
        "(SELECT * FROM employees WHERE dept_id < 50) sub "
        "GROUP BY sub.dept_id ORDER BY sub.dept_id"
    )
    h.run_case(py_c, sq_c, cat, "Derived Table in FROM", q_derived, is_query=True)

    q_cte = (
        "WITH sec_dept AS (SELECT id, name FROM departments WHERE name = 'Security') "
        "SELECT e.name FROM employees e JOIN sec_dept s ON e.dept_id = s.id ORDER BY e.name"
    )
    h.run_case(py_c, sq_c, cat, "Common Table Expression (WITH)", q_cte, is_query=True)


def _run_constraints_tcl_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "8. Constraints & Transactions"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Create Table with Constraints",
        "CREATE TABLE unique_test (id INT PRIMARY KEY, email TEXT UNIQUE NOT NULL)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Insert Valid Row",
        "INSERT INTO unique_test VALUES (1, 'alice@example.com')",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Duplicate Primary Key Violation",
        "INSERT INTO unique_test VALUES (1, 'another@example.com')",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "NOT NULL Violation",
        "INSERT INTO unique_test VALUES (2, NULL)",
        is_query=False,
    )
    h.run_case(py_c, sq_c, cat, "BEGIN Transaction", "BEGIN", is_query=False)
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Insert in Transaction",
        "INSERT INTO unique_test VALUES (3, 'charlie@example.com')",
        is_query=False,
    )
    h.run_case(py_c, sq_c, cat, "ROLLBACK Transaction", "ROLLBACK", is_query=False)
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Verify Rollback",
        "SELECT id, email FROM unique_test WHERE id = 3",
        is_query=True,
    )


def _run_upsert_returning_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "9. UPSERT & RETURNING"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Setup Upsert Table",
        "CREATE TABLE counters (k TEXT PRIMARY KEY, cnt INT)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Insert Initial",
        "INSERT INTO counters VALUES ('hits', 1)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "ON CONFLICT DO UPDATE",
        "INSERT INTO counters VALUES ('hits', 10) ON CONFLICT (k) DO UPDATE SET cnt = cnt + 10",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Verify Upsert Result",
        "SELECT k, cnt FROM counters WHERE k = 'hits'",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "INSERT RETURNING",
        "INSERT INTO counters VALUES ('views', 50) RETURNING k, cnt",
        is_query=True,
    )


def _run_views_introspection_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "10. Views & Introspection"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Setup Base for View",
        "CREATE TABLE raw_data (id INT, label TEXT, val REAL)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Insert Data for View",
        "INSERT INTO raw_data VALUES (1, 'A', 10.5), (2, 'B', 20.5)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "CREATE VIEW",
        "CREATE VIEW v_summary AS SELECT id, label, val * 2 AS doubled FROM raw_data",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Query VIEW",
        "SELECT id, label, doubled FROM v_summary ORDER BY id",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "PRAGMA table_info",
        "PRAGMA table_info(raw_data)",
        is_query=True,
    )


def _run_extensions_suite(h: DifferentialHarness) -> None:
    py_c, sq_c = h.reset_connections()
    cat = "11. Extensions & Differentiators"
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Create Table with VECTOR type",
        "CREATE TABLE papers (id TEXT PRIMARY KEY, title TEXT, embedding VECTOR(4))",
        is_query=False,
        is_extension=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Insert Vector Literal",
        "INSERT INTO papers VALUES ('p1', 'AI Security', [0.1, 0.2, 0.3, 0.4])",
        is_query=False,
        is_extension=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "KNN Vector Similarity Query",
        "SELECT id, title FROM papers WHERE embedding KNN [0.1, 0.2, 0.3, 0.4] TOP 1",
        is_query=True,
        is_extension=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "JSON Create Table",
        "CREATE TABLE audit_logs (id INT, payload TEXT)",
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "JSON Insert",
        'INSERT INTO audit_logs VALUES (1, \'{"user": "alice", "action": "login"}\')',
        is_query=False,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "JSON Extract Function",
        "SELECT id, json_extract(payload, '$.user') FROM audit_logs WHERE id = 1",
        is_query=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "JSON Arrow Operator ->>",
        "SELECT id, payload ->> '$.user' FROM audit_logs WHERE id = 1",
        is_query=True,
        is_extension=True,
    )
    h.run_case(
        py_c,
        sq_c,
        cat,
        "Standalone VALUES Query",
        "VALUES (1, 'first'), (2, 'second')",
        is_query=True,
    )


def execute_full_suite() -> List[TestCaseResult]:
    """Runs all functional suites and returns complete test case results."""
    harness = DifferentialHarness()
    _run_ddl_crud_suite(harness)
    _run_types_null_suite(harness)
    _run_operators_suite(harness)
    _run_aggregations_suite(harness)
    _run_paging_set_suite(harness)
    _run_joins_suite(harness)
    _run_subqueries_cte_suite(harness)
    _run_constraints_tcl_suite(harness)
    _run_upsert_returning_suite(harness)
    _run_views_introspection_suite(harness)
    _run_extensions_suite(harness)
    return harness.results


def _format_row_cell(is_ok: bool, out: Any, err: Optional[str]) -> str:
    val_str = f"OK: {out!r}" if is_ok else f"ERR: {err}"
    if len(val_str) > 30:
        return val_str[:27] + "..."
    return val_str


def _print_category_table(category: str, items: List[TestCaseResult]) -> None:
    print(f"\n### {category}")
    print(
        "| Test Case | Classification | Pure Python Output | SQLite3 Output | Notes |"
    )
    print("| :--- | :---: | :--- | :--- | :--- |")
    for r in items:
        py_str = _format_row_cell(r.py_success, r.py_output, r.py_error)
        sq_str = _format_row_cell(r.sq_success, r.sq_output, r.sq_error)
        notes_str = r.notes.replace("|", "/")
        print(
            f"| **{r.name}** | `{r.classification}` | `{py_str}` | `{sq_str}` | {notes_str} |"
        )


def _count_classifications(
    results: List[TestCaseResult],
) -> Dict[str, int]:
    counts: Dict[str, int] = {}
    for r in results:
        counts[r.classification] = counts.get(r.classification, 0) + 1
    return counts


def _print_metrics(results: List[TestCaseResult]) -> None:
    total = len(results)
    c = _count_classifications(results)
    matches = c.get("MATCH", 0) + c.get("EQUIVALENT", 0)
    diffs = c.get("BEHAVIORAL_DIFF", 0)
    exts = c.get("EXTENSION", 0) + c.get("PY_ONLY_SUCCESS", 0)
    sq_only = c.get("SQLITE_ONLY", 0) + c.get("SQ_ONLY_SUCCESS", 0)
    both_err = c.get("BOTH_ERROR", 0)

    print("\n" + "=" * 66)
    print("SUMMARY OF DIFFERENTIAL COMPARISON: Pure Python DB vs sqlite3")
    print("=" * 66)
    print(f"Total Evaluated Test Cases: {total}")
    print(f"  - MATCH / EQUIVALENT:     {matches:2d} ({matches/total*100:5.1f}%)")
    print(f"  - BEHAVIORAL DIFFERENCES: {diffs:2d} ({diffs/total*100:5.1f}%)")
    print(f"  - PURE PYTHON EXTENSIONS: {exts:2d} ({exts/total*100:5.1f}%)")
    print(f"  - SQLITE-ONLY SUCCESS:    {sq_only:2d} ({sq_only/total*100:5.1f}%)")
    print(f"  - BOTH REJECTED (ERRORS): {both_err:2d} ({both_err/total*100:5.1f}%)")
    print("=" * 66 + "\n")


def print_summary(results: List[TestCaseResult]) -> None:
    """Prints categorized summary and markdown formatted tables."""
    _print_metrics(results)
    categories = sorted(list(set(r.category for r in results)))
    for c in categories:
        cat_results = [r for r in results if r.category == c]
        _print_category_table(c, cat_results)


if __name__ == "__main__":
    test_results = execute_full_suite()
    print_summary(test_results)
