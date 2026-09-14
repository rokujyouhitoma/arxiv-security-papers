#!/usr/bin/env python3
"""
Pure Python Packrat PEG Parser for SQL DDL Statements.
Parses CREATE TABLE/VIEW/INDEX/TRIGGER/VIRTUAL TABLE, ALTER TABLE, DROP, REINDEX
into typed AST objects without external dependencies.
"""

from __future__ import annotations

import re
from typing import Any, List, Optional, Tuple, cast

from core.structures.peg import (
    Choice,
    Opt,
    Parser,
    PEGSyntaxError,
    Regex,
    Seq,
    ZeroOrMore,
)

from .ast import (
    AlterTableAction,
    AlterTableStatement,
    ColumnDef,
    CreateIndexStatement,
    CreateTableStatement,
    CreateTriggerStatement,
    CreateViewStatement,
    CreateVirtualTableStatement,
    DropIndexStatement,
    DropTableStatement,
    DropTriggerStatement,
    DropViewStatement,
    ForeignKeyDef,
    ReindexStatement,
    SQLCommandType,
    SQLStatement,
)
from .dql_parser import parse_dql

ALLOWED_STRICT_TYPES = {"INT", "INTEGER", "REAL", "TEXT", "BLOB", "ANY"}


def _tok(p: Parser[Any]) -> Parser[Any]:
    ws = Regex(r"(\s+|#[^\r\n]*|--[^\r\n]*)*")
    return Seq(p, ws).map(lambda r: r[0])


def _kw(word: str) -> Parser[str]:
    return _tok(Regex(rf"(?i)\b{re.escape(word)}\b"))


def _ident_p() -> Parser[str]:
    p = Regex(
        r"(?:[a-zA-Z0-9_]+\.)?[a-zA-Z_][a-zA-Z0-9_]*|\`[^\`]+\`|\[[^\]]+\]|\"[^\"]+\"|[a-zA-Z0-9_.]+"
    )
    return _tok(p).map(lambda s: s.strip('`[]"'))


def _str_lit_p() -> Parser[str]:
    return _tok(Regex(r"'([^']*)'|\"([^\"]*)\"")).map(
        lambda s: s[1:-1] if len(s) >= 2 else s
    )


def _int_lit_p() -> Parser[int]:
    return _tok(Regex(r"-?\d+")).map(int)


def _float_lit_p() -> Parser[float]:
    return _tok(Regex(r"-?\d+\.\d+")).map(float)


def _paren_chunk_p() -> Parser[str]:
    return _tok(Regex(r"\((?:[^()]|\([^()]*\))*\)"))


_ALLOWED_ENGINES: set[str] = {
    "binary_vdb",
    "json_lines",
    "json_table",
    "file_plain_text",
    "fts5",
    "csv_table",
    "csv",
}


def _validate_storage_engine(engine: Optional[str]) -> Optional[str]:
    if not engine:
        return None
    from .parser import SQLParseError

    clean = engine.strip().lower()
    if clean not in _ALLOWED_ENGINES:
        allowed = ", ".join(sorted(_ALLOWED_ENGINES))
        raise SQLParseError(
            f"Unsupported storage engine: '{engine}'. Allowed: [{allowed}]"
        )
    return clean


def _validate_strict_columns(columns: List[ColumnDef]) -> None:
    from .parser import SQLParseError

    for col in columns:
        dt = col.data_type.strip().upper()
        if dt not in ALLOWED_STRICT_TYPES:
            raise SQLParseError(
                f"Unknown datatype for {col.name} in STRICT table: {col.data_type}"
            )


# -------------------------------------------------------------------------
# Column Definition & Constraints
# -------------------------------------------------------------------------


