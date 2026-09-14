#!/usr/bin/env python3
"""
Pure Python Packrat PEG SQL Parser Dispatcher.
Coordinates DQL, DML, DDL, and Admin Packrat PEG parsers into a unified interface.
Eliminates all ad-hoc regular expression parsers and scanner logic in favor of PEG grammar.
"""

from __future__ import annotations

import re
from typing import Any, Callable, Dict, List, Optional, Tuple, cast

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
from .expr_parser import SQLExpressionParser


class SQLParseError(Exception):
    """Raised when SQL syntax cannot be parsed."""

    pass


def _process_paren_depth(ch: str, depth: int) -> int:
    if ch == "(":
        return depth + 1
    if ch == ")":
        return max(0, depth - 1)
    return depth


def _update_quote_flags(ch: str, in_s: bool, in_d: bool) -> Tuple[bool, bool]:
    if ch == "'" and not in_d:
        return not in_s, in_d
    if ch == '"' and not in_s:
        return in_s, not in_d
    return in_s, in_d


def _process_comma_char(
    ch: str,
    depth: int,
    in_s: bool,
    in_d: bool,
    cur: List[str],
    res: List[str],
) -> Tuple[int, bool, bool]:
    in_s, in_d = _update_quote_flags(ch, in_s, in_d)
    if not in_s and not in_d:
        depth = _process_paren_depth(ch, depth)
        if ch == "," and depth == 0:
            res.append("".join(cur).strip())
            cur.clear()
            return depth, in_s, in_d
    cur.append(ch)
    return depth, in_s, in_d


def _split_comma_expressions(text: str) -> List[str]:
    """Splits a comma-separated list of expressions at top paren nesting level."""
    res: List[str] = []
    cur: List[str] = []
    depth = 0
    in_single = False
    in_double = False

    for ch in text:
        depth, in_single, in_double = _process_comma_char(
            ch, depth, in_single, in_double, cur, res
        )

    if cur:
        res.append("".join(cur).strip())
    return res


def _parse_val_type(clean_val: str) -> Any:
    try:
        return int(clean_val)
    except ValueError:
        pass
    try:
        return float(clean_val)
    except ValueError:
        return clean_val


_ALLOWED_COLLATIONS: set[str] = {"BINARY", "NOCASE", "RTRIM"}


def _validate_collation(name: str) -> str:
    clean = name.strip().upper()
    if clean not in _ALLOWED_COLLATIONS:
        raise SQLParseError(f"no such collation sequence: {name}")
    return clean


def _parse_is_null_clause(part: str) -> Optional[Dict[str, Any]]:
    null_m = re.match(
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+IS\s+(NOT\s+NULL|NULL)$",
        part,
        re.IGNORECASE,
    )
    if null_m:
        op = "IS NOT NULL" if "NOT" in null_m.group(2).upper() else "IS NULL"
        return {"column": null_m.group(1), "operator": op, "value": None}
    return None


def _parse_between_clause(part: str) -> Optional[Dict[str, Any]]:
    pattern = (
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+(NOT\s+BETWEEN|BETWEEN)\s+"
        r"('[^']*'|\"[^\"]*\"|-?[0-9\.]+)\s+AND\s+('[^']*'|\"[^\"]*\"|-?[0-9\.]+)"
        r"(?:\s+COLLATE\s+([a-zA-Z0-9_]+))?$"
    )
    between_m = re.match(pattern, part, re.IGNORECASE)
    if between_m:
        v1 = _parse_val_type(between_m.group(3).strip("'\""))
        v2 = _parse_val_type(between_m.group(4).strip("'\""))
        res: Dict[str, Any] = {
            "column": between_m.group(1),
            "operator": between_m.group(2).upper(),
            "value": (v1, v2),
        }
        if between_m.group(5):
            res["collate"] = _validate_collation(between_m.group(5))
        return res
    return None


def _parse_glob_clause(part: str) -> Optional[Dict[str, Any]]:
    glob_m = re.match(
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+(NOT\s+GLOB|GLOB)\s+('[^']*'|\"[^\"]*\")$",
        part,
        re.IGNORECASE,
    )
    if glob_m:
        return {
            "column": glob_m.group(1),
            "operator": glob_m.group(2).upper(),
            "value": glob_m.group(3).strip("'\""),
        }
    return None


