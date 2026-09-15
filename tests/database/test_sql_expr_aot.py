#!/usr/bin/env python3
"""
Shadow Verification Test Suite for AOT-compiled SQL Expression Parser.
Validates 100% AST, to_sql(), and to_legacy_dict() parity between
the AOT SQLExprParser (generated_sql_expr_parser.py) and the existing
dynamic SQLExpressionParser (expr_parser.py).
Zero risk to existing RDBMS engine. Conforms to DSN-25 Phase 2 / Issue #301.
"""

from __future__ import annotations

import pytest

from core.structures.peg import PEGSyntaxError
from database.sql.expr_parser import (
    BetweenExpr,
    BinaryOpExpr,
    CaseExpr,
    CollateExpr,
    ColumnRefExpr,
    ExistsExpr,
    FunctionCallExpr,
    InExpr,
    IsNullExpr,
    LikeExpr,
    LiteralExpr,
    SQLExpressionParser,
    UnaryOpExpr,
)
from database.sql.generated_sql_expr_parser import SQLExprParser


@pytest.fixture
def aot_parser() -> SQLExprParser:
    return SQLExprParser()


@pytest.fixture
def dynamic_parser() -> SQLExpressionParser:
    return SQLExpressionParser()


class TestAOTSQLExprParity:
    """Verifies that the AOT parser produces identical AST outputs to the dynamic parser."""

    def test_numeric_literals_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in ["42", "3.1415"]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, LiteralExpr)
            assert isinstance(dyn_ast, LiteralExpr)
            assert aot_ast.value == dyn_ast.value
            assert aot_ast.to_sql() == dyn_ast.to_sql()

    def test_string_literals_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in ["'hello world'", "'it''s fine'", '"column_or_string"']:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, LiteralExpr)
            assert isinstance(dyn_ast, LiteralExpr)
            assert aot_ast.value == dyn_ast.value
            assert aot_ast.to_sql() == dyn_ast.to_sql()

    def test_boolean_and_null_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in ["TRUE", "false", "NULL"]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, LiteralExpr)
            assert isinstance(dyn_ast, LiteralExpr)
            assert aot_ast.value == dyn_ast.value
            assert aot_ast.to_sql() == dyn_ast.to_sql()

    def test_column_references_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in ["user_id", "papers.arxiv_id", "metadata->>'title'"]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, ColumnRefExpr)
            assert isinstance(dyn_ast, ColumnRefExpr)
            assert aot_ast.column_name == dyn_ast.column_name
            assert aot_ast.table_name == dyn_ast.table_name
            assert aot_ast.json_path == dyn_ast.json_path
            assert aot_ast.to_sql() == dyn_ast.to_sql()

    def test_unary_operators_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in ["-x", "NOT is_active"]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, UnaryOpExpr)
            assert isinstance(dyn_ast, UnaryOpExpr)
            assert aot_ast.operator == dyn_ast.operator
            assert aot_ast.to_sql() == dyn_ast.to_sql()

    def test_arithmetic_precedence_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in ["1 + 2 * 3", "(1 + 2) * 3", "10 - 4 / 2 + 1"]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, BinaryOpExpr)
            assert isinstance(dyn_ast, BinaryOpExpr)
            assert aot_ast.to_sql() == dyn_ast.to_sql()

    def test_binary_comparisons_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in [
            "age >= 18",
            "score < 60",
            "status = 'active'",
            "level != 0",
            "val <> 99",
        ]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, BinaryOpExpr)
            assert isinstance(dyn_ast, BinaryOpExpr)
            assert aot_ast.operator == dyn_ast.operator
            assert aot_ast.to_sql() == dyn_ast.to_sql()
            assert aot_ast.to_legacy_dict() == dyn_ast.to_legacy_dict()

    def test_is_null_predicates_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in ["deleted_at IS NULL", "updated_at IS NOT NULL"]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, IsNullExpr)
            assert isinstance(dyn_ast, IsNullExpr)
            assert aot_ast.is_not == dyn_ast.is_not
            assert aot_ast.to_sql() == dyn_ast.to_sql()
            assert aot_ast.to_legacy_dict() == dyn_ast.to_legacy_dict()

    def test_between_predicates_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in ["score BETWEEN 80 AND 100", "score NOT BETWEEN 0 AND 50"]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, BetweenExpr)
            assert isinstance(dyn_ast, BetweenExpr)
            assert aot_ast.is_not == dyn_ast.is_not
            assert aot_ast.to_sql() == dyn_ast.to_sql()
            assert aot_ast.to_legacy_dict() == dyn_ast.to_legacy_dict()

    def test_in_predicates_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in ["status IN ('draft', 'published')", "category NOT IN (1, 2, 3)"]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, InExpr)
            assert isinstance(dyn_ast, InExpr)
            assert aot_ast.is_not == dyn_ast.is_not
            assert len(aot_ast.values) == len(dyn_ast.values)
            assert aot_ast.to_sql() == dyn_ast.to_sql()
            assert aot_ast.to_legacy_dict() == dyn_ast.to_legacy_dict()

    def test_like_glob_match_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in [
            "title LIKE '%security%'",
            "title NOT LIKE 'Draft%'",
            "filename GLOB '*.py'",
            "content MATCH 'kernel'",
        ]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, LikeExpr)
            assert isinstance(dyn_ast, LikeExpr)
            assert aot_ast.operator == dyn_ast.operator
            assert aot_ast.is_not == dyn_ast.is_not
            assert aot_ast.to_sql() == dyn_ast.to_sql()
            assert aot_ast.to_legacy_dict() == dyn_ast.to_legacy_dict()

    def test_collate_and_exists_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        expr_c = aot_parser.parse("name = 'alice' COLLATE NOCASE")
        assert isinstance(expr_c, CollateExpr)
        assert expr_c.collation == "NOCASE"

        expr_e = aot_parser.parse("EXISTS (SELECT 1 FROM users)")
        assert isinstance(expr_e, ExistsExpr)
        assert not expr_e.is_not

        for q in [
            "name = 'alice' COLLATE NOCASE",
            "code BETWEEN 'a' AND 'z' COLLATE RTRIM",
            "EXISTS (SELECT 1 FROM users)",
        ]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert aot_ast.to_sql() == dyn_ast.to_sql()
            assert aot_ast.to_legacy_dict() == dyn_ast.to_legacy_dict()

    def test_logical_and_nesting_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        for q in [
            "a = 1 OR b = 2 AND c = 3",
            "(a = 1 OR b = 2) AND (c = 3 OR d = 4)",
        ]:
            aot_ast = aot_parser.parse(q)
            dyn_ast = dynamic_parser.parse(q)
            assert isinstance(aot_ast, BinaryOpExpr)
            assert aot_ast.to_sql() == dyn_ast.to_sql()

    def test_functions_and_case_parity(
        self, aot_parser: SQLExprParser, dynamic_parser: SQLExpressionParser
    ) -> None:
        q_func1 = "COUNT(*)"
        aot_f1 = aot_parser.parse(q_func1)
        dyn_f1 = dynamic_parser.parse(q_func1)
        assert isinstance(aot_f1, FunctionCallExpr)
        assert aot_f1.to_sql() == dyn_f1.to_sql()

        q_func2 = "COALESCE(papers.title, 'Untitled')"
        aot_f2 = aot_parser.parse(q_func2)
        dyn_f2 = dynamic_parser.parse(q_func2)
        assert isinstance(aot_f2, FunctionCallExpr)
        assert aot_f2.to_sql() == dyn_f2.to_sql()

        q_case1 = "CASE WHEN a > 0 THEN 'pos' ELSE 'non-pos' END"
        aot_c1 = aot_parser.parse(q_case1)
        dyn_c1 = dynamic_parser.parse(q_case1)
        assert isinstance(aot_c1, CaseExpr)
        assert aot_c1.to_sql() == dyn_c1.to_sql()

        q_case2 = "CASE status WHEN 1 THEN 'active' WHEN 2 THEN 'suspended' END"
        aot_c2 = aot_parser.parse(q_case2)
        dyn_c2 = dynamic_parser.parse(q_case2)
        assert isinstance(aot_c2, CaseExpr)
        assert aot_c2.to_sql() == dyn_c2.to_sql()

    def test_syntax_errors(self, aot_parser: SQLExprParser) -> None:
        with pytest.raises(PEGSyntaxError):
            aot_parser.parse("(a = 1 AND b = 2")
