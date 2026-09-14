#!/usr/bin/env python3
"""Comprehensive Unit Tests for Packrat PEG DQL (Data Query Language) Parser.

Validates SELECT statements, CTEs, JOIN clauses, set operations,
standalone VALUES, order by, limit/offset, and error handling.
"""

from __future__ import annotations

import pytest

from database.sql.ast import JoinType, SQLCommandType
from database.sql.dql_parser import SQLParseError, parse_dql


class TestDQLBasicSelect:
    """Tests for basic SELECT projections, tables, and aliases."""

    def test_select_constants(self) -> None:
        stmt = parse_dql("SELECT 1, 'hello', TRUE, NULL")
        assert stmt.command_type == SQLCommandType.SELECT
        assert len(stmt.columns) == 4
        assert stmt.table_name == ""

    def test_select_columns_from_table(self) -> None:
        stmt = parse_dql("SELECT id, title, authors FROM papers")
        assert stmt.table_name == "papers"
        assert stmt.columns == ["id", "title", "authors"]
        assert not stmt.distinct

    def test_select_distinct(self) -> None:
        stmt = parse_dql("SELECT DISTINCT category FROM papers")
        assert stmt.distinct
        assert stmt.columns == ["category"]

    def test_select_star_and_qualified_star(self) -> None:
        stmt1 = parse_dql("SELECT * FROM papers")
        assert stmt1.columns == ["*"]

        stmt2 = parse_dql("SELECT papers.*, users.name FROM papers")
        assert stmt2.columns == ["papers.*", "users.name"]

    def test_table_alias_and_indexed_hint(self) -> None:
        stmt = parse_dql("SELECT p.id FROM papers AS p INDEXED BY idx_arxiv_id")
        assert stmt.table_ref is not None
        assert stmt.table_ref.name == "papers"
        assert stmt.table_ref.alias == "p"
        assert stmt.table_ref.indexed_by == "idx_arxiv_id"
        assert not stmt.table_ref.not_indexed


class TestDQLTableValuedFunctionsAndSubqueries:
    """Tests for table-valued functions and derived subqueries in FROM."""

    def test_table_valued_function(self) -> None:
        stmt = parse_dql("SELECT j.value FROM json_each('[1, 2, 3]') AS j")
        assert stmt.table_ref is not None
        assert stmt.table_ref.function_name == "json_each"
        assert stmt.table_ref.alias == "j"

    def test_derived_subquery(self) -> None:
        stmt = parse_dql(
            "SELECT sub.val FROM (SELECT val FROM metrics WHERE score > 90) AS sub"
        )
        assert stmt.table_ref is not None
        assert stmt.table_ref.alias == "sub"
        assert stmt.table_ref.subquery is not None
        assert stmt.table_ref.subquery.table_name == "metrics"


class TestDQLJoinsAndConditions:
    """Tests for JOIN clauses, ON / USING conditions."""

    def test_inner_join_on(self) -> None:
        sql = "SELECT p.title, a.name FROM papers AS p JOIN authors AS a ON p.author_id = a.id"
        stmt = parse_dql(sql)
        assert len(stmt.joins) == 1
        join = stmt.joins[0]
        assert join.join_type == JoinType.INNER
        assert join.table.name == "authors"
        assert len(join.on_conditions) >= 1

    def test_left_outer_join_using(self) -> None:
        sql = "SELECT * FROM papers LEFT OUTER JOIN citations USING (paper_id)"
        stmt = parse_dql(sql)
        assert len(stmt.joins) == 1
        join = stmt.joins[0]
        assert join.join_type == JoinType.LEFT
        assert join.table.name == "citations"
        assert len(join.on_conditions) == 1
        assert join.on_conditions[0]["column"] == "paper_id"

    def test_cross_join(self) -> None:
        sql = "SELECT * FROM a CROSS JOIN b"
        stmt = parse_dql(sql)
        assert len(stmt.joins) == 1
        assert stmt.joins[0].join_type == JoinType.CROSS


