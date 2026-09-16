#!/usr/bin/env python3
"""Pure-Python Ahead-of-Time Packrat PEG DDL (Data Definition Language) Parser.

Parses arbitrary SQL DDL statements:
- CREATE TABLE (STRICT, constraints, foreign keys, storage engine, location)
- CREATE VIRTUAL TABLE (fts5, json, vector)
- CREATE [UNIQUE] INDEX ON table (column)
- CREATE VIEW AS SELECT ...
- CREATE TRIGGER (BEFORE/AFTER/INSTEAD OF INSERT/UPDATE/DELETE)
- ALTER TABLE (RENAME TABLE, RENAME COLUMN, ADD COLUMN, DROP COLUMN)
- DROP (TABLE, INDEX, VIEW, TRIGGER)
- REINDEX

Delegates directly to AOT compiled `SQLDDLParser` generated from `grammars/sql_ddl.peg`.
Zero external dependencies. Conforms to DSN-25 Phase 2 Ahead-of-Time specification.
"""

from __future__ import annotations

from typing import cast

from core.structures.peg import PEGSyntaxError

from .ast import SQLStatement
from .generated_sql_ddl_parser import SQLDDLParser as _AOTSQLDDLParser


class SQLParseError(Exception):
    """Raised when SQL parsing fails."""

    pass


class SQLDDLParser:
    """Packrat PEG Parser for SQL DDL statements."""

    def __init__(self) -> None:
        self._aot_parser = _AOTSQLDDLParser()

    def parse(self, text: str) -> SQLStatement:
        stripped = text.strip().rstrip(";")
        if not stripped:
            raise SQLParseError("Empty SQL query")
        try:
            stmt = cast(SQLStatement, self._aot_parser.parse(stripped))
            stmt.raw_sql = text
            return stmt
        except PEGSyntaxError as exc:
            raise SQLParseError(
                f"SQL DDL syntax error at line {exc.line}, col {exc.col}: {exc.message}"
            ) from exc


def parse_ddl(text: str) -> SQLStatement:
    """Convenience helper to parse a DDL SQL string into SQLStatement AST."""
    parser = SQLDDLParser()
    return parser.parse(text)