def _build_fk_actions_parser() -> Parser[Tuple[str, str]]:
    def _action_for(event: str) -> Parser[str]:
        act = Choice(
            _kw("CASCADE"),
            Seq(_kw("SET"), _kw("NULL")).map(lambda _: "SET NULL"),
            _kw("RESTRICT"),
            Seq(_kw("NO"), _kw("ACTION")).map(lambda _: "NO ACTION"),
            Seq(_kw("SET"), _kw("DEFAULT")).map(lambda _: "SET DEFAULT"),
        )
        return Seq(_kw("ON"), _kw(event), act).map(lambda r: str(r[2]))

    del_p = _action_for("DELETE")
    upd_p = _action_for("UPDATE")
    either = Choice(
        del_p.map(lambda a: ("del", a)),
        upd_p.map(lambda a: ("upd", a)),
    )
    return ZeroOrMore(either).map(_merge_fk_actions)


def _merge_fk_actions(actions: List[Tuple[str, str]]) -> Tuple[str, str]:
    on_del = "NO ACTION"
    on_upd = "NO ACTION"
    for kind, act in actions:
        if kind == "del":
            on_del = act
        elif kind == "upd":
            on_upd = act
    return on_del, on_upd


def _build_column_fk_parser(c_name: str) -> Parser[ForeignKeyDef]:
    actions_p = _build_fk_actions_parser()
    return Seq(
        _kw("REFERENCES"),
        _ident_p(),
        Opt(_paren_chunk_p()),
        actions_p,
    ).map(
        lambda r: ForeignKeyDef(
            child_column=c_name,
            parent_table=str(r[1]),
            parent_column=str(r[2]).strip("()") if r[2] else c_name,
            on_delete=cast(Tuple[str, str], r[3])[0],
            on_update=cast(Tuple[str, str], r[3])[1],
        )
    )


def _build_table_fk_parser() -> Parser[ForeignKeyDef]:
    actions_p = _build_fk_actions_parser()
    return Seq(
        Opt(Seq(_kw("CONSTRAINT"), _ident_p())),
        _kw("FOREIGN"),
        _kw("KEY"),
        _paren_chunk_p(),
        _kw("REFERENCES"),
        _ident_p(),
        Opt(_paren_chunk_p()),
        actions_p,
    ).map(
        lambda r: ForeignKeyDef(
            child_column=str(r[3]).strip("()").strip(),
            parent_table=str(r[5]),
            parent_column=(
                str(r[6]).strip("()").strip() if r[6] else str(r[3]).strip("()").strip()
            ),
            on_delete=cast(Tuple[str, str], r[7])[0],
            on_update=cast(Tuple[str, str], r[7])[1],
        )
    )


def _extract_col_nullability_and_keys(upper_c: str) -> Tuple[bool, bool, bool]:
    is_pk = "PRIMARY KEY" in upper_c
    is_unique = "UNIQUE" in upper_c or is_pk
    is_nullable = "NOT NULL" not in upper_c
    return is_pk, is_unique, is_nullable


def _extract_collate_from_raw(cleaned: str) -> Optional[str]:
    m_collate = re.search(r"\bCOLLATE\s+([a-zA-Z0-9_]+)\b", cleaned, re.IGNORECASE)
    return m_collate.group(1).upper() if m_collate else None


def _extract_generated_from_raw(
    cleaned: str, c_name: str
) -> Tuple[Optional[str], bool]:
    from .parser import SQLParseError

    gen_pattern = r"(?:GENERATED\s+ALWAYS\s+)?AS\s*\((.*?)\)(?:\s+(STORED|VIRTUAL))?"
    m_gen = re.search(gen_pattern, cleaned, re.IGNORECASE)
    if not m_gen:
        return None, False
    gen_expr = m_gen.group(1).strip()
    if re.search(rf"\b{re.escape(c_name)}\b", gen_expr):
        raise SQLParseError(f"Generated column '{c_name}' cannot refer to itself")
    is_stored = bool(m_gen.group(2) and m_gen.group(2).upper() == "STORED")
    return gen_expr, is_stored


