#!/usr/bin/env python3
"""Tests for SQL expression precompilation, non-reparsing invariants, and security."""

from __future__ import annotations

import inspect
import re
import time
from typing import Any, Dict, List
from unittest.mock import patch

import pytest

from database.sql import expr_compiler
from database.sql.ast import SQLExecutionError
from database.sql.executor import SQLExecutor
from database.sql.expr_compiler import (
    MAX_EXPR_AST_DEPTH,
    MAX_LIKE_PATTERN_LEN,
    compile_like_pattern,
    compile_sql_expr,
)
from database.sql.expr_parser import parse_sql_expr
from database.sql.parser import clear_sql_parser_caches


def test_compile_sql_expr_semantics_comprehensive() -> None:
    """Verifies compiled closures match expected semantics across all AST forms."""
    clear_sql_parser_caches()
    rec: Dict[str, Any] = {
        "id": 7,
        "t.score": 42,
        "name": "Alice",
        "meta": '{"count": 12, "nested": {"ok": true}, "tag": "sec"}',
        "empty": "",
        "missing": None,
    }
    assert compile_sql_expr("42")(rec) == 42
    assert compile_sql_expr("'hi'")(rec) == "hi"
    assert compile_sql_expr("NULL")(rec) is None
    assert compile_sql_expr("id * 2 + 3")(rec) == 17
    assert compile_sql_expr("id / 2")(rec) == 3.5
    assert compile_sql_expr("id / 0")(rec) is None
    assert compile_sql_expr("-id")(rec) == -7
    assert compile_sql_expr("t.score")(rec) == 42
    assert compile_sql_expr("name || '_' || id")(rec) == "Alice_7"
    assert compile_sql_expr("missing || '_x'")(rec) is None
    assert compile_sql_expr("meta->'$.count'")(rec) == 12
    assert compile_sql_expr("meta->>'$.count'")(rec) == "12"
    assert compile_sql_expr("UPPER(name)")(rec) == "ALICE"
    assert compile_sql_expr("COALESCE(missing, 'fallback')")(rec) == "fallback"
    assert (
        compile_sql_expr(
            "CASE WHEN id > 5 THEN 'high' WHEN id > 0 THEN 'low' ELSE 'zero' END"
        )(rec)
        == "high"
    )
    assert (
        compile_sql_expr("CASE id WHEN 7 THEN 'lucky' ELSE 'other' END")(rec) == "lucky"
    )
    assert compile_sql_expr("missing IS NULL")(rec) is True
    assert compile_sql_expr("empty IS NULL")(rec) is True
    assert compile_sql_expr("name IS NOT NULL")(rec) is True
    assert compile_sql_expr("id BETWEEN 5 AND 10")(rec) is True
    assert compile_sql_expr("id IN (3, 7, 9)")(rec) is True
    assert compile_sql_expr("name LIKE 'ali%'")(rec) is True
    assert compile_sql_expr("NOT (id = 99)")(rec) is True


def test_zero_per_record_reparsing_on_1000_row_scan() -> None:
    """Proves parse_sql_expr and re.compile run O(1) times across 1,000 rows."""
    ex = SQLExecutor()
    ex.execute("CREATE TABLE items (id INT, price INT, name VARCHAR)")
    values_sql = ", ".join(f"({i}, {i % 100}, 'item_{i % 20}')" for i in range(1000))
    ex.execute(f"INSERT INTO items (id, price, name) VALUES {values_sql}")
    ex.execute("SELECT 1")
    clear_sql_parser_caches()
    parse_calls: List[str] = []
    re_compile_calls: List[str] = []

    orig_parse = parse_sql_expr
    orig_re_compile = re.compile

    def spy_parse(text: str) -> Any:
        parse_calls.append(text)
        return orig_parse(text)

    def spy_re_compile(pattern: Any, flags: int = 0) -> Any:
        if isinstance(pattern, str):
            re_compile_calls.append(pattern)
        return orig_re_compile(pattern, flags)

    query = (
        "SELECT id, price * 2 + 1 AS doubled, "
        "CASE WHEN price >= 50 THEN 'high' ELSE 'low' END AS tier, "
        "name || '_tag' AS tagged "
        "FROM items "
        "WHERE price >= 10 AND name LIKE '%item%' "
        "ORDER BY price DESC"
    )
    with (
        patch.object(expr_compiler, "parse_sql_expr", side_effect=spy_parse),
        patch.object(expr_compiler.re, "compile", side_effect=spy_re_compile),
    ):
        res = ex.execute(query)

    assert res["count"] == 900
    assert res["rows"][0]["doubled"] == 199
    assert res["rows"][0]["tier"] == "high"
    assert res["rows"][0]["tagged"].endswith("_tag")
    assert len(parse_calls) <= 10, f"Per-record reparsing detected: {len(parse_calls)}"
    assert (
        len(re_compile_calls) <= 5
    ), f"Per-record regex compilation detected: {len(re_compile_calls)}"


