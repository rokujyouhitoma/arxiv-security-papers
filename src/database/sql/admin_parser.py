#!/usr/bin/env python3
"""Pure-Python Ahead-of-Time Packrat PEG Admin & Utility Parser.

Parses arbitrary SQL TCL, DCL, Admin, and Utility statements:
- BEGIN [DEFERRED|IMMEDIATE|EXCLUSIVE] [TRANSACTION]
- COMMIT [TRANSACTION]
- ROLLBACK [TRANSACTION] [TO [SAVEPOINT] name]
- SAVEPOINT name
- RELEASE [SAVEPOINT] name
- GRANT (ALL [PRIVILEGES] | perm) [ON (* | table)] TO role
- REVOKE (ALL [PRIVILEGES] | perm) [ON (* | table)] FROM role
- PRAGMA [schema.]name [= val | (val)]
- VACUUM [target] [INTO file]
- ANALYZE [schema[.target]]
- ATTACH [DATABASE] file AS schema
- DETACH [DATABASE] schema
- EXPLAIN [QUERY PLAN] stmt
- SHOW (DATABASES|SCHEMAS|TABLE STATUS|TABLES|COLUMNS|INDEXES) [FROM db] [LIKE pattern]

Delegates directly to AOT compiled `SQLAdminParser` generated from `grammars/sql_admin.peg`.
Zero external dependencies. Conforms to DSN-25 Phase 2 Ahead-of-Time specification.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Optional, cast

from core.structures.peg import PEGSyntaxError

from .ast import SQLStatement
from .generated_sql_admin_parser import SQLAdminParser as _AOTSQLAdminParser


class SQLParseError(Exception):
    """Raised when SQL admin parsing fails."""

    pass


_GLOBAL_ADMIN_AOT_PARSER: Optional[_AOTSQLAdminParser] = None


def _get_admin_aot_parser() -> _AOTSQLAdminParser:
    global _GLOBAL_ADMIN_AOT_PARSER
    if _GLOBAL_ADMIN_AOT_PARSER is None:
        _GLOBAL_ADMIN_AOT_PARSER = _AOTSQLAdminParser()
    return _GLOBAL_ADMIN_AOT_PARSER


@lru_cache(maxsize=1024)
def parse_admin(text: str) -> SQLStatement:
    """Convenience helper to parse an admin SQL string into SQLStatement AST with LRU caching."""
    stripped = text.strip().rstrip(";")
    if not stripped:
        raise SQLParseError("Empty SQL query")
    parser = _get_admin_aot_parser()
    try:
        stmt = cast(SQLStatement, parser.parse(stripped))
        stmt.raw_sql = text
        return stmt
    except PEGSyntaxError as exc:
        raise SQLParseError(
            f"SQL Admin syntax error at line {exc.line}, col {exc.col}: {exc.message}"
        ) from exc


def clear_admin_cache() -> None:
    """Clears the LRU cache for Admin query parsing."""
    parse_admin.cache_clear()


class SQLAdminParser:
    """Packrat PEG Parser for SQL TCL, DCL, Admin, and Utility statements."""

    def __init__(self) -> None:
        self._aot_parser = _get_admin_aot_parser()

    def parse(self, text: str) -> SQLStatement:
        return parse_admin(text)