def _resolve_raw_default_val(raw_val: Optional[str]) -> Any:
    if raw_val is None or raw_val.upper() == "NULL":
        return None
    if re.match(r"^-?\d+$", raw_val):
        return int(raw_val)
    if re.match(r"^-?\d+\.\d+$", raw_val):
        return float(raw_val)
    return raw_val


def _extract_default_from_raw(cleaned: str) -> Any:
    m_def = re.search(
        r"\s+DEFAULT\s+('([^']*)'|\"([^\"]*)\"|([a-zA-Z0-9_\.\-]+))",
        cleaned,
        re.IGNORECASE,
    )
    if not m_def:
        return None
    raw_val = m_def.group(2) or m_def.group(3) or m_def.group(4)
    return _resolve_raw_default_val(raw_val)


def _extract_fk_from_raw(cleaned: str, c_name: str) -> Optional[ForeignKeyDef]:
    m_fk = re.search(
        r"\bREFERENCES\s+([a-zA-Z0-9_.]+)(?:\s*\(([a-zA-Z0-9_]+)\))?(.*?)$",
        cleaned,
        re.IGNORECASE,
    )
    if not m_fk:
        return None
    parent_tbl = m_fk.group(1).strip()
    parent_col = m_fk.group(2).strip() if m_fk.group(2) else c_name
    rest = m_fk.group(3)
    on_del, on_upd = _extract_fk_actions_from_rest(rest)
    return ForeignKeyDef(
        child_column=c_name,
        parent_table=parent_tbl,
        parent_column=parent_col,
        on_delete=on_del,
        on_update=on_upd,
    )


def _extract_fk_actions_from_rest(rest: str) -> Tuple[str, str]:
    on_del = "NO ACTION"
    on_upd = "NO ACTION"
    m_del = re.search(
        r"\bON\s+DELETE\s+(CASCADE|SET\s+NULL|RESTRICT|NO\s+ACTION|SET\s+DEFAULT)\b",
        rest,
        re.IGNORECASE,
    )
    if m_del:
        on_del = re.sub(r"\s+", " ", m_del.group(1).upper())
    m_upd = re.search(
        r"\bON\s+UPDATE\s+(CASCADE|SET\s+NULL|RESTRICT|NO\s+ACTION|SET\s+DEFAULT)\b",
        rest,
        re.IGNORECASE,
    )
    if m_upd:
        on_upd = re.sub(r"\s+", " ", m_upd.group(1).upper())
    return on_del, on_upd


def _parse_col_constraints(
    c_name: str,
    raw_col: str,
) -> Tuple[
    bool, bool, bool, Optional[str], bool, Optional[str], Optional[ForeignKeyDef], Any
]:
    cleaned = raw_col
    upper_c = cleaned.upper()
    is_pk, is_unique, is_nullable = _extract_col_nullability_and_keys(upper_c)
    collate = _extract_collate_from_raw(cleaned)
    gen_expr, is_stored = _extract_generated_from_raw(cleaned, c_name)
    def_val = _extract_default_from_raw(cleaned)
    fk_def = _extract_fk_from_raw(cleaned, c_name)

    return is_pk, is_unique, is_nullable, gen_expr, is_stored, collate, fk_def, def_val


def _build_column_def_parser() -> Parser[Optional[ColumnDef]]:
    raw_col_p = Regex(r"[^,()]+(?:\((?:[^()]|\([^()]*\))*\)[^,()]*)*")
    return raw_col_p.map(_parse_single_column_def)


def _is_table_level_constraint(upper_s: str) -> bool:
    prefixes = ("PRIMARY KEY", "FOREIGN KEY", "UNIQUE", "CHECK", "CONSTRAINT")
    return upper_s.startswith(prefixes)


