#!/usr/bin/env python3
"""Pure-Python Packrat PEG DML (Data Manipulation Language) Parser.

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

Zero external dependencies. Conforms to DSN-25 Phase 2-C / DSN-05.
"""

from __future__ import annotations

import ast as py_ast
from typing import Any, Dict, List, Optional, Tuple, cast

from core.structures.peg import (
    Choice,
    Lit,
    NotPred,
    OneOrMore,
    Opt,
    Parser,
    PEGSyntaxError,
    Reg,
    Seq,
    ZeroOrMore,
)

from .ast import (
    DeleteStatement,
    InsertStatement,
    JoinClause,
    SelectStatement,
    SQLCommandType,
    SQLStatement,
    TableRef,
    UpdateStatement,
)
from .dql_parser import parse_dql


class SQLParseError(Exception):
    """Raised when SQL parsing fails."""

    pass


def _tok(p: Parser[Any]) -> Parser[Any]:
    ws = Reg(r"(\s+|#[^\r\n]*|--[^\r\n]*)*")
    return Seq(p, ws).map(lambda r: r[0])


def _kw(word: str) -> Parser[str]:
    return _tok(Reg(rf"(?i){word}\b")).map(lambda s: s.upper())


def _build_ident_parser() -> Parser[str]:
    plain = Reg(r"[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)?")
    backtick = Reg(r"`[^`]*`").map(lambda s: s[1:-1])
    double_quote = Reg(r'"[^"]*"').map(lambda s: s[1:-1])
    return _tok(Choice(plain, backtick, double_quote))


def _build_returning_clause() -> Parser[List[str]]:
    item = _tok(Reg(r"[^\s,;()]+(?:\s+AS\s+[a-zA-Z0-9_]+)?|\*"))
    items = Seq(item, ZeroOrMore(Seq(_tok(Lit(",")), item))).map(
        lambda r: [str(r[0])] + [str(it[1]) for it in cast(List[Any], r[1])]
    )
    return Seq(_kw("RETURNING"), items).map(lambda r: cast(List[str], r[1]))


def _build_conflict_target() -> Parser[List[str]]:
    col = _build_ident_parser()
    col_list = Seq(
        _tok(Lit("(")),
        col,
        ZeroOrMore(Seq(_tok(Lit(",")), col)),
        _tok(Lit(")")),
    ).map(lambda r: [str(r[1])] + [str(it[1]) for it in cast(List[Any], r[2])])
    return col_list


def _resolve_raw_literal(val_str: str) -> Any:
    clean = val_str.strip()
    if clean.upper() == "NULL":
        return None
    if clean.upper() == "TRUE":
        return True
    if clean.upper() == "FALSE":
        return False
    try:
        return py_ast.literal_eval(clean)
    except Exception:
        return clean.strip("'\"")


def _build_chunk_atom(end_kw: Parser[Any]) -> Parser[str]:
    func_name = Seq(NotPred(end_kw), Reg(r"[a-zA-Z_][a-zA-Z0-9_]*")).map(
        lambda r: str(r[1])
    )
    func_call = Seq(func_name, Reg(r"\s*\((?:[^()]|\([^()]*\))*\)")).map(
        lambda r: f"{r[0]}{r[1]}"
    )
    paren = Reg(r"\((?:[^()]|\([^()]*\))*\)")
    bracket = Reg(r"\[(?:[^\[\]]|\[[^\[\]]*\])*\]")
    s_quote = Reg(r"'([^']|'')*'")
    d_quote = Reg(r'"([^"\\]|\\.)*"')
    non_ws = Seq(NotPred(end_kw), Reg(r"[^\s,;()]+")).map(lambda r: str(r[1]))
    return _tok(Choice(func_call, paren, bracket, s_quote, d_quote, non_ws))


def _build_set_end() -> Parser[Any]:
    return Choice(
        _kw("FROM"),
        _kw("WHERE"),
        _kw("ORDER"),
        _kw("LIMIT"),
        _kw("RETURNING"),
        Lit(";"),
    )


