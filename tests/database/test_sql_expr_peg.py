#!/usr/bin/env python3
"""Comprehensive Unit Tests for Packrat PEG SQL Expression Parser.

Validates AST construction, operator precedence, predicate handling,
CASE expressions, function calls, legacy dictionary conversions,
and error handling without external dependencies.
"""

from __future__ import annotations

import pytest

from core.structures.peg import PEGSyntaxError
from database.sql import (
    BetweenExpr,
    BinaryOpExpr,
    CaseExpr,
    ColumnRefExpr,
    FunctionCallExpr,
    InExpr,
    IsNullExpr,
    LikeExpr,
    LiteralExpr,
    SQLExpressionParser,
    UnaryOpExpr,
    parse_sql_expr,
)


class TestSQLExprLiteralsAndColumns:
    """Tests for SQL literals and column identifiers."""

    def test_numeric_literals(self) -> None:
        parser = SQLExpressionParser()
        int_expr = parser.parse("42")
        assert isinstance(int_expr, LiteralExpr)
        assert int_expr.value == 42
        assert int_expr.to_sql() == "42"

        float_expr = parser.parse("3.1415")
        assert isinstance(float_expr, LiteralExpr)
        assert float_expr.value == 3.1415

    def test_string_literals(self) -> None:
        parser = SQLExpressionParser()
        single_quoted = parser.parse("'hello world'")
        assert isinstance(single_quoted, LiteralExpr)
        assert single_quoted.value == "hello world"
        assert single_quoted.to_sql() == "'hello world'"

        escaped_single = parser.parse("'it''s fine'")
        assert isinstance(escaped_single, LiteralExpr)
        assert escaped_single.value == "it's fine"

        double_quoted = parser.parse('"column_or_string"')
        assert isinstance(double_quoted, LiteralExpr)
        assert double_quoted.value == "column_or_string"

    def test_boolean_and_null_literals(self) -> None:
        parser = SQLExpressionParser()
        t_expr = parser.parse("TRUE")
        assert isinstance(t_expr, LiteralExpr)
        assert t_expr.value is True
        assert t_expr.to_sql() == "TRUE"

        f_expr = parser.parse("false")
        assert isinstance(f_expr, LiteralExpr)
        assert f_expr.value is False
        assert f_expr.to_sql() == "FALSE"

        null_expr = parser.parse("NULL")
        assert isinstance(null_expr, LiteralExpr)
        assert null_expr.value is None
        assert null_expr.to_sql() == "NULL"

    def test_column_references(self) -> None:
        parser = SQLExpressionParser()
        simple_col = parser.parse("user_id")
        assert isinstance(simple_col, ColumnRefExpr)
        assert simple_col.column_name == "user_id"
        assert simple_col.table_name is None
        assert simple_col.json_path is None
        assert simple_col.to_sql() == "user_id"

        qualified_col = parser.parse("papers.arxiv_id")
        assert isinstance(qualified_col, ColumnRefExpr)
        assert qualified_col.table_name == "papers"
        assert qualified_col.column_name == "arxiv_id"
        assert qualified_col.to_sql() == "papers.arxiv_id"

        json_col = parser.parse("metadata->>'title'")
        assert isinstance(json_col, ColumnRefExpr)
        assert json_col.column_name == "metadata"
        assert json_col.json_path == "title"
        assert json_col.to_sql() == "metadata->>'title'"