def _parse_single_column_def(raw: str) -> Optional[ColumnDef]:
    stripped = raw.strip()
    if not stripped or _is_table_level_constraint(stripped.upper()):
        return None

    parts = stripped.split(None, 2)
    c_name = parts[0].strip('`[]"')
    c_type = parts[1].upper() if len(parts) > 1 else "TEXT"
    (
        is_pk,
        is_uniq,
        is_null,
        gen_expr,
        is_stored,
        collate,
        fk_def,
        def_val,
    ) = _parse_col_constraints(c_name, stripped)

    return ColumnDef(
        name=c_name,
        data_type=c_type,
        is_primary_key=is_pk,
        is_unique=is_uniq,
        is_nullable=is_null,
        generated_expr=gen_expr,
        is_stored=is_stored,
        collate=collate,
        foreign_key=fk_def,
        default_value=def_val,
    )


def _extract_table_fk_def(ch: str) -> Optional[ForeignKeyDef]:
    if not re.match(r"^(?:CONSTRAINT\s+\S+\s+)?FOREIGN\s+KEY", ch, re.IGNORECASE):
        return None
    fk_pattern = (
        r"^(?:CONSTRAINT\s+\S+\s+)?FOREIGN\s+KEY\s*\(\s*([a-zA-Z0-9_]+)\s*\)\s*"
        r"REFERENCES\s+([a-zA-Z0-9_.]+)(?:\s*\(\s*([a-zA-Z0-9_]+)\s*\))?(.*)$"
    )
    m = re.match(fk_pattern, ch, re.IGNORECASE | re.DOTALL)
    if not m:
        return None
    c_col = m.group(1).strip()
    p_tbl = m.group(2).strip()
    p_col = m.group(3).strip() if m.group(3) else c_col
    on_del, on_upd = _extract_fk_actions_from_rest(m.group(4))
    return ForeignKeyDef(
        child_column=c_col,
        parent_table=p_tbl,
        parent_column=p_col,
        on_delete=on_del,
        on_update=on_upd,
    )


def _append_table_item(
    ch: str, cols: List[ColumnDef], fks: List[ForeignKeyDef]
) -> None:
    tbl_fk = _extract_table_fk_def(ch)
    if tbl_fk is not None:
        fks.append(tbl_fk)
        return
    c_def = _parse_single_column_def(ch)
    if c_def is not None:
        cols.append(c_def)
        if c_def.foreign_key is not None:
            fks.append(c_def.foreign_key)


def _split_table_items(body: str) -> Tuple[List[ColumnDef], List[ForeignKeyDef]]:
    cols: List[ColumnDef] = []
    fks: List[ForeignKeyDef] = []
    for chunk in _split_comma_top_level(body):
        ch = chunk.strip()
        if ch:
            _append_table_item(ch, cols, fks)
    return cols, fks


def _process_paren_depth_ddl(ch: str, depth: int) -> int:
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


def _process_comma_char_ddl(
    ch: str,
    depth: int,
    in_s: bool,
    in_d: bool,
    cur: List[str],
    res: List[str],
) -> Tuple[int, bool, bool]:
    in_s, in_d = _update_quote_flags(ch, in_s, in_d)
    if not in_s and not in_d:
        depth = _process_paren_depth_ddl(ch, depth)
        if ch == "," and depth == 0:
            res.append("".join(cur).strip())
            cur.clear()
            return depth, in_s, in_d
    cur.append(ch)
    return depth, in_s, in_d


def _split_comma_top_level(text: str) -> List[str]:
    res: List[str] = []
    cur: List[str] = []
    depth = 0
    in_s = False
    in_d = False

    for ch in text:
        depth, in_s, in_d = _process_comma_char_ddl(ch, depth, in_s, in_d, cur, res)

    if cur:
        res.append("".join(cur).strip())
    return res


# -------------------------------------------------------------------------
# Statement Parsers
# -------------------------------------------------------------------------