class TestDQLWhereAndAggregation:
    """Tests for WHERE filters, GROUP BY, HAVING, and KNN."""

    def test_where_binary_and_predicates(self) -> None:
        sql = "SELECT * FROM papers WHERE year >= 2024 AND status = 'published'"
        stmt = parse_dql(sql)
        assert len(stmt.where_clauses) == 2
        assert stmt.where_clauses[0]["column"] == "year"
        assert stmt.where_clauses[0]["operator"] == ">="
        assert stmt.where_clauses[0]["value"] == 2024

    def test_where_with_knn(self) -> None:
        sql = "SELECT * FROM papers WHERE KNN(embedding, [0.1, 0.2, 0.3], 5) AND year = 2024"
        stmt = parse_dql(sql)
        assert stmt.knn_query is not None
        assert stmt.knn_query["column"] == "embedding"
        assert stmt.knn_query["vector"] == [0.1, 0.2, 0.3]
        assert stmt.knn_query["top_k"] == 5
        assert len(stmt.where_clauses) == 1
        assert stmt.where_clauses[0]["column"] == "year"

    def test_group_by_and_having(self) -> None:
        sql = "SELECT category, COUNT(*) FROM papers GROUP BY category, year HAVING COUNT(*) > 10"
        stmt = parse_dql(sql)
        assert stmt.group_by == ["category", "year"]
        assert stmt.having is not None
        assert "COUNT(*)" in stmt.having


class TestDQLOrderByAndPagination:
    """Tests for ORDER BY, LIMIT, and OFFSET."""

    def test_order_by_collate_and_desc(self) -> None:
        sql = "SELECT * FROM users ORDER BY username COLLATE NOCASE DESC"
        stmt = parse_dql(sql)
        assert stmt.order_by == "username"
        assert stmt.order_desc is True
        assert stmt.order_collate == "NOCASE"

    def test_limit_and_offset_standard(self) -> None:
        sql = "SELECT * FROM papers LIMIT 25 OFFSET 50"
        stmt = parse_dql(sql)
        assert stmt.limit == 25
        assert stmt.offset == 50

    def test_limit_comma_syntax(self) -> None:
        sql = "SELECT * FROM papers LIMIT 50, 25"
        stmt = parse_dql(sql)
        assert stmt.limit == 25
        assert stmt.offset == 50


class TestDQLCompoundsAndCTE:
    """Tests for UNION, INTERSECT, EXCEPT, CTEs, and VALUES."""

    def test_union_and_union_all(self) -> None:
        sql1 = "SELECT 1 UNION SELECT 2"
        stmt1 = parse_dql(sql1)
        assert stmt1.union is not None
        assert len(stmt1.compounds) == 1
        assert stmt1.compounds[0][0] == "UNION"

        sql2 = "SELECT 1 UNION ALL SELECT 2"
        stmt2 = parse_dql(sql2)
        assert stmt2.union_all is not None
        assert stmt2.compounds[0][0] == "UNION ALL"

    def test_standalone_values(self) -> None:
        sql = "VALUES (1, 'Alice'), (2, 'Bob') ORDER BY column1 DESC LIMIT 1"
        stmt = parse_dql(sql)
        assert stmt.values_rows is not None
        assert len(stmt.values_rows) == 2
        assert stmt.values_rows[0] == [1, "Alice"]
        assert stmt.values_rows[1] == [2, "Bob"]
        assert stmt.columns == ["column1", "column2"]
        assert stmt.limit == 1
        assert stmt.order_desc is True

    def test_cte_with_recursive(self) -> None:
        sql = (
            "WITH RECURSIVE cnt(x) AS ("
            "SELECT 1 UNION ALL SELECT x + 1 FROM cnt WHERE x < 5"
            ") SELECT x FROM cnt"
        )
        stmt = parse_dql(sql)
        assert len(stmt.ctes) == 1
        cte = stmt.ctes[0]
        assert cte.name == "cnt"
        assert cte.is_recursive is True
        assert cte.columns == ["x"]
        assert stmt.table_name == "cnt"


class TestDQLErrorsAndEdgeCases:
    """Tests for error handling."""

    def test_empty_query(self) -> None:
        with pytest.raises(SQLParseError):
            parse_dql("   ")

    def test_malformed_syntax(self) -> None:
        with pytest.raises(SQLParseError):
            parse_dql("SELECT FROM")