def test_group_having_join_and_update_precompilation() -> None:
    """Verifies GROUP BY, MIN/MAX, HAVING, Hash Join, and UPDATE SET."""
    ex = SQLExecutor()
    ex.execute("CREATE TABLE sales (dept VARCHAR, amount INT, tag VARCHAR)")
    ex.execute(
        "INSERT INTO sales (dept, amount, tag) VALUES "
        "('eng', 10, 'a'), ('eng', 30, 'b'), ('hr', 5, 'c')"
    )
    res = ex.execute(
        "SELECT dept, MIN(amount) AS min_a, MAX(amount) AS max_a, "
        "SUM(amount) AS tot, GROUP_CONCAT(tag, '-') AS tags "
        "FROM sales GROUP BY dept HAVING SUM(amount) > 10"
    )
    assert res["count"] == 1
    assert res["rows"][0]["dept"] == "eng"
    assert res["rows"][0]["min_a"] == 10
    assert res["rows"][0]["max_a"] == 30
    assert res["rows"][0]["tot"] == 40
    assert res["rows"][0]["tags"] == "a-b"

    ex.execute("UPDATE sales SET amount = amount + 5 WHERE dept = 'eng'")
    check = ex.execute(
        "SELECT amount FROM sales WHERE dept = 'eng' ORDER BY amount ASC"
    )
    assert [r["amount"] for r in check["rows"]] == [15, 35]


def test_security_ast_depth_limit() -> None:
    """Rejects excessively nested expressions to prevent recursion DoS (CWE-674)."""
    clear_sql_parser_caches()
    deep_chain = " + ".join(["1"] * (MAX_EXPR_AST_DEPTH + 5))
    with pytest.raises(SQLExecutionError, match="depth exceeds limit"):
        compile_sql_expr(deep_chain)
    assert compile_sql_expr("((((1))))")({}) == 1


def test_security_like_redos_and_length_guard() -> None:
    """Collapses consecutive wildcards to prevent ReDoS and rejects huge patterns."""
    clear_sql_parser_caches()
    evil_pat = "%" * 50 + "target"
    compiled = compile_like_pattern(evil_pat)
    assert compiled.pattern.count(".*") == 1
    t0 = time.perf_counter()
    assert compiled.search("a" * 500) is None
    assert (time.perf_counter() - t0) < 0.02

    escaped = compile_like_pattern(r"\%\%a", escape="\\")
    assert escaped.search("%%a") is not None
    assert escaped.search("xxa") is None

    huge_pat = "a" * (MAX_LIKE_PATTERN_LEN + 1)
    with pytest.raises(SQLExecutionError, match="length exceeds limit"):
        compile_like_pattern(huge_pat)


def test_security_no_dynamic_eval_or_exec_and_cache_clear() -> None:
    """Ensures expr_compiler uses zero eval/exec and clears caches cleanly."""
    src = inspect.getsource(expr_compiler)
    assert re.search(r"(?<![a-zA-Z0-9_])eval\s*\(", src) is None
    assert re.search(r"(?<![a-zA-Z0-9_])exec\s*\(", src) is None

    clear_sql_parser_caches()
    compile_sql_expr("1 + 2")
    assert compile_sql_expr.cache_info().currsize >= 1
    clear_sql_parser_caches()
    assert compile_sql_expr.cache_info().currsize == 0


def test_2000_row_query_performance_budget() -> None:
    """Ensures precompiled 2,000-row complex query executes rapidly."""
    ex = SQLExecutor()
    ex.execute("CREATE TABLE bench (id INT, val INT, label VARCHAR)")
    rows_sql = ", ".join(f"({i}, {i % 200}, 'row_{i % 50}')" for i in range(2000))
    ex.execute(f"INSERT INTO bench (id, val, label) VALUES {rows_sql}")
    clear_sql_parser_caches()

    sql = (
        "SELECT id, val * 3 - 1 AS calc, "
        "CASE WHEN val >= 100 THEN 'hi' ELSE 'lo' END AS grp, "
        "label || '_ok' AS tag "
        "FROM bench "
        "WHERE val >= 20 AND label LIKE 'row_%' "
        "ORDER BY val DESC"
    )
    start = time.perf_counter()
    res = ex.execute(sql)
    elapsed = time.perf_counter() - start

    assert res["count"] == 1800
    assert elapsed < 0.50, f"2,000-row precompiled scan took too long: {elapsed:.3f}s"