def _build_set_item() -> Parser[Tuple[str, Any, str]]:
    col = _build_ident_parser()
    end_kw = _build_set_end()
    atom = _build_chunk_atom(end_kw)
    expr = OneOrMore(atom).map(lambda parts: " ".join(parts).strip())

    return Seq(col, _tok(Lit("=")), expr).map(
        lambda r: (str(r[0]), _resolve_raw_literal(str(r[2])), str(r[2]))
    )


def _build_set_assignments_parser() -> Parser[Tuple[Dict[str, Any], Dict[str, str]]]:
    item = _build_set_item()
    items = Seq(item, ZeroOrMore(Seq(_tok(Lit(",")), item))).map(
        lambda r: [r[0]] + [it[1] for it in cast(List[Any], r[1])]
    )

    def _assemble_sets(
        raw_list: List[Tuple[str, Any, str]],
    ) -> Tuple[Dict[str, Any], Dict[str, str]]:
        static_map: Dict[str, Any] = {}
        raw_map: Dict[str, str] = {}
        for c, val, raw_e in raw_list:
            static_map[c] = val
            raw_map[c] = raw_e
        return static_map, raw_map

    return Seq(_kw("SET"), items).map(
        lambda r: _assemble_sets(cast(List[Tuple[str, Any, str]], r[1]))
    )


def _build_upsert_clause() -> Parser[Tuple[Optional[List[str]], str, Dict[str, Any]]]:
    target = Opt(_build_conflict_target())
    target_where = Opt(Seq(_kw("WHERE"), _tok(Reg(r"[^;DO]+"))))

    do_nothing = _kw("NOTHING").map(lambda _: ("NOTHING", cast(Dict[str, Any], {})))

    set_parser = _build_set_assignments_parser()
    update_where = Opt(Seq(_kw("WHERE"), _tok(Reg(r"[^;RETURNING]+"))))
    do_update = Seq(_kw("UPDATE"), set_parser, update_where).map(
        lambda r: ("UPDATE", cast(Dict[str, Any], r[1][0]))
    )

    action_p = Seq(_kw("DO"), Choice(do_nothing, do_update)).map(lambda r: r[1])

    return Seq(_kw("ON"), _kw("CONFLICT"), target, target_where, action_p).map(
        lambda r: (
            cast(Optional[List[str]], r[2]),
            str(r[4][0]),
            cast(Dict[str, Any], r[4][1]),
        )
    )


def _parse_tuple_literal(row_str: str) -> List[Any]:
    clean = row_str.strip()
    try:
        parsed = py_ast.literal_eval(f"({clean})")
        if not isinstance(parsed, tuple):
            return [parsed]
        return list(parsed)
    except Exception:
        return [p.strip().strip("'\"") for p in clean.split(",")]


def _build_values_row() -> Parser[List[Any]]:
    inner_atom = Choice(
        Reg(r"'([^']|'')*'"),
        Reg(r'"([^"\\]|\\.)*"'),
        Reg(r"\[(?:[^\[\]]|\[[^\[\]]*\])*\]"),
        Reg(r"[^,)]+"),
    )
    atom_p = _tok(inner_atom).map(lambda s: _resolve_raw_literal(str(s)))
    row_inner = Seq(atom_p, ZeroOrMore(Seq(_tok(Lit(",")), atom_p))).map(
        lambda r: [r[0]] + [it[1] for it in cast(List[Any], r[1])]
    )
    return Seq(_tok(Lit("(")), row_inner, _tok(Lit(")"))).map(
        lambda r: cast(List[Any], r[1])
    )


def _build_values_rows_parser() -> Parser[List[List[Any]]]:
    row = _build_values_row()
    return Seq(
        _kw("VALUES"),
        row,
        ZeroOrMore(Seq(_tok(Lit(",")), row)),
    ).map(
        lambda r: [cast(List[Any], r[1])]
        + [cast(List[Any], it[1]) for it in cast(List[Any], r[2])]
    )


def _build_cols_list_parser() -> Parser[List[str]]:
    col = _build_ident_parser()
    return Seq(
        _tok(Lit("(")),
        col,
        ZeroOrMore(Seq(_tok(Lit(",")), col)),
        _tok(Lit(")")),
    ).map(lambda r: [str(r[1])] + [str(it[1]) for it in cast(List[Any], r[2])])


