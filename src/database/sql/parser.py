#!/usr/bin/env python3
"""Pure Python Packrat PEG SQL Parser Dispatcher.

Coordinates DQL, DML, DDL, and Admin Packrat PEG parsers into a unified interface.
Zero external dependencies, zero ad-hoc regular expressions.
"""

from __future__ import annotations

from typing import Any, Callable, Dict, List, Optional, Tuple, cast

from core.structures.peg import Choice, Lit, OneOrMore, Parser, Reg, Seq, ZeroOrMore

from .admin_parser import parse_admin
from .ast import (
    CreateTableStatement,
    DeleteStatement,
    InsertStatement,
    SelectStatement,
    SQLStatement,
    UpdateStatement,
)
from .ddl_parser import parse_ddl
from .dml_parser import parse_dml
from .dql_parser import parse_dql
from .expr_parser import BinaryOpExpr, SQLExpr, SQLExpressionParser


class SQLParseError(Exception):
    """Raised when SQL syntax cannot be parsed."""

    pass


# -----------------------------------------------------------------------------
# Packrat PEG Comma Expression Splitter
# -----------------------------------------------------------------------------


def _combine_comma_list(r: List[Any]) -> List[str]:
    first = cast(str, r[0])
    rest = [cast(str, item[1]) for item in cast(List[Any], r[1])]
    return [first] + rest


def _build_comma_split_parser() -> Parser[List[str]]:
    """Builds a pure PEG parser that splits comma-separated expressions."""
    chunk_item = Choice(
        Reg(r"'[^']*'"),
        Reg(r'"[^"]*"'),
        Reg(r"\((?:[^()]+|\([^()]*\))*\)"),
        Reg(r"[^,'\"()]+"),
    )
    chunk = OneOrMore(chunk_item).map(lambda chunks: "".join(chunks).strip())
    ws = Reg(r"\s*")
    sep = Seq(ws, Lit(","), ws)
    return Seq(chunk, ZeroOrMore(Seq(sep, chunk))).map(_combine_comma_list)


_COMMA_SPLIT_PARSER: Parser[List[str]] = _build_comma_split_parser()


def _split_comma_expressions(text: str) -> List[str]:
    """Splits a comma-separated list of expressions at top paren nesting level using PEG."""
    clean = text.strip()
    if not clean:
        return []
    try:
        items = _COMMA_SPLIT_PARSER.parse(clean)
        return [item for item in items if item]
    except Exception:
        return [clean]


def _parse_where_clause_item(part: str) -> Optional[Dict[str, Any]]:
    """Parses a single WHERE predicate term using Packrat PEG."""
    clean = part.strip()
    if not clean:
        return None
    try:
        expr = SQLExpressionParser().parse(clean)
        leg = expr.to_legacy_dict()
        if leg is not None:
            return leg
    except SQLParseError:
        raise
    except Exception:
        pass
    return {"column": clean, "operator": "=", "value": True}


# -----------------------------------------------------------------------------
# Packrat PEG WHERE AST Traversal & Legacy Mapping
# -----------------------------------------------------------------------------


def _flatten_and_exprs(expr: SQLExpr) -> List[SQLExpr]:
    """Flattens a binary tree of AND operations into a flat list of expressions."""
    if isinstance(expr, BinaryOpExpr) and expr.op == "AND":
        return _flatten_and_exprs(expr.left) + _flatten_and_exprs(expr.right)
    return [expr]


def _flatten_or_exprs(expr: SQLExpr) -> List[SQLExpr]:
    """Flattens a binary tree of OR operations into a flat list of branch expressions."""
    if isinstance(expr, BinaryOpExpr) and expr.op == "OR":
        return _flatten_or_exprs(expr.left) + _flatten_or_exprs(expr.right)
    return [expr]


def _expr_to_legacy_dict(expr: SQLExpr) -> Dict[str, Any]:
    """Converts a parsed SQLExpr into legacy engine WHERE dictionary."""
    leg = expr.to_legacy_dict()
    if leg is not None:
        return leg
    return {"column": expr.to_sql(), "operator": "=", "value": True}


def _build_or_clauses(or_branches: List[SQLExpr]) -> List[Dict[str, Any]]:
    clauses: List[Dict[str, Any]] = []
    for branch in or_branches:
        sub_clauses = [_expr_to_legacy_dict(e) for e in _flatten_and_exprs(branch)]
        clauses.append({"logic": "OR_BRANCH", "clauses": sub_clauses})
    return clauses


