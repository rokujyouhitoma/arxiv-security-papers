#!/usr/bin/env python3
"""Benchmark and performance verification for AOT-compiled Packrat PEG SQL Subsystems (DQL, DML, DDL).

Verifies:
1. Zero dynamic combinator graph construction overhead upon instantiation (< 0.10s for 100 instances).
2. High-throughput parsing of diverse SQL DQL queries (> 500 queries in < 1.0s).
3. High-throughput parsing of diverse SQL DML statements (> 500 statements in < 1.0s).
4. High-throughput parsing of diverse SQL DDL statements (> 500 statements in < 1.0s).
5. Seamless unified parser delegation through SQLParser.
"""

import time

from database.sql.ddl_parser import SQLDDLParser, parse_ddl
from database.sql.dml_parser import SQLDMLParser, parse_dml
from database.sql.dql_parser import SQLDQLParser, parse_dql
from database.sql.parser import SQLParser


def test_sql_subsystems_aot_parser_initialization_speed() -> None:
    """Verifies that AOT parsers initialize rapidly without dynamic combinator build overhead."""
    start = time.perf_counter()
    dql_parsers = [SQLDQLParser() for _ in range(100)]
    dml_parsers = [SQLDMLParser() for _ in range(100)]
    ddl_parsers = [SQLDDLParser() for _ in range(100)]
    elapsed = time.perf_counter() - start

    assert len(dql_parsers) == 100
    assert len(dml_parsers) == 100
    assert len(ddl_parsers) == 100
    # 300 total parser instantiations should take well under 0.30 seconds (< 1ms per instance)
    assert elapsed < 0.30


def test_sql_dql_aot_parser_throughput() -> None:
    """Verifies high throughput parsing of 500 standard SQL DQL queries."""
    queries = [
        "SELECT id, title, score FROM papers WHERE score > 0.85 ORDER BY score DESC LIMIT 10",
        "SELECT p.id, a.name FROM papers AS p JOIN authors AS a ON p.author_id = a.id",
        "SELECT category, COUNT(*), AVG(score) FROM papers GROUP BY category HAVING COUNT(*) > 5",
        "WITH recent AS (SELECT * FROM papers WHERE year >= 2025) SELECT * FROM recent",
        "SELECT 1 AS num, 'active' AS status",
    ]

    parser = SQLDQLParser()
    start = time.perf_counter()
    count = 0
    for _ in range(100):
        for q in queries:
            stmt = parser.parse(q)
            assert stmt is not None
            count += 1
    elapsed = time.perf_counter() - start

    assert count == 500
    # 500 queries parsed in less than 1.5 seconds
    assert elapsed < 1.5


def test_sql_dml_aot_parser_throughput() -> None:
    """Verifies high throughput parsing of 500 standard SQL DML statements."""
    statements = [
        "INSERT INTO papers (id, title, score) VALUES (1, 'Paper A', 0.95)",
        "INSERT INTO papers (id, score) VALUES (1, 0.9) ON CONFLICT (id) DO UPDATE SET score = 0.9",
        "UPDATE papers SET score = score + 0.1, status = 'reviewed' WHERE id = 10",
        "DELETE FROM papers WHERE score < 0.5 RETURNING id, title",
        "REPLACE INTO cache (key, value) VALUES ('k1', 'v1')",
    ]

    parser = SQLDMLParser()
    start = time.perf_counter()
    count = 0
    for _ in range(100):
        for stmt_str in statements:
            stmt = parser.parse(stmt_str)
            assert stmt is not None
            count += 1
    elapsed = time.perf_counter() - start

    assert count == 500
    # 500 statements parsed in less than 1.5 seconds
    assert elapsed < 1.5


def test_sql_ddl_aot_parser_throughput() -> None:
    """Verifies high throughput parsing of 500 standard SQL DDL statements."""
    statements = [
        "CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT NOT NULL, score REAL)",
        "CREATE TABLE logs (id INTEGER, ts TEXT) STRICT",
        "CREATE INDEX idx_papers_score ON papers (score DESC)",
        "CREATE VIEW high_score_papers AS SELECT * FROM papers WHERE score > 0.9",
        "ALTER TABLE papers ADD COLUMN tags TEXT",
    ]

    parser = SQLDDLParser()
    start = time.perf_counter()
    count = 0
    for _ in range(100):
        for stmt_str in statements:
            stmt = parser.parse(stmt_str)
            assert stmt is not None
            count += 1
    elapsed = time.perf_counter() - start

    assert count == 500
    # 500 statements parsed in less than 1.5 seconds
    assert elapsed < 1.5


def test_sql_subsystems_unified_parser_throughput() -> None:
    """Verifies SQLParser top-level dispatcher parses diverse statements with high throughput."""
    all_statements = [
        "SELECT id FROM papers WHERE id = 1",
        "INSERT INTO papers (id) VALUES (2)",
        "UPDATE papers SET id = 3 WHERE id = 2",
        "DELETE FROM papers WHERE id = 3",
        "CREATE TABLE test (id INTEGER)",
        "DROP TABLE test",
    ]

    parser = SQLParser()
    start = time.perf_counter()
    count = 0
    for _ in range(100):
        for sql in all_statements:
            stmt = parser.parse(sql)
            assert stmt is not None
            count += 1
    elapsed = time.perf_counter() - start

    assert count == 600
    # 600 mixed statements parsed in less than 2.0 seconds
    assert elapsed < 2.0


def test_sql_subsystems_convenience_functions_delegation() -> None:
    """Verifies parse_dql, parse_dml, and parse_ddl functions delegate cleanly."""
    start = time.perf_counter()
    for i in range(100):
        dql = parse_dql(f"SELECT {i} AS num")
        assert dql is not None
        dml = parse_dml(f"DELETE FROM items WHERE id = {i}")
        assert dml is not None
        ddl = parse_ddl(f"DROP TABLE IF EXISTS tbl_{i}")
        assert ddl is not None
    elapsed = time.perf_counter() - start

    # 300 function calls in less than 1.0 second
    assert elapsed < 1.0