def _build_insert_select_body() -> Parser[SelectStatement]:
    body_str = _tok(Reg(r"(?i)SELECT\s+.*?(?=\s+ON\s+CONFLICT|\s+RETURNING|$)")).map(
        lambda s: str(s).strip()
    )
    return body_str.map(lambda s: parse_dql(s))


def _resolve_insert_upsert_action(
    is_replace: bool, up_act: Optional[str]
) -> Optional[str]:
    if is_replace and up_act is None:
        return "UPDATE"
    return up_act


def _validate_insert_rows_columns(cols: List[str], rows: List[List[Any]]) -> None:
    if not cols:
        return
    for r in rows:
        if len(r) != len(cols):
            raise SQLParseError(
                f"Column count ({len(cols)}) does not match values count ({len(r)})"
            )


def _make_insert_values_stmt(
    table_name: str,
    cols: List[str],
    rows: List[List[Any]],
    up_tgt: Optional[List[str]],
    up_act: Optional[str],
    up_set: Dict[str, Any],
    ret_cols: Optional[List[str]],
) -> InsertStatement:
    _validate_insert_rows_columns(cols, rows)
    first_val = rows[0] if rows else []
    return InsertStatement(
        command_type=SQLCommandType.INSERT,
        raw_sql="",
        table_name=table_name,
        columns=cols,
        values=first_val,
        rows_values=rows,
        upsert_target=up_tgt,
        upsert_action=up_act,
        upsert_update_set=up_set,
        returning_cols=ret_cols,
    )


def _extract_upsert_parts(
    is_replace: bool,
    upsert_info: Optional[Tuple[Optional[List[str]], str, Dict[str, Any]]],
) -> Tuple[Optional[List[str]], Optional[str], Dict[str, Any]]:
    if not upsert_info:
        act = "UPDATE" if is_replace else None
        return None, act, {}
    act = _resolve_insert_upsert_action(is_replace, upsert_info[1])
    return upsert_info[0], act, upsert_info[2]


def _assemble_insert_stmt(
    is_replace: bool,
    table_name: str,
    cols: Optional[List[str]],
    body: Any,
    upsert_info: Optional[Tuple[Optional[List[str]], str, Dict[str, Any]]],
    ret_cols: Optional[List[str]],
) -> InsertStatement:
    cols_list = cols or []
    up_tgt, up_act, up_set = _extract_upsert_parts(is_replace, upsert_info)

    if isinstance(body, SelectStatement):
        return InsertStatement(
            command_type=SQLCommandType.INSERT,
            raw_sql="",
            table_name=table_name,
            columns=cols_list,
            select_stmt=body,
            upsert_target=up_tgt,
            upsert_action=up_act,
            upsert_update_set=up_set,
            returning_cols=ret_cols,
        )

    return _make_insert_values_stmt(
        table_name=table_name,
        cols=cols_list,
        rows=cast(List[List[Any]], body),
        up_tgt=up_tgt,
        up_act=up_act,
        up_set=up_set,
        ret_cols=ret_cols,
    )


def _build_insert_parser() -> Parser[InsertStatement]:
    header = Choice(
        Seq(_kw("INSERT"), Opt(Seq(_kw("OR"), _kw("REPLACE"))), _kw("INTO")).map(
            lambda _: False
        ),
        Seq(_kw("REPLACE"), _kw("INTO")).map(lambda _: True),
    )
    table_p = _build_ident_parser()
    cols_p = Opt(_build_cols_list_parser())
    body_p = Choice(_build_values_rows_parser(), _build_insert_select_body())
    upsert_p = Opt(_build_upsert_clause())
    ret_p = Opt(_build_returning_clause())

    return Seq(header, table_p, cols_p, body_p, upsert_p, ret_p).map(
        lambda r: _assemble_insert_stmt(
            is_replace=bool(r[0]),
            table_name=str(r[1]),
            cols=cast(Optional[List[str]], r[2]),
            body=r[3],
            upsert_info=cast(
                Optional[Tuple[Optional[List[str]], str, Dict[str, Any]]], r[4]
            ),
            ret_cols=cast(Optional[List[str]], r[5]),
        )
    )