class TestSQLExprArithmeticAndPrecedence:
    """Tests for arithmetic operations and operator precedence."""

    def test_unary_operators(self) -> None:
        expr1 = parse_sql_expr("-x")
        assert isinstance(expr1, UnaryOpExpr)
        assert expr1.operator == "-"
        assert isinstance(expr1.operand, ColumnRefExpr)
        assert expr1.to_sql() == "-x"

        expr2 = parse_sql_expr("NOT is_active")
        assert isinstance(expr2, UnaryOpExpr)
        assert expr2.operator == "NOT"
        assert expr2.to_sql() == "NOT is_active"

    def test_precedence_mult_over_add(self) -> None:
        # 1 + 2 * 3 should be (1 + (2 * 3))
        expr = parse_sql_expr("1 + 2 * 3")
        assert isinstance(expr, BinaryOpExpr)
        assert expr.operator == "+"
        assert isinstance(expr.left, LiteralExpr)
        assert expr.left.value == 1
        assert isinstance(expr.right, BinaryOpExpr)
        assert expr.right.operator == "*"
        assert isinstance(expr.right.left, LiteralExpr)
        assert expr.right.left.value == 2
        assert isinstance(expr.right.right, LiteralExpr)
        assert expr.right.right.value == 3

    def test_parentheses_override_precedence(self) -> None:
        # (1 + 2) * 3
        expr = parse_sql_expr("(1 + 2) * 3")
        assert isinstance(expr, BinaryOpExpr)
        assert expr.operator == "*"
        assert isinstance(expr.left, BinaryOpExpr)
        assert expr.left.operator == "+"
        assert isinstance(expr.right, LiteralExpr)
        assert expr.right.value == 3


class TestSQLExprPredicatesAndComparisons:
    """Tests for comparison operators and SQL predicates."""

    def test_binary_comparisons(self) -> None:
        expr = parse_sql_expr("age >= 18")
        assert isinstance(expr, BinaryOpExpr)
        assert expr.operator == ">="
        assert isinstance(expr.left, ColumnRefExpr)
        assert isinstance(expr.right, LiteralExpr)
        assert expr.to_legacy_dict() == {
            "column": "age",
            "operator": ">=",
            "value": 18,
        }

    def test_is_null_and_is_not_null(self) -> None:
        expr_null = parse_sql_expr("deleted_at IS NULL")
        assert isinstance(expr_null, IsNullExpr)
        assert not expr_null.is_not
        assert expr_null.to_sql() == "deleted_at IS NULL"
        assert expr_null.to_legacy_dict() == {
            "column": "deleted_at",
            "operator": "IS NULL",
            "value": None,
        }

        expr_not_null = parse_sql_expr("updated_at IS NOT NULL")
        assert isinstance(expr_not_null, IsNullExpr)
        assert expr_not_null.is_not
        assert expr_not_null.to_sql() == "updated_at IS NOT NULL"
        assert expr_not_null.to_legacy_dict() == {
            "column": "updated_at",
            "operator": "IS NOT NULL",
            "value": None,
        }

    def test_between_predicate(self) -> None:
        expr = parse_sql_expr("score BETWEEN 80 AND 100")
        assert isinstance(expr, BetweenExpr)
        assert not expr.is_not
        assert expr.to_sql() == "score BETWEEN 80 AND 100"
        assert expr.to_legacy_dict() == {
            "column": "score",
            "operator": "BETWEEN",
            "value": [80, 100],
        }

        not_between = parse_sql_expr("score NOT BETWEEN 0 AND 50")
        assert isinstance(not_between, BetweenExpr)
        assert not_between.is_not
        assert not_between.to_sql() == "score NOT BETWEEN 0 AND 50"

    def test_in_predicate(self) -> None:
        expr = parse_sql_expr("status IN ('draft', 'published')")
        assert isinstance(expr, InExpr)
        assert not expr.is_not
        assert len(expr.values) == 2
        assert expr.to_sql() == "status IN ('draft', 'published')"
        assert expr.to_legacy_dict() == {
            "column": "status",
            "operator": "IN",
            "value": ["draft", "published"],
        }

        not_in = parse_sql_expr("category NOT IN (1, 2, 3)")
        assert isinstance(not_in, InExpr)
        assert not_in.is_not
        assert not_in.to_sql() == "category NOT IN (1, 2, 3)"
        assert not_in.to_legacy_dict() == {
            "column": "category",
            "operator": "NOT IN",
            "value": [1, 2, 3],
        }

    def test_like_glob_match(self) -> None:
        expr_like = parse_sql_expr("title LIKE '%security%'")
        assert isinstance(expr_like, LikeExpr)
        assert expr_like.operator == "LIKE"
        assert not expr_like.is_not
        assert expr_like.to_sql() == "title LIKE '%security%'"
        assert expr_like.to_legacy_dict() == {
            "column": "title",
            "operator": "LIKE",
            "value": "%security%",
        }

        expr_not_like = parse_sql_expr("title NOT LIKE 'Draft%'")
        assert isinstance(expr_not_like, LikeExpr)
        assert expr_not_like.is_not
        assert expr_not_like.to_legacy_dict() == {
            "column": "title",
            "operator": "NOT LIKE",
            "value": "Draft%",
        }

        expr_glob = parse_sql_expr("filename GLOB '*.py'")
        assert isinstance(expr_glob, LikeExpr)
        assert expr_glob.operator == "GLOB"

        expr_match = parse_sql_expr("content MATCH 'kernel'")
        assert isinstance(expr_match, LikeExpr)
        assert expr_match.operator == "MATCH"


