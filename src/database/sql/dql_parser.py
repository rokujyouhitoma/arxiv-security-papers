#!/usr/bin/env python3
"""Pure-Python Ahead-of-Time Packrat PEG DQL (Data Query Language) Parser.

Parses arbitrary SQL SELECT, CTE, JOIN, SET operations, and VALUES statements into
strongly-typed `SelectStatement` AST nodes:
- SELECT projection list (*, table.*, expressions, aliases with/without AS)
- DISTINCT / ALL modifiers
- FROM clause: table references, table-valued functions (json_each, json_tree), subqueries
- JOIN clauses: INNER, LEFT [OUTER], RIGHT, CROSS, NATURAL, with ON / USING
- WHERE clause integrated with Packrat PEG SQLExpressionParser & KNN vector queries
- GROUP BY and HAVING clauses
- ORDER BY clause (ASC / DESC, COLLATE, NULLS FIRST/LAST)
- LIMIT and OFFSET clauses (LIMIT n OFFSET m / LIMIT m, n)
- Compound queries: UNION [ALL], INTERSECT, EXCEPT
- Common Table Expressions (CTE): WITH [RECURSIVE] name AS (query)
- Standalone VALUES queries: VALUES (r1, r2), (r3, r4)

Delegates directly to AOT compiled `SQLDQLParser` generated from `grammars/sql_dql.peg`.
Zero external dependencies. Conforms to DSN-25 Phase 2 Ahead-of-Time specification.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Optional, cast

from core.structures.peg import PEGSyntaxError

from .ast import SelectStatement
from .generated_sql_dql_parser import SQLDQLParser as _AOTSQLDQLParser


class SQLParseError(Exception):
    """Raised when SQL parsing fails."""

    pass


_GLOBAL_DQL_AOT_PARSER: Optional[_AOTSQLDQLParser] = None


def _get_dql_aot_parser() -> _AOTSQLDQLParser:
    global _GLOBAL_DQL_AOT_PARSER
    if _GLOBAL_DQL_AOT_PARSER is None:
        _GLOBAL_DQL_AOT_PARSER = _AOTSQLDQLParser()
    return _GLOBAL_DQL_AOT_PARSER


@lru_cache(maxsize=1024)
def parse_dql(text: str) -> SelectStatement:
    """Convenience helper to parse a DQL SQL string into SelectStatement AST with LRU caching."""
    stripped = text.strip().rstrip(";")
    if not stripped:
        raise SQLParseError("Empty SQL query")
    parser = _get_dql_aot_parser()
    try:
        stmt = cast(SelectStatement, parser.parse(stripped))
        stmt.raw_sql = text
        return stmt
    except PEGSyntaxError as exc:
        raise SQLParseError(
            f"SQL DQL syntax error at line {exc.line}, col {exc.col}: {exc.message}"
        ) from exc


def clear_dql_cache() -> None:
    """Clears the LRU cache for DQL query parsing."""
    parse_dql.cache_clear()


class SQLDQLParser:
    """Packrat PEG Parser for full SQL DQL queries (SELECT, CTE, JOIN, UNION, VALUES)."""

    def __init__(self) -> None:
        self._aot_parser = _get_dql_aot_parser()

    def parse(self, text: str) -> SelectStatement:
        return parse_dql(text)