def _build_idx_hint_parser() -> Parser[Tuple[Optional[str], bool]]:
    idx_p = Seq(_kw("INDEXED"), _kw("BY"), _build_ident_parser()).map(
        lambda r: (str(r[2]), False)
    )
    not_idx_p = Seq(_kw("NOT"), _kw("INDEXED")).map(lambda _: (None, True))
    return Choice(idx_p, not_idx_p)


def _extract_where_list(where_raw: Optional[str]) -> List[Dict[str, Any]]:
    if not where_raw:
        return []
    from .parser import SQLParser

    dummy_parser = SQLParser()
    return dummy_parser._extract_where_clauses(where_raw.strip())


def _build_order_limit_clause() -> Parser[Tuple[Optional[str], bool, Optional[int]]]:
    order_col = _tok(Reg(r"[a-zA-Z0-9_\.]+"))
    direction = Opt(Choice(_kw("ASC"), _kw("DESC"))).map(
        lambda r: (r == "DESC") if r else False
    )
    order_p = Opt(Seq(_kw("ORDER"), _kw("BY"), order_col, direction)).map(
        lambda r: (str(r[2]), bool(r[3])) if r else (None, False)
    )

    limit_num = _tok(Reg(r"[0-9]+")).map(lambda s: int(s))
    limit_p = Opt(Seq(_kw("LIMIT"), limit_num)).map(lambda r: int(r[1]) if r else None)

    return Seq(order_p, limit_p).map(
        lambda r: (
            cast(Optional[str], r[0][0]),
            cast(bool, r[0][1]),
            cast(Optional[int], r[1]),
        )
    )


def _assemble_update_stmt(
    table_info: Tuple[str, Optional[Tuple[Optional[str], bool]]],
    sets: Tuple[Dict[str, Any], Dict[str, str]],
    from_info: Optional[Tuple[TableRef, List[JoinClause]]],
    where_raw: Optional[str],
    ret_cols: Optional[List[str]],
    ord_lim: Tuple[Optional[str], bool, Optional[int]],
) -> UpdateStatement:
    tbl_name = table_info[0]
    hint = table_info[1]
    indexed_by = hint[0] if hint else None
    not_indexed = hint[1] if hint else False

    from_tbl = from_info[0] if from_info else None
    joins_list = from_info[1] if from_info else []
    where_clauses = _extract_where_list(where_raw)

    return UpdateStatement(
        command_type=SQLCommandType.UPDATE,
        raw_sql="",
        table_name=tbl_name,
        assignments=sets[0],
        raw_assignments=sets[1],
        from_table=from_tbl,
        joins=joins_list,
        where_clauses=where_clauses,
        returning_cols=ret_cols,
        order_by=ord_lim[0],
        order_desc=ord_lim[1],
        limit=ord_lim[2],
        indexed_by=indexed_by,
        not_indexed=not_indexed,
    )


def _build_update_from_clause() -> Parser[Tuple[TableRef, List[JoinClause]]]:
    from core.structures.peg import RuleRef

    from .dql_parser import _build_join_clause_parser, _build_table_ref_parser

    dummy_ref = RuleRef("dql_ref")
    tbl_p = _build_table_ref_parser(dummy_ref)
    join_p = _build_join_clause_parser(dummy_ref)
    return Seq(_kw("FROM"), tbl_p, ZeroOrMore(join_p)).map(
        lambda r: (cast(TableRef, r[1]), cast(List[JoinClause], r[2]))
    )


def _build_where_end() -> Parser[Any]:
    return Choice(
        _kw("ORDER"),
        _kw("LIMIT"),
        _kw("RETURNING"),
        Lit(";"),
    )


def _build_where_clause() -> Parser[Optional[str]]:
    end_kw = _build_where_end()
    atom = _build_chunk_atom(end_kw)
    where_body = OneOrMore(atom).map(lambda parts: " ".join(parts).strip())
    return Opt(Seq(_kw("WHERE"), where_body)).map(lambda r: str(r[1]) if r else None)


