#!/usr/bin/env python3
"""
Pure Python SQL Lexer & Parser.
Parses standard SQL statements into typed AST objects without external dependencies.
"""

import ast as py_ast
import re
from typing import Any, Dict, List, Optional, Tuple

from .ast import (
    AlterTableAction,
    AlterTableStatement,
    AnalyzeStatement,
    AttachStatement,
    BeginStatement,
    ColumnDef,
    CommitStatement,
    CreateIndexStatement,
    CreateTableStatement,
    CreateTriggerStatement,
    CreateViewStatement,
    CreateVirtualTableStatement,
    CTEDefinition,
    DeleteStatement,
    DetachStatement,
    DropIndexStatement,
    DropTableStatement,
    DropTriggerStatement,
    DropViewStatement,
    ExplainStatement,
    GrantStatement,
    InsertStatement,
    JoinClause,
    JoinType,
    PragmaStatement,
    ReindexStatement,
    RevokeStatement,
    RollbackStatement,
    SavepointStatement,
    SelectStatement,
    ShowStatement,
    SQLCommandType,
    SQLStatement,
    TableRef,
    UpdateStatement,
    VacuumStatement,
)


class SQLParseError(Exception):
    """Raised when SQL syntax cannot be parsed."""

    pass


def _extract_distinct_prefix(cols_raw: str) -> Tuple[str, bool]:
    """Strips DISTINCT or ALL prefix from projection column string."""
    if re.match(r"^DISTINCT\s+", cols_raw, re.IGNORECASE):
        return re.sub(r"^DISTINCT\s+", "", cols_raw, flags=re.IGNORECASE).strip(), True
    if re.match(r"^ALL\s+", cols_raw, re.IGNORECASE):
        return re.sub(r"^ALL\s+", "", cols_raw, flags=re.IGNORECASE).strip(), False
    return cols_raw, False


def _update_quote_state(ch: str, in_quote: bool, quote_char: str) -> Tuple[bool, str]:
    if ch in ("'", '"') and not in_quote:
        return True, ch
    if ch == quote_char and in_quote:
        return False, ""
    return in_quote, quote_char


def _update_paren_depth(ch: str, depth: int) -> int:
    delta = 1 if ch == "(" else (-1 if ch == ")" else 0)
    return depth + delta


def _update_scan_state(
    ch: str, paren_depth: int, in_quote: bool, quote_char: str
) -> Tuple[int, bool, str]:
    """Updates quote and paren states for expression scanning."""
    new_in_quote, new_quote_char = _update_quote_state(ch, in_quote, quote_char)
    if not in_quote and not new_in_quote:
        return _update_paren_depth(ch, paren_depth), False, ""
    return paren_depth, new_in_quote, new_quote_char


def _is_top_level_comma(ch: str, paren_depth: int, in_quote: bool) -> bool:
    return ch == "," and paren_depth == 0 and not in_quote


def _is_top_level_boundary(i: int, sql: str, paren_depth: int, in_quote: bool) -> bool:
    return paren_depth == 0 and not in_quote and (i == 0 or sql[i - 1].isspace())


def _find_top_level_keyword_pos(sql: str, pattern: str) -> Optional[Tuple[int, int]]:
    """Finds start and end index of top-level keyword pattern."""
    regex = re.compile(rf"^({pattern})(?:\s+|$)", re.IGNORECASE)
    paren_depth, in_quote, quote_char = 0, False, ""
    for i, ch in enumerate(sql):
        if _is_top_level_boundary(i, sql, paren_depth, in_quote):
            m = regex.match(sql[i:])
            if m:
                return i, i + len(m.group(1))
        paren_depth, in_quote, quote_char = _update_scan_state(
            ch, paren_depth, in_quote, quote_char
        )
    return None


def _collect_remaining_chunk(res: List[str], curr: List[str]) -> List[str]:
    if curr:
        res.append("".join(curr).strip())
    return [c for c in res if c]


def _process_comma_char(
    ch: str, paren_depth: int, in_quote: bool, curr: List[str], res: List[str]
) -> None:
    if _is_top_level_comma(ch, paren_depth, in_quote):
        res.append("".join(curr).strip())
        curr.clear()
    else:
        curr.append(ch)


def _split_comma_expressions(expr_str: str) -> List[str]:
    """Splits comma-separated expressions respecting parentheses and quotes."""
    res: List[str] = []
    curr: List[str] = []
    paren_depth, in_quote, quote_char = 0, False, ""
    for ch in expr_str:
        paren_depth, in_quote, quote_char = _update_scan_state(
            ch, paren_depth, in_quote, quote_char
        )
        _process_comma_char(ch, paren_depth, in_quote, curr, res)
    return _collect_remaining_chunk(res, curr)


def _parse_alter_rename_table(sql: str) -> Optional[AlterTableStatement]:
    """Parses ALTER TABLE tbl RENAME TO new_tbl."""
    m = re.match(
        r"^ALTER\s+TABLE\s+([a-zA-Z0-9_]+)\s+RENAME\s+TO\s+([a-zA-Z0-9_]+)$",
        sql,
        re.IGNORECASE,
    )
    if not m:
        return None
    return AlterTableStatement(
        command_type=SQLCommandType.ALTER_TABLE,
        raw_sql=sql,
        table_name=m.group(1),
        action=AlterTableAction.RENAME_TABLE,
        new_table_name=m.group(2),
    )


def _parse_alter_rename_column(sql: str) -> Optional[AlterTableStatement]:
    """Parses ALTER TABLE tbl RENAME [COLUMN] old_col TO new_col."""
    m = re.match(
        r"^ALTER\s+TABLE\s+([a-zA-Z0-9_]+)\s+RENAME\s+(?:COLUMN\s+)?([a-zA-Z0-9_]+)\s+TO\s+([a-zA-Z0-9_]+)$",
        sql,
        re.IGNORECASE,
    )
    if not m:
        return None
    return AlterTableStatement(
        command_type=SQLCommandType.ALTER_TABLE,
        raw_sql=sql,
        table_name=m.group(1),
        action=AlterTableAction.RENAME_COLUMN,
        old_column_name=m.group(2),
        new_column_name=m.group(3),
    )


def _resolve_raw_default_val(raw_val: Optional[str]) -> Any:
    """Parses raw DEFAULT literal string into typed value."""
    if raw_val is None or raw_val.upper() == "NULL":
        return None
    if re.match(r"^-?\d+$", raw_val):
        return int(raw_val)
    if re.match(r"^-?\d+\.\d+$", raw_val):
        return float(raw_val)
    return raw_val


def _extract_default_value(col_def_str: str) -> Tuple[str, Any]:
    """Extracts DEFAULT clause from column definition string."""
    m = re.search(
        r"\s+DEFAULT\s+('([^']*)'|\"([^\"]*)\"|([a-zA-Z0-9_\.\-]+))",
        col_def_str,
        re.IGNORECASE,
    )
    if not m:
        return col_def_str, None
    raw_val = m.group(2) or m.group(3) or m.group(4)
    cleaned_col = col_def_str[: m.start()] + col_def_str[m.end() :]
    return cleaned_col.strip(), _resolve_raw_default_val(raw_val)


def _parse_alter_add_column(
    sql: str, parser_instance: Any
) -> Optional[AlterTableStatement]:
    """Parses ALTER TABLE tbl ADD [COLUMN] col_def."""
    m = re.match(
        r"^ALTER\s+TABLE\s+([a-zA-Z0-9_]+)\s+ADD\s+(?:COLUMN\s+)?(.*)$",
        sql,
        re.IGNORECASE,
    )
    if not m:
        return None
    cleaned_def, default_val = _extract_default_value(m.group(2).strip())
    c_def = parser_instance._parse_column_def(cleaned_def)
    return AlterTableStatement(
        command_type=SQLCommandType.ALTER_TABLE,
        raw_sql=sql,
        table_name=m.group(1),
        action=AlterTableAction.ADD_COLUMN,
        column_def=c_def,
        default_value=default_val,
    )