def _parse_like_clause(part: str) -> Optional[Dict[str, Any]]:
    like_m = re.match(
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+(NOT\s+LIKE|LIKE)\s+('[^']*'|\"[^\"]*\")(?:\s+ESCAPE\s+('[^']*'|\"[^\"]*\"))?$",
        part,
        re.IGNORECASE,
    )
    if like_m:
        escape_char = like_m.group(4).strip("'\"") if like_m.group(4) else None
        return {
            "column": like_m.group(1),
            "operator": like_m.group(2).upper(),
            "value": like_m.group(3).strip("'\""),
            "escape": escape_char,
        }
    return None


def _parse_exists_clause(part: str) -> Optional[Dict[str, Any]]:
    m = re.match(
        r"^(NOT\s+EXISTS|EXISTS)\s*\((.*?)\)$", part.strip(), re.IGNORECASE | re.DOTALL
    )
    if not m:
        return None
    raw_inner = m.group(2).strip()
    if not raw_inner.upper().startswith("SELECT"):
        return None
    return {
        "column": "*",
        "operator": re.sub(r"\s+", " ", m.group(1).upper()),
        "subquery": raw_inner,
    }


def _parse_in_clause(part: str) -> Optional[Dict[str, Any]]:
    in_m = re.match(
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+(NOT\s+IN|IN)\s*\((.*?)\)(?:\s+COLLATE\s+([a-zA-Z0-9_]+))?$",
        part,
        re.IGNORECASE | re.DOTALL,
    )
    if not in_m:
        return None
    raw_inner = in_m.group(3).strip()
    op = re.sub(r"\s+", " ", in_m.group(2).upper())
    if raw_inner.upper().startswith("SELECT"):
        res: Dict[str, Any] = {
            "column": in_m.group(1),
            "operator": op,
            "subquery": raw_inner,
        }
    else:
        items = [x.strip().strip("'\"") for x in raw_inner.split(",")]
        res = {"column": in_m.group(1), "operator": op, "value": items}
    if in_m.group(4):
        res["collate"] = _validate_collation(in_m.group(4))
    return res


def _parse_match_clause(part: str) -> Optional[Dict[str, Any]]:
    pattern = (
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+MATCH\s+"
        r"('[^']*'|\"[^\"]*\"|[a-zA-Z0-9_\.\->>\'\"]+)$"
    )
    m = re.match(pattern, part, re.IGNORECASE)
    if m:
        val = m.group(2).strip("'\"")
        return {"column": m.group(1), "operator": "MATCH", "value": val}
    return None


def _parse_cmp_clause(part: str) -> Optional[Dict[str, Any]]:
    cmp_pattern = (
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s*(>=|<=|!=|<>|=|>|<)\s*"
        r"('[^']*'|\"[^\"]*\"|[a-zA-Z0-9_\.\->>\'\"]+|-?[0-9\.]+)(?:\s+COLLATE\s+([a-zA-Z0-9_]+))?$"
    )
    eq_m = re.match(cmp_pattern, part, re.IGNORECASE)
    if eq_m:
        clean_val = eq_m.group(3).strip("'\"")
        v: Any = _parse_val_type(clean_val)
        res = {"column": eq_m.group(1), "operator": eq_m.group(2), "value": v}
        if eq_m.group(4):
            res["collate"] = _validate_collation(eq_m.group(4))
        return res
    return None


_WHERE_PARSERS = (
    _parse_is_null_clause,
    _parse_between_clause,
    _parse_glob_clause,
    _parse_like_clause,
    _parse_exists_clause,
    _parse_in_clause,
    _parse_match_clause,
    _parse_cmp_clause,
)


def _parse_where_clause_item(part: str) -> Optional[Dict[str, Any]]:
    """Parses a single WHERE predicate term."""
    clean = part.strip()
    if not clean:
        return None
    for parser in _WHERE_PARSERS:
        res = parser(clean)
        if res is not None:
            return res
    return _parse_where_expr_fallback(clean)


def _parse_where_expr_fallback(clean: str) -> Dict[str, Any]:
    try:
        expr = SQLExpressionParser().parse(clean)
        leg = expr.to_legacy_dict()
        if leg is not None:
            return leg
    except Exception:
        pass
    return {"column": clean, "operator": "=", "value": True}


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
    # Backward compatibility helpers for internal callers
    # -------------------------------------------------------------------------

    def _extract_where_clauses(self, where_raw: Optional[str]) -> List[Dict[str, Any]]:
        clauses: List[Dict[str, Any]] = []
        if not where_raw:
            return clauses

        or_parts = re.split(r"\s+OR\s+", where_raw, flags=re.IGNORECASE)
        if len(or_parts) > 1:
            for part in or_parts:
                sub_clauses = self._extract_simple_clauses(part)
                clauses.append({"logic": "OR_BRANCH", "clauses": sub_clauses})
            return clauses

        return self._extract_simple_clauses(where_raw)

    def _extract_simple_clauses(self, text: str) -> List[Dict[str, Any]]:
        clauses: List[Dict[str, Any]] = []
        if not text:
            return clauses

        and_parts = _split_and_conditions(text)
        for part in and_parts:
            item = _parse_where_clause_item(part)
            if item is not None:
                clauses.append(item)
        return clauses

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


def _split_and_conditions(text: str) -> List[str]:
    """Splits conditions on AND while preserving BETWEEN ... AND ... clauses."""
    pattern = (
        r"(\b(?:NOT\s+)?BETWEEN\s+(?:'[^']*'|\"[^\"]*\"|[a-zA-Z0-9_\.\->>\'\"]+|-?[0-9\.]+))\s+AND\s+"
        r"((?:'[^']*'|\"[^\"]*\"|[a-zA-Z0-9_\.\->>\'\"]+|-?[0-9\.]+))"
    )
    protected = re.sub(pattern, r"\1 __BETWEEN_AND__ \2", text, flags=re.IGNORECASE)
    parts = re.split(r"\s+AND\s+", protected, flags=re.IGNORECASE)
    return [p.replace("__BETWEEN_AND__", "AND").strip() for p in parts if p.strip()]


def parse_sql(sql_query: str) -> SQLStatement:
    """Convenience helper to parse an SQL string into SQLStatement AST."""
    parser = SQLParser()
    return parser.parse(sql_query)
