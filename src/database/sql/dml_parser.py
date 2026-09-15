#!/usr/bin/env python3
"""Pure-Python Ahead-of-Time Packrat PEG DML (Data Manipulation Language) Parser.

Parses arbitrary SQL INSERT, REPLACE, UPDATE, and DELETE statements into
strongly-typed AST nodes:
- INSERT INTO ... VALUES (...), (...)
- INSERT INTO ... SELECT ...
- REPLACE INTO ...
- UPSERT: ON CONFLICT (...) DO NOTHING / DO UPDATE SET ...
- UPDATE ... SET ... [FROM ...] [WHERE ...]
- DELETE FROM ... [WHERE ...]
- RETURNING clauses on all DML statements
- Index hints (INDEXED BY / NOT INDEXED) and conflict resolution clauses

Delegates directly to AOT compiled `SQLDMLParser` generated from `grammars/sql_dml.peg`.
Zero external dependencies. Conforms to DSN-25 Phase 2 Ahead-of-Time specification.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Optional, cast

from core.structures.peg import PEGSyntaxError

from .ast import SQLStatement
from .generated_sql_dml_parser import SQLDMLParser as _AOTSQLDMLParser


class SQLParseError(Exception):
    """Raised when SQL parsing fails."""

    pass


_GLOBAL_DML_AOT_PARSER: Optional[_AOTSQLDMLParser] = None


def _get_dml_aot_parser() -> _AOTSQLDMLParser:
    global _GLOBAL_DML_AOT_PARSER
    if _GLOBAL_DML_AOT_PARSER is None:
        _GLOBAL_DML_AOT_PARSER = _AOTSQLDMLParser()
    return _GLOBAL_DML_AOT_PARSER


@lru_cache(maxsize=1024)
def parse_dml(text: str) -> SQLStatement:
    """Convenience helper to parse a DML SQL string into SQLStatement AST with LRU caching."""
    stripped = text.strip().rstrip(";")
    if not stripped:
        raise SQLParseError("Empty SQL query")
    parser = _get_dml_aot_parser()
    try:
        stmt = cast(SQLStatement, parser.parse(stripped))
        stmt.raw_sql = text
        return stmt
    except PEGSyntaxError as exc:
        raise SQLParseError(
            f"SQL DML syntax error at line {exc.line}, col {exc.col}: {exc.message}"
        ) from exc


def clear_dml_cache() -> None:
    """Clears the LRU cache for DML query parsing."""
    parse_dml.cache_clear()


class SQLDMLParser:
    """Packrat PEG Parser for SQL DML statements (INSERT, UPDATE, DELETE, UPSERT)."""

    def __init__(self) -> None:
        self._aot_parser = _get_dml_aot_parser()

    def parse(self, text: str) -> SQLStatement:
        return parse_dml(text)