def _safe_parse_where_expr(
    parser: SQLExpressionParser, clean: str
) -> Optional[SQLExpr]:
    try:
        return parser.parse(clean)
    except SQLParseError:
        raise
    except Exception:
        return None


# -----------------------------------------------------------------------------
# Dispatcher Table & Keywords
# -----------------------------------------------------------------------------

_ADMIN_KEYWORDS: tuple[str, ...] = (
    "BEGIN",
    "COMMIT",
    "ROLLBACK",
    "SAVEPOINT",
    "RELEASE",
    "GRANT",
    "REVOKE",
    "PRAGMA",
    "VACUUM",
    "ANALYZE",
    "ATTACH",
    "DETACH",
    "EXPLAIN",
    "SHOW",
)

_PREFIX_DISPATCH: Tuple[Tuple[Tuple[str, ...], Callable[[str], SQLStatement]], ...] = (
    (("SELECT", "WITH", "VALUES"), parse_dql),
    (("INSERT", "REPLACE", "UPDATE", "DELETE"), parse_dml),
    (("CREATE", "ALTER", "DROP", "REINDEX"), parse_ddl),
    (_ADMIN_KEYWORDS, parse_admin),
)


def _clean_sql_text(text: Optional[str]) -> str:
    return text.strip() if text else ""


def _parse_where_to_clauses(
    parser: SQLExpressionParser, clean: str
) -> List[Dict[str, Any]]:
    expr = _safe_parse_where_expr(parser, clean)
    if expr is None:
        return [{"column": clean, "operator": "=", "value": True}]
    or_branches = _flatten_or_exprs(expr)
    if len(or_branches) > 1:
        return _build_or_clauses(or_branches)
    return [_expr_to_legacy_dict(e) for e in _flatten_and_exprs(expr)]


class SQLParser:
    """Unified Packrat PEG SQL Parser Dispatcher."""

    def __init__(self) -> None:
        self._expr_parser = SQLExpressionParser()

    def parse(self, sql_query: str) -> SQLStatement:
        """Parses any standard SQL query string into a typed SQLStatement AST."""
        sql = sql_query.strip().rstrip(";")
        if not sql:
            raise SQLParseError("Empty SQL query")
        return self._dispatch_parse(sql)

    @staticmethod
    def _dispatch_parse(sql: str) -> SQLStatement:
        upper = sql.upper().lstrip()
        for prefixes, parser_fn in _PREFIX_DISPATCH:
            if upper.startswith(prefixes):
                return parser_fn(sql)
        return SQLParser._try_fallback_parse(sql)

    @staticmethod
    def _try_fallback_parse(sql: str) -> SQLStatement:
        for parser_fn in (parse_dql, parse_dml, parse_ddl, parse_admin):
            try:
                return parser_fn(sql)
            except Exception:
                pass
        raise SQLParseError(f"Unsupported or unrecognized SQL statement: '{sql}'")

    # -------------------------------------------------------------------------
    # Backward compatibility helpers for internal callers (Pure PEG Powered)
    # -------------------------------------------------------------------------

    def _extract_where_clauses(self, where_raw: Optional[str]) -> List[Dict[str, Any]]:
        """Extracts legacy WHERE clause dictionary list purely using Packrat PEG."""
        clean = _clean_sql_text(where_raw)
        if not clean:
            return []
        return _parse_where_to_clauses(self._expr_parser, clean)

    def _parse_select(self, sql: str) -> SelectStatement:
        return parse_dql(sql)

    def _parse_cte(self, sql: str) -> SelectStatement:
        return parse_dql(sql)

    def _parse_insert(self, sql: str) -> InsertStatement:
        return cast(InsertStatement, parse_dml(sql))

    def _parse_update(self, sql: str) -> UpdateStatement:
        return cast(UpdateStatement, parse_dml(sql))

    def _parse_delete(self, sql: str) -> DeleteStatement:
        return cast(DeleteStatement, parse_dml(sql))

    def _parse_create_table(self, sql: str) -> CreateTableStatement:
        return cast(CreateTableStatement, parse_ddl(sql))


def parse_sql(sql_query: str) -> SQLStatement:
    """Convenience helper to parse an SQL string into SQLStatement AST."""
    parser = SQLParser()
    return parser.parse(sql_query)