def _build_create_table_parser() -> Parser[CreateTableStatement]:
    prefix = Seq(
        _kw("CREATE"),
        Opt(Choice(_kw("TEMP"), _kw("TEMPORARY"))),
        _kw("TABLE"),
        Opt(Seq(_kw("IF"), _kw("NOT"), _kw("EXISTS"))),
        _ident_p(),
        _paren_chunk_p(),
        Regex(r".*"),
    )

    return prefix.map(_assemble_create_table)


def _assemble_create_table(r: List[Any]) -> CreateTableStatement:
    if_not_exists = bool(r[3])
    table_name = str(r[4])
    body = str(r[5]).strip()[1:-1]  # remove outer parens
    tail = str(r[6]).strip()

    strict = bool(re.search(r"\bSTRICT\b", tail, re.IGNORECASE))
    m_loc = re.search(r"\bLOCATION\s+['\"](.*?)['\"]", tail, re.IGNORECASE)
    location = m_loc.group(1).strip() if m_loc else None
    m_eng = re.search(r"\bUSING\s+([a-zA-Z0-9_]+)\b", tail, re.IGNORECASE)
    raw_engine = m_eng.group(1).strip() if m_eng else None
    engine = _validate_storage_engine(raw_engine)

    cols, fks = _split_table_items(body)
    if strict:
        _validate_strict_columns(cols)

    return CreateTableStatement(
        command_type=SQLCommandType.CREATE_TABLE,
        raw_sql="",
        table_name=table_name,
        columns=cols,
        if_not_exists=if_not_exists,
        storage_engine=engine,
        location=location,
        strict=strict,
        foreign_keys=fks,
    )


def _build_create_virtual_table_parser() -> Parser[CreateVirtualTableStatement]:
    prefix = Seq(
        _kw("CREATE"),
        _kw("VIRTUAL"),
        _kw("TABLE"),
        Opt(Seq(_kw("IF"), _kw("NOT"), _kw("EXISTS"))),
        _ident_p(),
        _kw("USING"),
        _ident_p(),
        Opt(_paren_chunk_p()),
    )
    return prefix.map(_assemble_create_virtual_table)


def _assemble_create_virtual_table(r: List[Any]) -> CreateVirtualTableStatement:
    if_not_exists = bool(r[3])
    tbl = str(r[4])
    module = str(r[6])
    args_raw = str(r[7]).strip()[1:-1] if r[7] else ""
    args = [a.strip() for a in _split_comma_top_level(args_raw) if a.strip()]

    return CreateVirtualTableStatement(
        command_type=SQLCommandType.CREATE_VIRTUAL_TABLE,
        raw_sql="",
        table_name=tbl,
        module_name=module,
        module_args=args,
        if_not_exists=if_not_exists,
    )


def _build_create_index_parser() -> Parser[CreateIndexStatement]:
    prefix = Seq(
        _kw("CREATE"),
        Opt(_kw("UNIQUE")),
        _kw("INDEX"),
        Opt(Seq(_kw("IF"), _kw("NOT"), _kw("EXISTS"))),
        _ident_p(),
        _kw("ON"),
        _ident_p(),
        _paren_chunk_p(),
        Opt(Seq(_kw("USING"), _ident_p())),
    )
    return prefix.map(_assemble_create_index)


def _assemble_create_index(r: List[Any]) -> CreateIndexStatement:
    idx_name = str(r[4])
    tbl_name = str(r[6])
    cols_body = str(r[7]).strip()[1:-1].strip()
    idx_type = str(r[8][1]).upper() if r[8] else "HNSW"

    return CreateIndexStatement(
        command_type=SQLCommandType.CREATE_INDEX,
        raw_sql="",
        index_name=idx_name,
        table_name=tbl_name,
        column_name=cols_body,
        index_type=idx_type,
    )