def _build_update_parser() -> Parser[UpdateStatement]:
    header = Seq(
        _kw("UPDATE"),
        Opt(
            Seq(
                _kw("OR"),
                Choice(
                    _kw("ROLLBACK"),
                    _kw("ABORT"),
                    _kw("FAIL"),
                    _kw("IGNORE"),
                    _kw("REPLACE"),
                ),
            )
        ),
    )
    table_p = Seq(_build_ident_parser(), Opt(_build_idx_hint_parser())).map(
        lambda r: (str(r[0]), cast(Optional[Tuple[Optional[str], bool]], r[1]))
    )

    set_p = _build_set_assignments_parser()
    from_p = Opt(_build_update_from_clause())
    where_p = _build_where_clause()
    ret_p = Opt(_build_returning_clause())
    ord_lim_p = _build_order_limit_clause()

    return Seq(header, table_p, set_p, from_p, where_p, ord_lim_p, ret_p).map(
        lambda r: _assemble_update_stmt(
            table_info=r[1],
            sets=r[2],
            from_info=r[3],
            where_raw=r[4],
            ret_cols=r[6],
            ord_lim=r[5],
        )
    )


def _assemble_delete_stmt(
    table_info: Tuple[str, Optional[Tuple[Optional[str], bool]]],
    where_raw: Optional[str],
    ord_lim: Tuple[Optional[str], bool, Optional[int]],
    ret_cols: Optional[List[str]],
) -> DeleteStatement:
    tbl_name = table_info[0]
    hint = table_info[1]
    indexed_by = hint[0] if hint else None
    not_indexed = hint[1] if hint else False
    where_clauses = _extract_where_list(where_raw)

    return DeleteStatement(
        command_type=SQLCommandType.DELETE,
        raw_sql="",
        table_name=tbl_name,
        where_clauses=where_clauses,
        returning_cols=ret_cols,
        order_by=ord_lim[0],
        order_desc=ord_lim[1],
        limit=ord_lim[2],
        indexed_by=indexed_by,
        not_indexed=not_indexed,
    )


def _build_delete_parser() -> Parser[DeleteStatement]:
    table_p = Seq(_build_ident_parser(), Opt(_build_idx_hint_parser())).map(
        lambda r: (str(r[0]), cast(Optional[Tuple[Optional[str], bool]], r[1]))
    )

    where_p = _build_where_clause()
    ord_lim_p = _build_order_limit_clause()
    ret_p = Opt(_build_returning_clause())

    return Seq(_kw("DELETE"), _kw("FROM"), table_p, where_p, ord_lim_p, ret_p).map(
        lambda r: _assemble_delete_stmt(
            table_info=r[2],
            where_raw=r[3],
            ord_lim=r[4],
            ret_cols=r[5],
        )
    )


def _build_dml_grammar() -> Parser[SQLStatement]:
    dml_choice = Choice(
        _build_insert_parser(),
        _build_update_parser(),
        _build_delete_parser(),
    )
    leading_ws = Reg(r"(\s+|#[^\r\n]*|--[^\r\n]*)*")
    return Seq(leading_ws, dml_choice, leading_ws).map(
        lambda r: cast(SQLStatement, r[1])
    )


class SQLDMLParser:
    """Packrat PEG Parser for SQL DML statements (INSERT, UPDATE, DELETE, UPSERT)."""

    def __init__(self) -> None:
        self._grammar = _build_dml_grammar()

    def parse(self, text: str) -> SQLStatement:
        stripped = text.strip().rstrip(";")
        if not stripped:
            raise SQLParseError("Empty SQL query")
        try:
            stmt = self._grammar.parse(stripped)
            stmt.raw_sql = text
            return stmt
        except PEGSyntaxError as exc:
            raise SQLParseError(
                f"SQL DML syntax error at line {exc.line}, col {exc.col}: {exc.message}"
            ) from exc


def parse_dml(text: str) -> SQLStatement:
    """Convenience helper to parse a DML SQL string into SQLStatement AST."""
    parser = SQLDMLParser()
    return parser.parse(text)