class TestSQLExprLogicalAndNesting:
    """Tests for logical operators (AND, OR) and complex nesting."""

    def test_and_precedence_over_or(self) -> None:
        # a = 1 OR b = 2 AND c = 3 -> a = 1 OR (b = 2 AND c = 3)
        expr = parse_sql_expr("a = 1 OR b = 2 AND c = 3")
        assert isinstance(expr, BinaryOpExpr)
        assert expr.operator == "OR"
        assert isinstance(expr.right, BinaryOpExpr)
        assert expr.right.operator == "AND"

    def test_nested_parentheses(self) -> None:
        expr = parse_sql_expr("(a = 1 OR b = 2) AND (c = 3 OR d = 4)")
        assert isinstance(expr, BinaryOpExpr)
        assert expr.operator == "AND"
        assert isinstance(expr.left, BinaryOpExpr)
        assert expr.left.operator == "OR"
        assert isinstance(expr.right, BinaryOpExpr)
        assert expr.right.operator == "OR"


class TestSQLExprFunctionsAndCase:
    """Tests for function calls and CASE WHEN expressions."""

    def test_function_call_star(self) -> None:
        expr = parse_sql_expr("COUNT(*)")
        assert isinstance(expr, FunctionCallExpr)
        assert expr.func_name == "COUNT"
        assert expr.is_star
        assert len(expr.args) == 0
        assert expr.to_sql() == "COUNT(*)"

    def test_function_call_with_args(self) -> None:
        expr = parse_sql_expr("COALESCE(papers.title, 'Untitled')")
        assert isinstance(expr, FunctionCallExpr)
        assert expr.func_name == "COALESCE"
        assert not expr.is_star
        assert len(expr.args) == 2
        assert isinstance(expr.args[0], ColumnRefExpr)
        assert isinstance(expr.args[1], LiteralExpr)
        assert expr.to_sql() == "COALESCE(papers.title, 'Untitled')"

    def test_case_searched(self) -> None:
        expr = parse_sql_expr("CASE WHEN a > 0 THEN 'pos' ELSE 'non-pos' END")
        assert isinstance(expr, CaseExpr)
        assert expr.base_expr is None
        assert len(expr.when_branches) == 1
        assert expr.else_expr is not None
        assert isinstance(expr.else_expr, LiteralExpr)
        assert expr.else_expr.value == "non-pos"
        assert "CASE WHEN" in expr.to_sql()
        assert "ELSE 'non-pos' END" in expr.to_sql()

    def test_case_simple(self) -> None:
        expr = parse_sql_expr(
            "CASE status WHEN 1 THEN 'active' WHEN 2 THEN 'suspended' END"
        )
        assert isinstance(expr, CaseExpr)
        assert expr.base_expr is not None
        assert isinstance(expr.base_expr, ColumnRefExpr)
        assert len(expr.when_branches) == 2
        assert expr.else_expr is None


class TestSQLExprErrorsAndEdgeCases:
    """Tests for syntax error handling and edge cases."""

    def test_empty_query(self) -> None:
        with pytest.raises(ValueError):
            parse_sql_expr("   ")

    def test_syntax_error_unclosed_paren(self) -> None:
        with pytest.raises(PEGSyntaxError):
            parse_sql_expr("(a = 1 AND b = 2")

    def test_syntax_error_trailing_garbage(self) -> None:
        with pytest.raises(PEGSyntaxError):
            parse_sql_expr("a = 1 WHERE")