def _build_create_view_parser() -> Parser[CreateViewStatement]:
    prefix = Seq(
        _kw("CREATE"),
        Opt(Choice(_kw("TEMP"), _kw("TEMPORARY"))),
        _kw("VIEW"),
        Opt(Seq(_kw("IF"), _kw("NOT"), _kw("EXISTS"))),
        _ident_p(),
        _kw("AS"),
        Regex(r".*"),
    )
    return prefix.map(_assemble_create_view)


def _assemble_create_view(r: List[Any]) -> CreateViewStatement:
    if_not_exists = bool(r[3])
    view_name = str(r[4])
    select_raw = str(r[6]).strip()
    sub_select = parse_dql(select_raw)

    return CreateViewStatement(
        command_type=SQLCommandType.CREATE_VIEW,
        raw_sql="",
        view_name=view_name,
        select_stmt=sub_select,
        if_not_exists=if_not_exists,
    )


def _build_create_trigger_parser() -> Parser[CreateTriggerStatement]:
    timing_p = Choice(
        _kw("BEFORE"),
        _kw("AFTER"),
        Seq(_kw("INSTEAD"), _kw("OF")).map(lambda _: "INSTEAD OF"),
    )
    event_p = Choice(_kw("INSERT"), _kw("UPDATE"), _kw("DELETE"))
    prefix = Seq(
        _kw("CREATE"),
        Opt(Choice(_kw("TEMP"), _kw("TEMPORARY"))),
        _kw("TRIGGER"),
        Opt(Seq(_kw("IF"), _kw("NOT"), _kw("EXISTS"))),
        _ident_p(),
        timing_p,
        event_p,
        _kw("ON"),
        _ident_p(),
        Opt(Seq(_kw("FOR"), _kw("EACH"), _kw("ROW"))),
        _kw("BEGIN"),
        Regex(r"(?is).*?(?=\bEND\b)"),
        _kw("END"),
    )
    return prefix.map(_assemble_create_trigger)


def _assemble_create_trigger(r: List[Any]) -> CreateTriggerStatement:
    trg_name = str(r[4])
    timing = str(r[5]).upper()
    event = str(r[6]).upper()
    tbl_name = str(r[8])
    body_raw = str(r[11]).strip()
    body_sqls = [s.strip() for s in body_raw.split(";") if s.strip()]

    return CreateTriggerStatement(
        command_type=SQLCommandType.CREATE_TRIGGER,
        raw_sql="",
        trigger_name=trg_name,
        timing=timing,
        event=event,
        table_name=tbl_name,
        body_sqls=body_sqls,
    )


def _build_alter_table_parser() -> Parser[AlterTableStatement]:
    rename_table_p = Seq(
        _kw("ALTER"),
        _kw("TABLE"),
        _ident_p(),
        _kw("RENAME"),
        _kw("TO"),
        _ident_p(),
    ).map(
        lambda r: AlterTableStatement(
            command_type=SQLCommandType.ALTER_TABLE,
            raw_sql="",
            table_name=str(r[2]),
            action=AlterTableAction.RENAME_TABLE,
            new_table_name=str(r[5]),
        )
    )

    rename_col_p = Seq(
        _kw("ALTER"),
        _kw("TABLE"),
        _ident_p(),
        _kw("RENAME"),
        Opt(_kw("COLUMN")),
        _ident_p(),
        _kw("TO"),
        _ident_p(),
    ).map(
        lambda r: AlterTableStatement(
            command_type=SQLCommandType.ALTER_TABLE,
            raw_sql="",
            table_name=str(r[2]),
            action=AlterTableAction.RENAME_COLUMN,
            old_column_name=str(r[5]),
            new_column_name=str(r[7]),
        )
    )

    add_col_p = Seq(
        _kw("ALTER"),
        _kw("TABLE"),
        _ident_p(),
        _kw("ADD"),
        Opt(_kw("COLUMN")),
        Regex(r".*"),
    ).map(_assemble_alter_add_column)

    drop_col_p = Seq(
        _kw("ALTER"),
        _kw("TABLE"),
        _ident_p(),
        _kw("DROP"),
        Opt(_kw("COLUMN")),
        _ident_p(),
    ).map(
        lambda r: AlterTableStatement(
            command_type=SQLCommandType.ALTER_TABLE,
            raw_sql="",
            table_name=str(r[2]),
            action=AlterTableAction.DROP_COLUMN,
            drop_column_name=str(r[5]),
        )
    )

    return Choice(rename_table_p, rename_col_p, add_col_p, drop_col_p)


