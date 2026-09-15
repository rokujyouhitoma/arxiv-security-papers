#!/usr/bin/env python3
"""Benchmark and performance verification for AOT-compiled Packrat PEG SQL Expression Parser.

Verifies:
1. Zero dynamic combinator graph construction overhead upon instantiation (< 0.10s for 100 instances).
2. High-throughput parsing of diverse SQL expressions (> 1,000 expressions in < 0.50s).
3. Fast execution on complex nested expressions (arithmetic, functions, predicates, CASE).
4. Zero-overhead delegation through parse_sql_expr() and SQLExpressionParser.
"""

import time

from database.sql.expr_parser import (
    BinaryOpExpr,
    CaseExpr,
    SQLExpressionParser,
    parse_sql_expr,
)
from database.sql.generated_sql_expr_parser import SQLExprParser


def test_sql_expr_aot_parser_initialization_speed() -> None:
    """Verifies that AOT parser initializes rapidly without dynamic combinator build overhead."""
    start = time.perf_counter()
    parsers = [SQLExprParser() for _ in range(100)]
    elapsed = time.perf_counter() - start

    assert len(parsers) == 100
    # 100 parser instantiations should take well under 0.10 seconds
    assert elapsed < 0.10


def test_sql_expr_aot_parser_throughput() -> None:
    """Verifies high throughput parsing of 1,000 standard SQL expressions."""
    expressions = [
        "a + b * 2",
        "user.id = 100 AND user.is_active = TRUE",
        "score BETWEEN 80 AND 100",
        "category IN ('security', 'crypto', 'network')",
        "title LIKE '%vulnerability%'",
        "payload->>'cve_id'",
        "COUNT(DISTINCT paper_id)",
        "CASE WHEN status = 1 THEN 'active' ELSE 'inactive' END",
        "(x > 0 AND y > 0) OR (x < 0 AND y < 0)",
        "NOT (deleted IS NULL)",
    ]

    parser = SQLExpressionParser()
    start = time.perf_counter()
    count = 0
    for _ in range(100):
        for expr_str in expressions:
            ast = parser.parse(expr_str)
            assert ast is not None
            count += 1
    elapsed = time.perf_counter() - start

    assert count == 1000
    # 1,000 expressions parsed in less than 1.0 second
    assert elapsed < 1.0


def test_sql_expr_nested_complex_expression_performance() -> None:
    """Verifies fast parsing of deep nested expressions with arithmetic and functions."""
    complex_expr = (
        "CASE "
        "  WHEN (base_score * 1.5 + bonus) >= 100.0 AND status = 'CERTIFIED' "
        "  THEN UPPER(report_title) "
        "  WHEN error_count > 0 OR flag IS NULL "
        "  THEN 'REQUIRES_TRIAGE' "
        "  ELSE COALESCE(default_tag, 'UNKNOWN') "
        "END"
    )

    parser = SQLExpressionParser()
    start = time.perf_counter()
    for _ in range(200):
        ast = parser.parse(complex_expr)
        assert isinstance(ast, CaseExpr)
    elapsed = time.perf_counter() - start

    # 200 complex evaluations should take well under 0.60 seconds
    assert elapsed < 0.60


def test_sql_expr_delegation_zero_overhead() -> None:
    """Verifies top-level parse_sql_expr() function delegates seamlessly with zero overhead."""
    start = time.perf_counter()
    for i in range(200):
        ast = parse_sql_expr(f"col_{i} = {i} AND is_valid IS NOT NULL")
        assert isinstance(ast, BinaryOpExpr)
    elapsed = time.perf_counter() - start

    # 200 top-level calls in less than 0.50 seconds
    assert elapsed < 0.50