def _parse_alter_drop_column(sql: str) -> Optional[AlterTableStatement]:
    """Parses ALTER TABLE tbl DROP [COLUMN] col_name."""
    m = re.match(
        r"^ALTER\s+TABLE\s+([a-zA-Z0-9_]+)\s+DROP\s+(?:COLUMN\s+)?([a-zA-Z0-9_]+)$",
        sql,
        re.IGNORECASE,
    )
    if not m:
        return None
    return AlterTableStatement(
        command_type=SQLCommandType.ALTER_TABLE,
        raw_sql=sql,
        table_name=m.group(1),
        action=AlterTableAction.DROP_COLUMN,
        drop_column_name=m.group(2),
    )


def _resolve_show_target(upper_sql: str) -> str:
    """Resolves target entity for SHOW command."""
    if "SHOW DATABASES" in upper_sql or "SHOW SCHEMAS" in upper_sql:
        return "DATABASES"
    if "SHOW TABLE STATUS" in upper_sql:
        return "TABLE_STATUS"
    if "SHOW TABLES" in upper_sql:
        return "TABLES"
    raise SQLParseError(f"Unsupported SHOW query: {upper_sql}")


def _parse_like_clause(part: str) -> Optional[Dict[str, Any]]:
    """Parses LIKE/NOT LIKE condition with optional ESCAPE."""
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


def _parse_glob_clause(part: str) -> Optional[Dict[str, Any]]:
    """Parses GLOB/NOT GLOB condition."""
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


def _parse_is_null_clause(part: str) -> Optional[Dict[str, Any]]:
    """Parses IS NULL / IS NOT NULL condition."""
    null_m = re.match(
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+IS\s+(NOT\s+NULL|NULL)$",
        part,
        re.IGNORECASE,
    )
    if null_m:
        op = "IS NOT NULL" if "NOT" in null_m.group(2).upper() else "IS NULL"
        return {"column": null_m.group(1), "operator": op, "value": None}
    return None


_ALLOWED_COLLATIONS: set[str] = {"BINARY", "NOCASE", "RTRIM"}


def _validate_collation(name: str) -> str:
    clean = name.strip().upper()
    if clean not in _ALLOWED_COLLATIONS:
        raise SQLParseError(f"no such collation sequence: {name}")
    return clean