def _assemble_alter_add_column(r: List[Any]) -> AlterTableStatement:
    tbl = str(r[2])
    raw_col = str(r[5]).strip()
    c_def = _parse_single_column_def(raw_col)
    def_val = c_def.default_value if c_def else None

    return AlterTableStatement(
        command_type=SQLCommandType.ALTER_TABLE,
        raw_sql="",
        table_name=tbl,
        action=AlterTableAction.ADD_COLUMN,
        column_def=c_def,
        default_value=def_val,
    )


def _build_drop_parser() -> Parser[SQLStatement]:
    drop_tbl = Seq(
        _kw("DROP"),
        _kw("TABLE"),
        Opt(Seq(_kw("IF"), _kw("EXISTS"))),
        _ident_p(),
    ).map(
        lambda r: DropTableStatement(
            command_type=SQLCommandType.DROP_TABLE,
            raw_sql="",
            table_name=str(r[3]),
            if_exists=bool(r[2]),
        )
    )

    drop_idx = Seq(
        _kw("DROP"),
        _kw("INDEX"),
        Opt(Seq(_kw("IF"), _kw("EXISTS"))),
        _ident_p(),
    ).map(
        lambda r: DropIndexStatement(
            command_type=SQLCommandType.DROP_INDEX,
            raw_sql="",
            index_name=str(r[3]),
            if_exists=bool(r[2]),
        )
    )

    drop_vw = Seq(
        _kw("DROP"),
        _kw("VIEW"),
        Opt(Seq(_kw("IF"), _kw("EXISTS"))),
        _ident_p(),
    ).map(
        lambda r: DropViewStatement(
            command_type=SQLCommandType.DROP_VIEW,
            raw_sql="",
            view_name=str(r[3]),
            if_exists=bool(r[2]),
        )
    )

    drop_trg = Seq(
        _kw("DROP"),
        _kw("TRIGGER"),
        Opt(Seq(_kw("IF"), _kw("EXISTS"))),
        _ident_p(),
    ).map(
        lambda r: DropTriggerStatement(
            command_type=SQLCommandType.DROP_TRIGGER,
            raw_sql="",
            trigger_name=str(r[3]),
            if_exists=bool(r[2]),
        )
    )

    return Choice(drop_tbl, drop_idx, drop_vw, drop_trg)


def _build_reindex_parser() -> Parser[ReindexStatement]:
    return Seq(_kw("REINDEX"), Opt(_ident_p())).map(
        lambda r: ReindexStatement(
            command_type=SQLCommandType.REINDEX,
            raw_sql="",
            target_name=str(r[1]) if r[1] else None,
        )
    )


def _build_ddl_grammar() -> Parser[SQLStatement]:
    return Choice(
        _build_create_virtual_table_parser(),
        _build_create_table_parser(),
        _build_create_index_parser(),
        _build_create_view_parser(),
        _build_create_trigger_parser(),
        _build_alter_table_parser(),
        _build_drop_parser(),
        _build_reindex_parser(),
    )


class SQLDDLParser:
    """Packrat PEG Parser for SQL DDL statements."""

    def __init__(self) -> None:
        self._grammar = _build_ddl_grammar()

    def parse(self, text: str) -> SQLStatement:
        from .parser import SQLParseError

        stripped = text.strip().rstrip(";")
        if not stripped:
            raise SQLParseError("Empty SQL query")
        try:
            stmt = self._grammar.parse(stripped)
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