def _parse_between_clause(part: str) -> Optional[Dict[str, Any]]:
    """Parses BETWEEN / NOT BETWEEN condition."""
    pattern = (
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s+(NOT\s+BETWEEN|BETWEEN)\s+"
        r"('[^']*'|\"[^\"]*\"|[0-9\.]+)\s+AND\s+('[^']*'|\"[^\"]*\"|[0-9\.]+)"
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


def _parse_in_clause(part: str) -> Optional[Dict[str, Any]]:
    """Parses IN/NOT IN condition (literals or subqueries)."""
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


def _parse_exists_clause(part: str) -> Optional[Dict[str, Any]]:
    """Parses EXISTS/NOT EXISTS (SELECT ...) condition."""
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


def _parse_cmp_clause(part: str) -> Optional[Dict[str, Any]]:
    """Parses standard comparison condition."""
    cmp_pattern = (
        r"^([a-zA-Z0-9_\.\->>\'\"]+)\s*(>=|<=|!=|<>|=|>|<)\s*"
        r"('[^']*'|\"[^\"]*\"|[a-zA-Z0-9_\.\->>\'\"]+|[0-9\.]+)(?:\s+COLLATE\s+([a-zA-Z0-9_]+))?$"
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
    return None


def _parse_val_type(clean_val: str) -> Any:
    """Parses numeric literal or returns string."""
    if clean_val.isdigit():
        return int(clean_val)
    try:
        return float(clean_val)
    except ValueError:
        return clean_val


_ALLOWED_ENGINES: set[str] = {
    "binary_vdb",
    "json_lines",
    "json_table",
    "file_plain_text",
}


def _validate_storage_engine(engine: Optional[str]) -> Optional[str]:
    if not engine:
        return None
    clean = engine.strip().lower()
    if clean not in _ALLOWED_ENGINES:
        allowed = ", ".join(sorted(_ALLOWED_ENGINES))
        raise SQLParseError(
            f"Unsupported storage engine: '{engine}'. Allowed: [{allowed}]"
        )
    return clean


def _update_depth(char: str, depth: int) -> int:
    if char == "(":
        return depth + 1
    if char == ")":
        return max(0, depth - 1)
    return depth


def _append_current_part(current: list[str], cols: list[str]) -> None:
    part = "".join(current).strip()
    if part:
        cols.append(part)


def _split_column_defs(cols_body: str) -> list[str]:
    """Split comma-separated column definitions respecting nested parentheses."""
    cols: list[str] = []
    current: list[str] = []
    depth = 0
    for char in cols_body:
        depth = _update_depth(char, depth)
        is_sep = char == "," and depth == 0
        if is_sep:
            _append_current_part(current, cols)
            current.clear()
        else:
            current.append(char)
    _append_current_part(current, cols)
    return cols


def _parse_limit_offset_clause(lim_str: str) -> Tuple[Optional[int], Optional[int]]:
    """Parses numeric LIMIT and optional OFFSET from limit string."""
    m_off = re.match(r"^([0-9]+)\s+OFFSET\s+([0-9]+)$", lim_str, re.IGNORECASE)
    if m_off:
        return int(m_off.group(1)), int(m_off.group(2))
    m_comma = re.match(r"^([0-9]+)\s*,\s*([0-9]+)$", lim_str)
    if m_comma:
        return int(m_comma.group(2)), int(m_comma.group(1))
    m_single = re.match(r"^([0-9]+)$", lim_str)
    if m_single:
        return int(m_single.group(1)), None
    return None, None


def _extract_limit_and_offset(
    clean_sql: str,
) -> Tuple[str, Optional[int], Optional[int]]:
    """Extracts and strips LIMIT and OFFSET values."""
    pos = _find_top_level_keyword_pos(clean_sql, r"LIMIT")
    if not pos:
        return clean_sql, None, None
    k_start, k_end = pos
    lim, off = _parse_limit_offset_clause(clean_sql[k_end:].strip())
    return clean_sql[:k_start].strip(), lim, off


def _extract_storage_clauses(sql: str) -> tuple[str, Optional[str], Optional[str]]:
    """Extract optional USING <engine> and LOCATION '<path>' clauses from CREATE TABLE."""
    loc_match = re.search(r"\s+LOCATION\s+['\"](.*?)['\"]\s*$", sql, re.IGNORECASE)
    location = loc_match.group(1).strip() if loc_match else None
    cleaned = sql[: loc_match.start()] if loc_match else sql

    using_match = re.search(r"\s+USING\s+([a-zA-Z0-9_]+)\s*$", cleaned, re.IGNORECASE)
    raw_engine = using_match.group(1).strip() if using_match else None
    cleaned = cleaned[: using_match.start()] if using_match else cleaned

    engine = _validate_storage_engine(raw_engine)
    return cleaned.strip(), engine, location


ALLOWED_STRICT_TYPES = {"INT", "INTEGER", "REAL", "TEXT", "BLOB", "ANY"}


def _validate_strict_columns(columns: List[ColumnDef]) -> None:
    for col in columns:
        dt = col.data_type.strip().upper()
        if dt not in ALLOWED_STRICT_TYPES:
            raise SQLParseError(
                f"Unknown datatype for {col.name} in STRICT table: {col.data_type}"
            )


def _extract_generated_column_info(
    raw_col: str, c_name: str
) -> Tuple[str, Optional[str], bool]:
    gen_pattern = r"(?:GENERATED\s+ALWAYS\s+)?AS\s*\((.*?)\)(?:\s+(STORED|VIRTUAL))?"
    gen_m = re.search(gen_pattern, raw_col, re.IGNORECASE)
    if not gen_m:
        return raw_col, None, False
    gen_expr = gen_m.group(1).strip()
    if re.search(rf"\b{re.escape(c_name)}\b", gen_expr):
        raise SQLParseError(f"Generated column '{c_name}' cannot refer to itself")
    is_stored = bool(gen_m.group(2) and gen_m.group(2).upper() == "STORED")
    cleaned = raw_col[: gen_m.start()] + raw_col[gen_m.end() :]
    return cleaned.strip(), gen_expr, is_stored


def _extract_collate_from_col_def(raw_col: str) -> Tuple[str, Optional[str]]:
    m = re.search(r"\bCOLLATE\s+([a-zA-Z0-9_]+)\b", raw_col, re.IGNORECASE)
    if not m:
        return raw_col, None
    collate = _validate_collation(m.group(1))
    cleaned = (raw_col[: m.start()] + raw_col[m.end() :]).strip()
    return cleaned, collate


def _split_and_conditions(text: str) -> List[str]:
    """Splits conditions on AND while preserving BETWEEN ... AND ... clauses."""
    pattern = (
        r"(\b(?:NOT\s+)?BETWEEN\s+(?:'[^']*'|\"[^\"]*\"|[a-zA-Z0-9_\.\->>\'\"]+|[0-9\.]+))\s+AND\s+"
        r"((?:'[^']*'|\"[^\"]*\"|[a-zA-Z0-9_\.\->>\'\"]+|[0-9\.]+))"
    )
    protected = re.sub(pattern, r"\1 __BETWEEN_AND__ \2", text, flags=re.IGNORECASE)
    parts = re.split(r"\s+AND\s+", protected, flags=re.IGNORECASE)
    return [p.replace("__BETWEEN_AND__", "AND").strip() for p in parts if p.strip()]


def _extract_returning_clause(sql: str) -> Tuple[str, Optional[List[str]]]:
    """Extracts optional RETURNING col1, col2, ... from end of DML statement."""
    m = re.search(r"\s+RETURNING\s+(.+)$", sql, re.IGNORECASE)
    if not m:
        return sql, None
    returning_raw = m.group(1).strip()
    cleaned_sql = sql[: m.start()].strip()
    cols = [c.strip() for c in returning_raw.split(",")]
    return cleaned_sql, cols


def _parse_set_assignments(set_raw: str) -> Tuple[Dict[str, Any], Dict[str, str]]:
    """Parses SET k1=v1, k2=v2 into static assignments and raw expression strings."""
    assignments: Dict[str, Any] = {}
    raw_assignments: Dict[str, str] = {}
    for item in set_raw.split(","):
        if "=" in item:
            k, v_raw = item.split("=", 1)
            k_clean = k.strip()
            v_clean = v_raw.strip()
            raw_assignments[k_clean] = v_clean
            assignments[k_clean] = _parse_val_type(v_clean.strip("'\""))
    return assignments, raw_assignments


def _parse_set_assignments_static(set_raw: str) -> Dict[str, Any]:
    """Parses SET k1=v1, k2=v2 assignments statically."""
    assignments, _ = _parse_set_assignments(set_raw)
    return assignments


def _extract_upsert_nothing(
    sql: str,
) -> Optional[Tuple[str, Optional[List[str]], str, Dict[str, Any]]]:
    pattern = r"\s+ON\s+CONFLICT(?:\s*\((.*?)\))?\s+DO\s+NOTHING\s*$"
    m = re.search(pattern, sql, re.IGNORECASE)
    if not m:
        return None
    cleaned = sql[: m.start()].strip()
    cols_raw = m.group(1)
    cols = [c.strip() for c in cols_raw.split(",")] if cols_raw else None
    return cleaned, cols, "NOTHING", {}


def _extract_upsert_update(
    sql: str,
) -> Optional[Tuple[str, Optional[List[str]], str, Dict[str, Any]]]:
    pattern = r"\s+ON\s+CONFLICT(?:\s*\((.*?)\))?\s+DO\s+UPDATE\s+SET\s+(.+)$"
    m = re.search(pattern, sql, re.IGNORECASE)
    if not m:
        return None
    cleaned = sql[: m.start()].strip()
    cols_raw = m.group(1)
    cols = [c.strip() for c in cols_raw.split(",")] if cols_raw else None
    update_set = _parse_set_assignments_static(m.group(2).strip())
    return cleaned, cols, "UPDATE", update_set


def _extract_upsert_clause(
    sql: str,
) -> Tuple[str, Optional[List[str]], Optional[str], Dict[str, Any]]:
    """Extracts optional ON CONFLICT clause."""
    nothing_res = _extract_upsert_nothing(sql)
    if nothing_res is not None:
        return nothing_res
    update_res = _extract_upsert_update(sql)
    if update_res is not None:
        return update_res
    return sql, None, None, {}


def _handle_close_paren(depth: int, current: List[str], tuples: List[str]) -> int:
    if depth == 1:
        tuples.append("".join(current).strip())
        current.clear()
        return 0
    current.append(")")
    return max(0, depth - 1)


def _handle_value_char(
    ch: str, depth: int, current: List[str], tuples: List[str]
) -> int:
    if ch == "(":
        if depth >= 1:
            current.append(ch)
        return depth + 1
    if ch == ")":
        return _handle_close_paren(depth, current, tuples)
    if depth >= 1:
        current.append(ch)
    return depth


def _extract_values_tuples(values_raw: str) -> List[str]:
    """Splits multiple (val1, val2), (val3, val4) value tuples."""
    tuples: List[str] = []
    current: List[str] = []
    depth = 0
    for ch in values_raw:
        depth = _handle_value_char(ch, depth, current, tuples)
    return tuples


def _extract_values_rows(parser: Any, raw_sql: str, clean_sql: str) -> List[List[Any]]:
    m = re.match(r"^VALUES\s*(.+)$", clean_sql, re.IGNORECASE | re.DOTALL)
    if not m:
        raise SQLParseError(f"Malformed VALUES syntax: {raw_sql}")
    raw_tuples = _extract_values_tuples(m.group(1).strip())
    if not raw_tuples:
        raise SQLParseError(f"Empty VALUES clause: {raw_sql}")
    res: List[List[Any]] = []
    for t in raw_tuples:
        res.append(parser._parse_insert_values(t))
    return res


def _generate_default_column_names(rows: List[List[Any]]) -> List[str]:
    max_cols = 0
    for r in rows:
        if len(r) > max_cols:
            max_cols = len(r)
    res: List[str] = []
    for i in range(max_cols):
        res.append(f"column{i+1}")
    return res


def _extract_dml_order_and_limit(
    sql: str,
) -> Tuple[str, Optional[str], bool, Optional[int]]:
    """Extracts optional ORDER BY and LIMIT from UPDATE or DELETE statement."""
    cleaned, limit_val, _ = _extract_limit_and_offset(sql)
    order_pattern = r"\s+ORDER\s+BY\s+([a-zA-Z0-9_\.\->>\'\"]+)(?:\s+(ASC|DESC))?\s*$"
    order_m = re.search(order_pattern, cleaned, re.IGNORECASE)
    if not order_m:
        return cleaned, None, False, limit_val
    order_col = order_m.group(1).strip()
    order_desc = bool(order_m.group(2) and order_m.group(2).upper() == "DESC")
    return cleaned[: order_m.start()].strip(), order_col, order_desc, limit_val


def _parse_savepoint_stmt(sql: str) -> Optional[SavepointStatement]:
    m_sp = re.match(r"^SAVEPOINT\s+([a-zA-Z0-9_]+)$", sql.strip(), re.IGNORECASE)
    if m_sp:
        return SavepointStatement(
            command_type=SQLCommandType.SAVEPOINT,
            raw_sql=sql,
            name=m_sp.group(1),
            action="SAVEPOINT",
        )
    m_rel = re.match(
        r"^RELEASE(?:\s+SAVEPOINT)?\s+([a-zA-Z0-9_]+)$", sql.strip(), re.IGNORECASE
    )
    if m_rel:
        return SavepointStatement(
            command_type=SQLCommandType.RELEASE,
            raw_sql=sql,
            name=m_rel.group(1),
            action="RELEASE",
        )
    m_rb = re.match(
        r"^ROLLBACK(?:\s+TRANSACTION)?\s+TO(?:\s+SAVEPOINT)?\s+([a-zA-Z0-9_]+)$",
        sql.strip(),
        re.IGNORECASE,
    )
    if m_rb:
        return SavepointStatement(
            command_type=SQLCommandType.ROLLBACK_TO,
            raw_sql=sql,
            name=m_rb.group(1),
            action="ROLLBACK_TO",
        )
    return None


def _parse_pragma_stmt(sql: str) -> Optional[PragmaStatement]:
    clean = sql.strip()
    m = re.match(
        r"^PRAGMA\s+([a-zA-Z0-9_]+)(?:\s*\(\s*([a-zA-Z0-9_]+)\s*\)|\s*=\s*([a-zA-Z0-9_'\"]+))?$",
        clean,
        re.IGNORECASE,
    )
    if not m:
        return None
    p_name = m.group(1).lower()
    arg = m.group(2)
    val = m.group(3).strip("'\"") if m.group(3) else None
    return PragmaStatement(
        command_type=SQLCommandType.PRAGMA,
        raw_sql=sql,
        pragma_name=p_name,
        argument=arg,
        value=val,
    )


def _parse_vacuum_stmt(sql: str) -> Optional[VacuumStatement]:
    clean = sql.strip()
    m = re.match(
        r"^VACUUM(?:\s+INTO\s+['\"](.*?)['\"]|\s+([a-zA-Z0-9_]+))?$",
        clean,
        re.IGNORECASE,
    )
    if not m:
        return None
    into_file = m.group(1)
    target_table = m.group(2)
    return VacuumStatement(
        command_type=SQLCommandType.VACUUM,
        raw_sql=sql,
        target_table=target_table,
        into_file=into_file,
    )


def _parse_analyze_stmt(sql: str) -> Optional[AnalyzeStatement]:
    clean = sql.strip()
    m = re.match(
        r"^ANALYZE(?:\s+(?:([a-zA-Z0-9_]+)\.)?([a-zA-Z0-9_]+))?$",
        clean,
        re.IGNORECASE,
    )
    if not m:
        return None
    schema_name = m.group(1)
    target_name = m.group(2)
    return AnalyzeStatement(
        command_type=SQLCommandType.ANALYZE,
        raw_sql=sql,
        target_name=target_name,
        schema_name=schema_name,
    )


def _parse_attach_stmt(sql: str) -> AttachStatement:
    clean = sql.strip().rstrip(";")
    pattern = r"^ATTACH(?:\s+DATABASE)?\s+(?:'([^']*)'|\"([^\"]*)\"|(\S+))\s+AS\s+([a-zA-Z_][a-zA-Z0-9_]*)$"
    m = re.match(pattern, clean, re.IGNORECASE)
    if not m:
        raise SQLParseError(f"Malformed ATTACH syntax: {sql}")
    filename = m.group(1) or m.group(2) or m.group(3)
    schema_name = m.group(4)
    return AttachStatement(
        command_type=SQLCommandType.ATTACH,
        raw_sql=sql,
        filename=filename,
        schema_name=schema_name,
    )


def _parse_detach_stmt(sql: str) -> DetachStatement:
    clean = sql.strip().rstrip(";")
    pattern = r"^DETACH(?:\s+DATABASE)?\s+([a-zA-Z_][a-zA-Z0-9_]*)$"
    m = re.match(pattern, clean, re.IGNORECASE)
    if not m:
        raise SQLParseError(f"Malformed DETACH syntax: {sql}")
    schema_name = m.group(1)
    return DetachStatement(
        command_type=SQLCommandType.DETACH,
        raw_sql=sql,
        schema_name=schema_name,
    )


def _parse_create_virtual_table(sql: str) -> CreateVirtualTableStatement:
    clean = sql.strip().rstrip(";")
    pattern = (
        r"^CREATE\s+VIRTUAL\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?"
        r"([a-zA-Z0-9_.]+)\s+USING\s+([a-zA-Z0-9_]+)(?:\s*\((.*)\))?$"
    )
    m = re.match(pattern, clean, re.IGNORECASE | re.DOTALL)
    if not m:
        raise SQLParseError(f"Malformed CREATE VIRTUAL TABLE syntax: {sql}")

    if_not_exists = bool(m.group(1))
    table_name = m.group(2)
    module_name = m.group(3)
    args_raw = m.group(4)
    args = _split_comma_expressions(args_raw.strip()) if args_raw else []

    return CreateVirtualTableStatement(
        command_type=SQLCommandType.CREATE_VIRTUAL_TABLE,
        raw_sql=sql,
        table_name=table_name,
        module_name=module_name,
        module_args=args,
        if_not_exists=if_not_exists,
    )


def _parse_create_trigger_stmt(sql: str) -> CreateTriggerStatement:
    pattern = (
        r"^CREATE\s+TRIGGER\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_]+)\s+"
        r"(BEFORE|AFTER|INSTEAD\s+OF)\s+(INSERT|UPDATE|DELETE)\s+ON\s+([a-zA-Z0-9_]+)"
        r"(?:\s+FOR\s+EACH\s+ROW)?\s+BEGIN\s+(.*?)\s+END$"
    )
    m = re.match(pattern, sql.strip(), re.IGNORECASE | re.DOTALL)
    if not m:
        raise SQLParseError(f"Malformed CREATE TRIGGER syntax: {sql}")
    timing = re.sub(r"\s+", " ", m.group(2)).upper()
    body_raw = m.group(5).strip()
    body_sqls = [s.strip() for s in body_raw.split(";") if s.strip()]
    return CreateTriggerStatement(
        command_type=SQLCommandType.CREATE_TRIGGER,
        raw_sql=sql,
        trigger_name=m.group(1),
        timing=timing,
        event=m.group(3).upper(),
        table_name=m.group(4),
        body_sqls=body_sqls,
    )


def _parse_drop_trigger_stmt(sql: str) -> DropTriggerStatement:
    m = re.match(
        r"^DROP\s+TRIGGER\s+(IF\s+EXISTS\s+)?([a-zA-Z0-9_]+)$",
        sql.strip(),
        re.IGNORECASE,
    )
    if not m:
        raise SQLParseError(f"Malformed DROP TRIGGER syntax: {sql}")
    return DropTriggerStatement(
        command_type=SQLCommandType.DROP_TRIGGER,
        raw_sql=sql,
        trigger_name=m.group(2),
        if_exists=bool(m.group(1)),
    )


def _extract_index_hint(text: str) -> Tuple[str, Optional[str], bool]:
    """Extracts INDEXED BY <idx> or NOT INDEXED hint from table reference string."""
    clean = text.strip()
    m_not_indexed = re.search(r"\s+NOT\s+INDEXED\s*$", clean, re.IGNORECASE)
    if m_not_indexed:
        return clean[: m_not_indexed.start()].strip(), None, True
    m_indexed_by = re.search(
        r"\s+INDEXED\s+BY\s+([a-zA-Z0-9_]+)\s*$", clean, re.IGNORECASE
    )
    if m_indexed_by:
        idx_name = m_indexed_by.group(1)
        return clean[: m_indexed_by.start()].strip(), idx_name, False
    return clean, None, False


class SQLParser:
    """
    Parses SQL string queries into structured SQLStatement AST nodes.
    Supports advanced features: CTE (WITH RECURSIVE), JOINs, JSON operators (->, ->>), and Aliases.
    """

    def _parse_tcl(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if re.match(r"^BEGIN(\s+TRANSACTION)?$", upper_sql):
            return BeginStatement(command_type=SQLCommandType.BEGIN, raw_sql=sql)
        if re.match(r"^COMMIT$", upper_sql):
            return CommitStatement(command_type=SQLCommandType.COMMIT, raw_sql=sql)
        if re.match(r"^ROLLBACK$", upper_sql):
            return RollbackStatement(command_type=SQLCommandType.ROLLBACK, raw_sql=sql)
        return _parse_savepoint_stmt(sql)

    def _parse_ddl_table(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("CREATE VIRTUAL TABLE"):
            return _parse_create_virtual_table(sql)
        if upper_sql.startswith("CREATE TABLE"):
            return self._parse_create_table(sql)
        if upper_sql.startswith("DROP TABLE"):
            return self._parse_drop_table(sql)
        if upper_sql.startswith("ALTER TABLE"):
            return self._parse_alter_table(sql)
        return None

    def _parse_ddl_index(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("CREATE INDEX"):
            return self._parse_create_index(sql)
        if upper_sql.startswith("DROP INDEX"):
            return self._parse_drop_index(sql)
        if upper_sql.startswith("REINDEX"):
            return self._parse_reindex(sql)
        return None

    def _parse_ddl_view(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("CREATE VIEW"):
            return self._parse_create_view(sql)
        if upper_sql.startswith("DROP VIEW"):
            return self._parse_drop_view(sql)
        return None

    def _parse_ddl_trigger(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("CREATE TRIGGER"):
            return _parse_create_trigger_stmt(sql)
        if upper_sql.startswith("DROP TRIGGER"):
            return _parse_drop_trigger_stmt(sql)
        return None

    def _parse_ddl(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        return (
            self._parse_ddl_table(upper_sql, sql)
            or self._parse_ddl_index(upper_sql, sql)
            or self._parse_ddl_view(upper_sql, sql)
            or self._parse_ddl_trigger(upper_sql, sql)
        )

    def _parse_dml_dql_part(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("WITH"):
            return self._parse_cte(sql)
        if upper_sql.startswith(("SELECT", "VALUES")):
            return self._parse_select(sql)
        if upper_sql.startswith(("INSERT INTO", "REPLACE INTO")):
            return self._parse_insert(sql)
        return None

    def _parse_dml_dql(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        part1 = self._parse_dml_dql_part(upper_sql, sql)
        if part1 is not None:
            return part1
        if upper_sql.startswith("UPDATE"):
            return self._parse_update(sql)
        if upper_sql.startswith("DELETE FROM"):
            return self._parse_delete(sql)
        return None

    def _parse_schema_mount_ops(
        self, upper_sql: str, sql: str
    ) -> Optional[SQLStatement]:
        if upper_sql.startswith("ATTACH"):
            return _parse_attach_stmt(sql)
        if upper_sql.startswith("DETACH"):
            return _parse_detach_stmt(sql)
        return None

    def _parse_admin_ops(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("PRAGMA"):
            return _parse_pragma_stmt(sql)
        if upper_sql.startswith("VACUUM"):
            return _parse_vacuum_stmt(sql)
        if upper_sql.startswith("ANALYZE"):
            return _parse_analyze_stmt(sql)
        return self._parse_schema_mount_ops(upper_sql, sql)

    def _parse_dcl_stmt(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        if upper_sql.startswith("GRANT"):
            return self._parse_grant(sql)
        if upper_sql.startswith("REVOKE"):
            return self._parse_revoke(sql)
        return None

    def _parse_dcl_explain(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        sub_res = self._parse_admin_ops(upper_sql, sql) or self._parse_dcl_stmt(
            upper_sql, sql
        )
        if sub_res is not None:
            return sub_res
        if upper_sql.startswith("EXPLAIN"):
            return self._parse_explain(sql)
        if upper_sql.startswith("SHOW"):
            return self._parse_show(sql)
        return None

    def _parse_show(self, sql: str) -> SQLStatement:
        upper_sql = sql.upper().strip()
        target = _resolve_show_target(upper_sql)

        from_m = re.search(r"FROM\s+([a-zA-Z0-9_]+)", sql, re.IGNORECASE)
        from_db = from_m.group(1) if from_m else None

        like_m = re.search(r"LIKE\s+['\"](.*?)['\"]", sql, re.IGNORECASE)
        like_pat = like_m.group(1) if like_m else None

        return ShowStatement(
            command_type=SQLCommandType.SHOW,
            raw_sql=sql,
            target=target,
            from_database=from_db,
            like_pattern=like_pat,
        )

    def _parse_ddl_dml(self, upper_sql: str, sql: str) -> Optional[SQLStatement]:
        return (
            self._parse_dcl_explain(upper_sql, sql)
            or self._parse_ddl(upper_sql, sql)
            or self._parse_dml_dql(upper_sql, sql)
        )

    def parse(self, sql_query: str) -> SQLStatement:
        sql = sql_query.strip().rstrip(";")
        if not sql:
            raise SQLParseError("Empty SQL query")

        upper_sql = sql.upper()
        tcl_stmt = self._parse_tcl(upper_sql, sql)
        if tcl_stmt is not None:
            return tcl_stmt

        stmt = self._parse_ddl_dml(upper_sql, sql)
        if stmt is not None:
            return stmt

        raise SQLParseError(f"Unsupported or unrecognized SQL statement: '{sql}'")

    def _parse_explain(self, sql: str) -> ExplainStatement:
        m = re.match(
            r"^EXPLAIN(\s+QUERY\s+PLAN)?\s+(.*)$", sql, re.IGNORECASE | re.DOTALL
        )
        if not m:
            raise SQLParseError(f"Malformed EXPLAIN syntax: {sql}")
        query_plan = bool(m.group(1))
        sub_sql = m.group(2).strip()
        sub_stmt = self.parse(sub_sql)
        return ExplainStatement(
            command_type=SQLCommandType.EXPLAIN,
            raw_sql=sql,
            statement=sub_stmt,
            query_plan=query_plan,
        )

    def _parse_column_def(self, raw_col: str) -> Optional[ColumnDef]:
        """Parses a single column definition within CREATE TABLE."""
        raw_col = raw_col.strip()
        if not raw_col:
            return None
        parts = raw_col.split()
        c_name = parts[0]
        cleaned_col, collate = _extract_collate_from_col_def(raw_col)
        cleaned_col, gen_expr, is_stored = _extract_generated_column_info(
            cleaned_col, c_name
        )
        c_parts = cleaned_col.split()
        c_type = c_parts[1] if len(c_parts) > 1 else "TEXT"
        is_pk = "PRIMARY KEY" in cleaned_col.upper()
        is_nullable = "NOT NULL" not in cleaned_col.upper()
        return ColumnDef(
            name=c_name,
            data_type=c_type,
            is_primary_key=is_pk,
            is_nullable=is_nullable,
            generated_expr=gen_expr,
            is_stored=is_stored,
            collate=collate,
        )

    def _parse_create_table(self, sql: str) -> CreateTableStatement:
        cleaned_sql, engine, location = _extract_storage_clauses(sql)
        pattern = r"^CREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_.]+)\s*\((.*)\)\s*(.*)$"
        m = re.match(pattern, cleaned_sql, re.IGNORECASE | re.DOTALL)
        if not m:
            raise SQLParseError(f"Malformed CREATE TABLE syntax: {sql}")

        if_not_exists = bool(m.group(1))
        table_name = m.group(2)
        cols_body = m.group(3).strip()
        table_options = m.group(4).strip()
        strict = bool(re.search(r"\bSTRICT\b", table_options, re.IGNORECASE))

        col_defs = [
            c_def
            for raw_col in _split_column_defs(cols_body)
            if (c_def := self._parse_column_def(raw_col)) is not None
        ]
        if strict:
            _validate_strict_columns(col_defs)

        return CreateTableStatement(
            command_type=SQLCommandType.CREATE_TABLE,
            raw_sql=sql,
            table_name=table_name,
            columns=col_defs,
            if_not_exists=if_not_exists,
            storage_engine=engine,
            location=location,
            strict=strict,
        )

    def _parse_drop_table(self, sql: str) -> DropTableStatement:
        m = re.match(
            r"DROP\s+TABLE\s+(IF\s+EXISTS\s+)?([a-zA-Z0-9_.]+)",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed DROP TABLE syntax: {sql}")

        if_exists = bool(m.group(1))
        table_name = m.group(2)
        return DropTableStatement(
            command_type=SQLCommandType.DROP_TABLE,
            raw_sql=sql,
            table_name=table_name,
            if_exists=if_exists,
        )

    def _parse_create_index(self, sql: str) -> CreateIndexStatement:
        m = re.match(
            r"CREATE\s+INDEX\s+([a-zA-Z0-9_]+)\s+ON\s+([a-zA-Z0-9_]+)"
            r"\s*\(([a-zA-Z0-9_]+)\)(\s+USING\s+([a-zA-Z0-9_]+))?",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed CREATE INDEX syntax: {sql}")

        idx_name = m.group(1)
        table_name = m.group(2)
        col_name = m.group(3)
        idx_type = m.group(5) or "HNSW"

        return CreateIndexStatement(
            command_type=SQLCommandType.CREATE_INDEX,
            raw_sql=sql,
            index_name=idx_name,
            table_name=table_name,
            column_name=col_name,
            index_type=idx_type.upper(),
        )

    def _parse_alter_table(self, sql: str) -> AlterTableStatement:
        res = (
            _parse_alter_rename_table(sql)
            or _parse_alter_rename_column(sql)
            or _parse_alter_add_column(sql, self)
            or _parse_alter_drop_column(sql)
        )
        if res is not None:
            return res
        raise SQLParseError(f"Malformed ALTER TABLE syntax: {sql}")

    def _parse_drop_index(self, sql: str) -> DropIndexStatement:
        m = re.match(
            r"^DROP\s+INDEX\s+(IF\s+EXISTS\s+)?([a-zA-Z0-9_]+)$",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed DROP INDEX syntax: {sql}")
        return DropIndexStatement(
            command_type=SQLCommandType.DROP_INDEX,
            raw_sql=sql,
            index_name=m.group(2),
            if_exists=bool(m.group(1)),
        )

    def _parse_reindex(self, sql: str) -> ReindexStatement:
        m = re.match(r"^REINDEX(?:\s+([a-zA-Z0-9_]+))?$", sql, re.IGNORECASE)
        if not m:
            raise SQLParseError(f"Malformed REINDEX syntax: {sql}")
        return ReindexStatement(
            command_type=SQLCommandType.REINDEX,
            raw_sql=sql,
            target_name=m.group(1),
        )

    def _parse_create_view(self, sql: str) -> CreateViewStatement:
        m = re.match(
            r"^CREATE\s+VIEW\s+(IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_]+)\s+AS\s+(.*)$",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed CREATE VIEW syntax: {sql}")
        return CreateViewStatement(
            command_type=SQLCommandType.CREATE_VIEW,
            raw_sql=sql,
            view_name=m.group(2),
            select_stmt=self.parse(m.group(3).strip()),
            if_not_exists=bool(m.group(1)),
        )

    def _parse_drop_view(self, sql: str) -> DropViewStatement:
        m = re.match(
            r"^DROP\s+VIEW\s+(IF\s+EXISTS\s+)?([a-zA-Z0-9_]+)$",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed DROP VIEW syntax: {sql}")
        return DropViewStatement(
            command_type=SQLCommandType.DROP_VIEW,
            raw_sql=sql,
            view_name=m.group(2),
            if_exists=bool(m.group(1)),
        )

    def _find_matching_paren(self, text: str, start_pos: int) -> int:
        paren_depth = 1
        for idx in range(start_pos, len(text)):
            ch = text[idx]
            paren_depth += 1 if ch == "(" else (-1 if ch == ")" else 0)
            if paren_depth == 0:
                return idx + 1
        raise SQLParseError("Unbalanced parentheses in subquery definition")

    def _extract_single_cte(
        self, rest: str, is_recursive: bool
    ) -> Optional[Tuple[CTEDefinition, str]]:
        cte_head_m = re.match(
            r"^([a-zA-Z0-9_]+)(?:\s*\((.*?)\))?\s+AS\s*\(", rest, re.IGNORECASE
        )
        if not cte_head_m:
            return None

        cte_name = cte_head_m.group(1)
        raw_cols = cte_head_m.group(2)
        cols = [c.strip() for c in raw_cols.split(",")] if raw_cols else []

        start_pos = cte_head_m.end()
        end_pos = self._find_matching_paren(rest, start_pos)
        sub_query_sql = rest[start_pos : end_pos - 1].strip()
        sub_stmt = self._parse_select(sub_query_sql)

        cte_def = CTEDefinition(
            name=cte_name,
            statement=sub_stmt,
            columns=cols,
            is_recursive=is_recursive,
        )

        remaining = rest[end_pos:].strip()
        if remaining.startswith(","):
            remaining = remaining[1:].strip()
        return cte_def, remaining

    def _parse_cte(self, sql: str) -> SelectStatement:
        """
        Parses WITH [RECURSIVE] name [(cols...)] AS (SELECT ...) [, ...] SELECT ...
        """
        is_recursive = bool(re.match(r"^WITH\s+RECURSIVE\s+", sql, re.IGNORECASE))
        header_match = re.match(r"^WITH(\s+RECURSIVE)?\s+", sql, re.IGNORECASE)
        if not header_match:
            raise SQLParseError(f"Malformed WITH syntax: {sql}")

        rest = sql[header_match.end() :].strip()
        ctes: List[CTEDefinition] = []

        while True:
            res = self._extract_single_cte(rest, is_recursive)
            if not res:
                break
            cte_def, rest = res
            ctes.append(cte_def)

        if not rest.upper().startswith("SELECT"):
            raise SQLParseError(
                f"Expected SELECT query following CTE definitions, got: {rest}"
            )

        main_stmt = self._parse_select(rest)
        main_stmt.ctes = ctes
        main_stmt.raw_sql = sql
        return main_stmt

    @staticmethod
    def _assign_compound_stmt(
        left_stmt: SelectStatement, op: str, right_stmt: SelectStatement
    ) -> None:
        if op == "UNION ALL":
            left_stmt.union_all = right_stmt
        elif op == "UNION":
            left_stmt.union = right_stmt
        elif op == "INTERSECT":
            left_stmt.intersect = right_stmt
        elif op == "EXCEPT":
            left_stmt.except_ = right_stmt

    def _parse_select(self, sql: str) -> SelectStatement:
        union_split = self._split_top_level_union(sql)
        if union_split:
            left_sql, op, right_sql = union_split
            left_stmt = self._parse_single_select(left_sql)
            right_stmt = self._parse_select(right_sql)
            self._assign_compound_stmt(left_stmt, op, right_stmt)
            return left_stmt

        return self._parse_single_select(sql)

    def _check_union_at_pos(self, sql: str, i: int) -> Optional[Tuple[str, str, str]]:
        """Checks for compound operator match at index i."""
        for pat, op_name in (
            (r"^\s+UNION\s+ALL\s+", "UNION ALL"),
            (r"^\s+UNION\s+", "UNION"),
            (r"^\s+INTERSECT\s+", "INTERSECT"),
            (r"^\s+EXCEPT\s+", "EXCEPT"),
        ):
            m = re.match(pat, sql[i:], re.IGNORECASE)
            if m:
                left_part = sql[:i].strip()
                right_part = sql[i + m.end() :].strip()
                return left_part, op_name, right_part
        return None

    def _update_depth_and_check(
        self, sql: str, i: int, char: str, paren_depth: int
    ) -> Tuple[int, Optional[Tuple[str, str, str]]]:
        """Updates paren_depth and checks for compound op at position i."""
        if char == "(":
            return paren_depth + 1, None
        if char == ")":
            return paren_depth - 1, None
        if paren_depth == 0:
            return 0, self._check_union_at_pos(sql, i)
        return paren_depth, None

    def _split_top_level_union(self, sql: str) -> Optional[Tuple[str, str, str]]:
        paren_depth = 0
        for i, char in enumerate(sql):
            paren_depth, match = self._update_depth_and_check(sql, i, char, paren_depth)
            if match is not None:
                return match
        return None

    @staticmethod
    def _extract_limit_and_offset(
        clean_sql: str,
    ) -> Tuple[str, Optional[int], Optional[int]]:
        """Extracts and strips LIMIT and OFFSET values."""
        return _extract_limit_and_offset(clean_sql)

    def _extract_order_by_clause(
        self, clean_sql: str
    ) -> Tuple[str, Optional[str], bool, Optional[str]]:
        """Extracts and strips ORDER BY clause (supports COLLATE and multiple keys)."""
        pos = _find_top_level_keyword_pos(clean_sql, r"ORDER\s+BY")
        if not pos:
            return clean_sql, None, False, None
        k_start, k_end = pos
        first_item = clean_sql[k_end:].strip().split(",")[0].strip()
        collate: Optional[str] = None
        m_col = re.search(r"\bCOLLATE\s+([a-zA-Z0-9_]+)\b", first_item, re.IGNORECASE)
        if m_col:
            collate = _validate_collation(m_col.group(1))
            first_item = (
                first_item[: m_col.start()] + first_item[m_col.end() :]
            ).strip()
        parts = first_item.split()
        order_by = parts[0] if parts else None
        order_desc = len(parts) > 1 and parts[1].upper() == "DESC"
        return clean_sql[:k_start].strip(), order_by, order_desc, collate

    def _extract_having_clause(self, clean_sql: str) -> Tuple[str, Optional[str]]:
        """Extracts and strips HAVING condition."""
        pos = _find_top_level_keyword_pos(clean_sql, r"HAVING")
        if not pos:
            return clean_sql, None
        k_start, k_end = pos
        return clean_sql[:k_start].strip(), clean_sql[k_end:].strip()

    def _extract_group_by_clause(self, clean_sql: str) -> Tuple[str, List[str]]:
        """Extracts and strips GROUP BY columns."""
        pos = _find_top_level_keyword_pos(clean_sql, r"GROUP\s+BY")
        if not pos:
            return clean_sql, []
        k_start, k_end = pos
        cols = [c.strip() for c in clean_sql[k_end:].strip().split(",") if c.strip()]
        return clean_sql[:k_start].strip(), cols

    def _extract_where_clause(self, clean_sql: str) -> Tuple[str, Optional[str]]:
        """Extracts and strips WHERE condition."""
        pos = _find_top_level_keyword_pos(clean_sql, r"WHERE")
        if not pos:
            return clean_sql, None
        k_start, k_end = pos
        return clean_sql[:k_start].strip(), clean_sql[k_end:].strip()

    def _extract_knn_query(
        self, where_raw: str
    ) -> Tuple[str, Optional[Dict[str, Any]]]:
        """Extracts KNN function and cleans where_raw string."""
        knn_m = re.search(
            r"KNN\s*\(\s*([a-zA-Z0-9_\.]+)\s*,\s*(\[.*?\])\s*,\s*([0-9]+)\s*\)",
            where_raw,
            re.IGNORECASE,
        )
        if not knn_m:
            return where_raw, None

        knn_col = knn_m.group(1)
        try:
            knn_vec = py_ast.literal_eval(knn_m.group(2))
        except Exception as e:
            raise SQLParseError(f"Invalid vector in KNN clause: {e}") from e
        top_k = int(knn_m.group(3))
        knn_query = {
            "column": knn_col,
            "vector": [float(x) for x in knn_vec],
            "top_k": top_k,
        }
        cleaned_raw = where_raw.replace(knn_m.group(0), "").strip()
        cleaned_raw = re.sub(
            r"^(AND|OR)\s+", "", cleaned_raw, flags=re.IGNORECASE
        ).strip()
        cleaned_raw = re.sub(
            r"\s+(AND|OR)$", "", cleaned_raw, flags=re.IGNORECASE
        ).strip()
        return cleaned_raw, knn_query

    def _parse_standalone_values(
        self,
        raw_sql: str,
        clean_sql: str,
        order_by: Optional[str],
        order_desc: bool,
        order_collate: Optional[str],
        limit_val: Optional[int],
        offset_val: Optional[int],
    ) -> SelectStatement:
        rows = _extract_values_rows(self, raw_sql, clean_sql)
        columns = _generate_default_column_names(rows)
        return SelectStatement(
            command_type=SQLCommandType.SELECT,
            raw_sql=raw_sql,
            table_name="",
            columns=columns,
            values_rows=rows,
            order_by=order_by,
            order_desc=order_desc,
            order_collate=order_collate,
            limit=limit_val,
            offset=offset_val,
        )

    def _parse_single_select(self, sql: str) -> SelectStatement:
        clean_sql = re.sub(r"\s+", " ", sql).strip()
        clean_sql, limit_val, offset_val = self._extract_limit_and_offset(clean_sql)
        clean_sql, order_by, order_desc, order_collate = self._extract_order_by_clause(
            clean_sql
        )
        if re.match(r"^VALUES\s*\(", clean_sql, re.IGNORECASE):
            return self._parse_standalone_values(
                sql,
                clean_sql,
                order_by,
                order_desc,
                order_collate,
                limit_val,
                offset_val,
            )
        clean_sql, having_raw = self._extract_having_clause(clean_sql)
        clean_sql, group_by_cols = self._extract_group_by_clause(clean_sql)
        clean_sql, where_raw = self._extract_where_clause(clean_sql)

        from_pos = _find_top_level_keyword_pos(clean_sql, r"FROM")
        if not from_pos:
            raise SQLParseError(f"Malformed SELECT syntax: {sql}")
        f_start, f_end = from_pos
        select_prefix = clean_sql[:f_start].strip()
        m_sel = re.match(r"^SELECT\s+(.+)$", select_prefix, re.IGNORECASE | re.DOTALL)
        if not m_sel:
            raise SQLParseError(f"Malformed SELECT syntax: {sql}")

        cols_raw, distinct = _extract_distinct_prefix(m_sel.group(1).strip())
        columns = self._parse_column_list(cols_raw)
        table_ref, joins = self._parse_from_and_joins(clean_sql[f_end:].strip())

        where_clauses: List[Dict[str, Any]] = []
        knn_query: Optional[Dict[str, Any]] = None

        if where_raw:
            where_raw, knn_query = self._extract_knn_query(where_raw)
            where_clauses.extend(self._extract_where_clauses(where_raw))

        return SelectStatement(
            command_type=SQLCommandType.SELECT,
            raw_sql=sql,
            table_name=table_ref.name,
            table_ref=table_ref,
            columns=columns,
            where_clauses=where_clauses,
            knn_query=knn_query,
            joins=joins,
            order_by=order_by,
            order_desc=order_desc,
            order_collate=order_collate,
            limit=limit_val,
            offset=offset_val,
            distinct=distinct,
            group_by=group_by_cols,
            having=having_raw,
        )

    def _parse_column_list(self, cols_raw: str) -> List[str]:
        """Parses comma-separated column projections respecting parentheses and quotes."""
        if cols_raw == "*":
            return ["*"]
        return _split_comma_expressions(cols_raw)

    def _resolve_join_type(self, join_kw: str) -> JoinType:
        """Resolves JoinType enum from join keyword."""
        if "LEFT" in join_kw:
            return JoinType.LEFT
        if "RIGHT" in join_kw:
            return JoinType.RIGHT
        if "CROSS" in join_kw:
            return JoinType.CROSS
        return JoinType.INNER

    def _parse_join_part(self, join_kw: str, join_body: str) -> JoinClause:
        """Parses target table and ON conditions for a single JOIN clause."""
        join_type = self._resolve_join_type(join_kw)
        on_m = re.search(r"\s+ON\s+(.+)$", join_body, re.IGNORECASE)
        if not on_m:
            target_table_ref = self._parse_single_table_ref(join_body)
            return JoinClause(
                join_type=join_type, table=target_table_ref, on_conditions=[]
            )
        tbl_part = join_body[: on_m.start()].strip()
        target_table_ref = self._parse_single_table_ref(tbl_part)
        on_conds = self._extract_simple_clauses(on_m.group(1).strip())
        return JoinClause(
            join_type=join_type, table=target_table_ref, on_conditions=on_conds
        )

    def _parse_from_and_joins(self, from_raw: str) -> Tuple[TableRef, List[JoinClause]]:
        """Parses FROM table [AS alias] [JOIN table2 [AS alias2] ON cond1 = cond2 ...]"""
        join_regex = r"\s+(INNER\s+JOIN|LEFT\s+OUTER\s+JOIN|LEFT\s+JOIN|RIGHT\s+JOIN|CROSS\s+JOIN|JOIN)\s+"
        parts = re.split(join_regex, from_raw, flags=re.IGNORECASE)

        table_ref = self._parse_single_table_ref(parts[0].strip())
        joins: List[JoinClause] = []
        idx = 1
        while idx < len(parts):
            join_kw = parts[idx].strip().upper()
            join_body = parts[idx + 1].strip()
            idx += 2
            joins.append(self._parse_join_part(join_kw, join_body))

        return table_ref, joins

    def _parse_single_table_ref(self, text: str) -> TableRef:
        clean_tbl, indexed_by, not_indexed = _extract_index_hint(text)
        m = re.match(
            r"^([a-zA-Z0-9_.]+)(?:\s+(?:AS\s+)?([a-zA-Z0-9_]+))?$",
            clean_tbl.strip(),
            re.IGNORECASE,
        )
        if not m:
            return TableRef(
                name=clean_tbl.strip(),
                indexed_by=indexed_by,
                not_indexed=not_indexed,
            )
        return TableRef(
            name=m.group(1),
            alias=m.group(2),
            indexed_by=indexed_by,
            not_indexed=not_indexed,
        )

    def _extract_where_clauses(self, where_raw: str) -> List[Dict[str, Any]]:
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

    def _parse_insert_values(self, vals_raw: str) -> List[Any]:
        """Safely parses literal values using python ast or fallback split."""
        try:
            parsed_tuple = py_ast.literal_eval(f"({vals_raw})")
            if not isinstance(parsed_tuple, tuple):
                return [parsed_tuple]
            return list(parsed_tuple)
        except Exception:
            return [v.strip().strip("'\"") for v in vals_raw.split(",")]

    def _parse_insert_select_stmt(
        self,
        sql: str,
        returning_cols: Optional[List[str]],
        upsert_target: Optional[List[str]],
        upsert_action: Optional[str],
        upsert_update_set: Dict[str, Any],
    ) -> Optional[InsertStatement]:
        m_sel = re.match(
            r"^(?:INSERT|REPLACE)\s+INTO\s+([a-zA-Z0-9_]+)(?:\s*\((.*?)\))?\s+(SELECT\s+.+)$",
            sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m_sel:
            return None
        tbl = m_sel.group(1).strip()
        cols = [c.strip() for c in m_sel.group(2).split(",")] if m_sel.group(2) else []
        sel_stmt = self._parse_select(m_sel.group(3).strip())
        return InsertStatement(
            command_type=SQLCommandType.INSERT,
            raw_sql=sql,
            table_name=tbl,
            columns=cols,
            select_stmt=sel_stmt,
            upsert_target=upsert_target,
            upsert_action=upsert_action,
            upsert_update_set=upsert_update_set,
            returning_cols=returning_cols,
        )

    def _parse_insert_rows(
        self, raw_vals_body: str, cols_count: int
    ) -> List[List[Any]]:
        tuples = _extract_values_tuples(raw_vals_body)
        rows: List[List[Any]] = []
        for t in tuples:
            vals = self._parse_insert_values(t)
            if cols_count and len(vals) != cols_count:
                raise SQLParseError(
                    f"Column count ({cols_count}) does not match values count ({len(vals)})"
                )
            rows.append(vals)
        return rows

    @staticmethod
    def _resolve_upsert_action(clean_sql: str, up_act: Optional[str]) -> Optional[str]:
        if re.match(r"^REPLACE\s+INTO", clean_sql, re.IGNORECASE):
            return up_act or "UPDATE"
        return up_act

    @staticmethod
    def _split_insert_cols(raw_cols: Optional[str]) -> List[str]:
        if not raw_cols:
            return []
        return [c.strip() for c in raw_cols.split(",")]

    def _parse_insert(self, sql: str) -> InsertStatement:
        clean_sql, ret_cols = _extract_returning_clause(sql)
        clean_sql, up_tgt, up_act, up_set = _extract_upsert_clause(clean_sql)
        up_act = self._resolve_upsert_action(clean_sql, up_act)

        sel_res = self._parse_insert_select_stmt(
            clean_sql, ret_cols, up_tgt, up_act, up_set
        )
        if sel_res is not None:
            return sel_res

        m = re.match(
            r"^(?:INSERT|REPLACE)\s+INTO\s+([a-zA-Z0-9_.]+)(?:\s*\((.*?)\))?\s+VALUES\s*(.+)$",
            clean_sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed INSERT syntax: {sql}")

        tbl = m.group(1).strip()
        cols = self._split_insert_cols(m.group(2))
        rows = self._parse_insert_rows(m.group(3).strip(), len(cols))
        first_val = rows[0] if rows else []
        return InsertStatement(
            command_type=SQLCommandType.INSERT,
            raw_sql=sql,
            table_name=tbl,
            columns=cols,
            values=first_val,
            rows_values=rows,
            upsert_target=up_tgt,
            upsert_action=up_act,
            upsert_update_set=up_set,
            returning_cols=ret_cols,
        )

    def _parse_update(self, sql: str) -> UpdateStatement:
        clean_sql, ret_cols = _extract_returning_clause(sql)
        clean_sql, order_col, order_desc, limit_val = _extract_dml_order_and_limit(
            clean_sql
        )
        clean_sql, where_raw = self._extract_where_clause(clean_sql)
        where_clauses = self._extract_where_clauses(where_raw) if where_raw else []

        from_table: Optional[TableRef] = None
        joins: List[JoinClause] = []
        from_pos = _find_top_level_keyword_pos(clean_sql, r"FROM")
        if from_pos:
            f_start, f_end = from_pos
            from_body = clean_sql[f_end:].strip()
            from_table, joins = self._parse_from_and_joins(from_body)
            clean_sql = clean_sql[:f_start].strip()

        m = re.match(
            r"UPDATE\s+(.+?)\s+SET\s+(.+)$",
            clean_sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed UPDATE syntax: {sql}")

        table_name, indexed_by, not_indexed = _extract_index_hint(m.group(1).strip())
        assignments, raw_assignments = _parse_set_assignments(m.group(2).strip())

        return UpdateStatement(
            command_type=SQLCommandType.UPDATE,
            raw_sql=sql,
            table_name=table_name,
            assignments=assignments,
            raw_assignments=raw_assignments,
            from_table=from_table,
            joins=joins,
            where_clauses=where_clauses,
            returning_cols=ret_cols,
            order_by=order_col,
            order_desc=order_desc,
            limit=limit_val,
            indexed_by=indexed_by,
            not_indexed=not_indexed,
        )

    def _parse_delete(self, sql: str) -> DeleteStatement:
        clean_sql, ret_cols = _extract_returning_clause(sql)
        clean_sql, order_col, order_desc, limit_val = _extract_dml_order_and_limit(
            clean_sql
        )
        m = re.match(
            r"DELETE\s+FROM\s+(.+?)(?:\s+WHERE\s+(.+))?$",
            clean_sql,
            re.IGNORECASE | re.DOTALL,
        )
        if not m:
            raise SQLParseError(f"Malformed DELETE syntax: {sql}")

        table_name, indexed_by, not_indexed = _extract_index_hint(m.group(1).strip())
        where_raw = m.group(2)
        where_clauses = self._extract_where_clauses(where_raw) if where_raw else []

        return DeleteStatement(
            command_type=SQLCommandType.DELETE,
            raw_sql=sql,
            table_name=table_name,
            where_clauses=where_clauses,
            returning_cols=ret_cols,
            order_by=order_col,
            order_desc=order_desc,
            limit=limit_val,
            indexed_by=indexed_by,
            not_indexed=not_indexed,
        )

    def _parse_grant(self, sql: str) -> GrantStatement:
        m = re.match(
            r"GRANT\s+(.+?)(?:\s+ON\s+([a-zA-Z0-9_\*]+))?\s+TO\s+([a-zA-Z0-9_]+)$",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed GRANT syntax: {sql}")

        perm = m.group(1).strip().upper()
        if perm in ("ALL PRIVILEGES", "ALL"):
            perm = "ALL"
        table_name = m.group(2) or "*"
        role_name = m.group(3).strip()

        return GrantStatement(
            command_type=SQLCommandType.GRANT,
            raw_sql=sql,
            permission=perm,
            table_name=table_name,
            role=role_name,
        )

    def _parse_revoke(self, sql: str) -> RevokeStatement:
        m = re.match(
            r"REVOKE\s+([a-zA-Z0-9_]+)\s+ON\s+([a-zA-Z0-9_]+)\s+FROM\s+([a-zA-Z0-9_]+)",
            sql,
            re.IGNORECASE,
        )
        if not m:
            raise SQLParseError(f"Malformed REVOKE syntax: {sql}")

        return RevokeStatement(
            command_type=SQLCommandType.REVOKE,
            raw_sql=sql,
            permission=m.group(1).upper(),
            table_name=m.group(2),
            role=m.group(3),
        )
