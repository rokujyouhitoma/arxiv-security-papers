#!/usr/bin/env python3
"""Pure-Python Packrat PEG DQL (Data Query Language) Parser.

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

Zero external dependencies. Conforms to DSN-25 Phase 2-B / DSN-05.
"""

from __future__ import annotations

import ast as py_ast
import re
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
    RuleRef,
    Seq,
    ZeroOrMore,
)

from .ast import (
    CTEDefinition,
    JoinClause,
    JoinType,
    SelectStatement,
    SQLCommandType,
    TableRef,
)
from .expr_parser import SQLExpressionParser


class SQLParseError(Exception):
    """Raised when SQL parsing fails."""

    pass


def _tok(p: Parser[Any]) -> Parser[Any]:
    ws = Reg(r"(\s+|#[^\r\n]*|--[^\r\n]*)*")
    return Seq(p, ws).map(lambda r: r[0])


def _kw(word: str) -> Parser[str]:
    return _tok(Reg(rf"(?i){word}\b")).map(lambda s: s.upper())


_RESERVED_LIST = [
    "SELECT",
    "FROM",
    "WHERE",
    "GROUP",
    "BY",
    "HAVING",
    "WINDOW",
    "ORDER",
    "LIMIT",
    "OFFSET",
    "JOIN",
    "INNER",
    "LEFT",
    "RIGHT",
    "CROSS",
    "NATURAL",
    "ON",
    "USING",
    "UNION",
    "INTERSECT",
    "EXCEPT",
    "WITH",
    "RECURSIVE",
    "AS",
    "INDEXED",
    "NOT",
    "VALUES",
    "DISTINCT",
    "ALL",
]


def _build_reserved_checker() -> Parser[Any]:
    return Choice(*[_kw(w) for w in _RESERVED_LIST])


def _build_ident_parser() -> Parser[str]:
    plain = Reg(r"[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)?")
    backtick = Reg(r"`[^`]*`").map(lambda s: s[1:-1])
    double_quote = Reg(r'"[^"]*"').map(lambda s: s[1:-1])
    return _tok(Choice(plain, backtick, double_quote))


def _build_non_reserved_ident() -> Parser[str]:
    res_chk = _build_reserved_checker()
    ident = _build_ident_parser()
    return Seq(NotPred(res_chk), ident).map(lambda r: cast(str, r[1]))


def _build_number_parser() -> Parser[Any]:
    num_re = Reg(r"[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?")

    def _conv(s: str) -> Any:
        if "." in s or "e" in s or "E" in s:
            return float(s)
        return int(s)

    return _tok(num_re).map(_conv)


def _build_string_literal_parser() -> Parser[str]:
    single_quote = Reg(r"'([^']|'')*'")

    def _strip_quote(s: str) -> str:
        return s[1:-1].replace("''", "'")

    return _tok(single_quote).map(_strip_quote)


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


def _build_delimited_expr(end_kw: Parser[Any]) -> Parser[str]:
    atom = _build_chunk_atom(end_kw)
    return OneOrMore(atom).map(lambda parts: " ".join(parts).strip())


def _build_clause_end() -> Parser[Any]:
    return Choice(
        _kw("FROM"),
        _kw("WHERE"),
        _kw("GROUP"),
        _kw("HAVING"),
        _kw("WINDOW"),
        _kw("ORDER"),
        _kw("LIMIT"),
        _kw("UNION"),
        _kw("INTERSECT"),
        _kw("EXCEPT"),
        Lit(";"),
    )


def _build_projection_item() -> Parser[str]:
    end_kw = _build_clause_end()
    star = _tok(Lit("*")).map(lambda _: "*")
    tbl_star = Seq(_build_ident_parser(), _tok(Lit(".")), _tok(Lit("*"))).map(
        lambda r: f"{r[0]}.*"
    )
    expr = _build_delimited_expr(end_kw)
    return Choice(tbl_star, star, expr)


def _build_limit_offset_parser() -> Parser[Tuple[Optional[int], Optional[int]]]:
    num = _tok(Reg(r"[0-9]+")).map(lambda s: int(s))
    limit_offset = Seq(_kw("LIMIT"), num, _kw("OFFSET"), num).map(
        lambda r: (r[1], r[3])
    )
    limit_comma = Seq(_kw("LIMIT"), num, _tok(Lit(",")), num).map(
        lambda r: (r[3], r[1])
    )
    limit_only = Seq(_kw("LIMIT"), num).map(lambda r: (r[1], None))
    return Choice(limit_offset, limit_comma, limit_only)


def _build_order_by_parser() -> Parser[Tuple[str, bool, Optional[str]]]:
    col_name = _tok(Reg(r"[a-zA-Z0-9_\.\->>\'\"]+"))
    collate = Opt(Seq(_kw("COLLATE"), _tok(Reg(r"[a-zA-Z0-9_]+")))).map(
        lambda r: str(r[1]).upper() if r else None
    )
    direction = Opt(Choice(_kw("ASC"), _kw("DESC"))).map(
        lambda r: (r == "DESC") if r else False
    )
    nulls = Opt(Seq(_kw("NULLS"), Choice(_kw("FIRST"), _kw("LAST"))))

    item = Seq(col_name, collate, direction, nulls).map(
        lambda r: (str(r[0]), bool(r[2]), cast(Optional[str], r[1]))
    )
    items = Seq(item, ZeroOrMore(Seq(_tok(Lit(",")), item))).map(
        lambda r: cast(Tuple[str, bool, Optional[str]], r[0])
    )
    return Seq(_kw("ORDER"), _kw("BY"), items).map(
        lambda r: cast(Tuple[str, bool, Optional[str]], r[2])
    )


def _build_group_by_parser() -> Parser[List[str]]:
    col = _tok(Reg(r"[a-zA-Z0-9_\.\->>\'\"]+"))
    items = Seq(col, ZeroOrMore(Seq(_tok(Lit(",")), col))).map(
        lambda r: [str(r[0])] + [str(it[1]) for it in cast(List[Any], r[1])]
    )
    return Seq(_kw("GROUP"), _kw("BY"), items).map(lambda r: cast(List[str], r[2]))


def _build_having_end() -> Parser[Any]:
    return Choice(
        _kw("WINDOW"),
        _kw("ORDER"),
        _kw("LIMIT"),
        _kw("UNION"),
        _kw("INTERSECT"),
        _kw("EXCEPT"),
        Lit(";"),
    )


def _build_having_parser() -> Parser[str]:
    end_kw = _build_having_end()
    cond = _build_delimited_expr(end_kw)
    return Seq(_kw("HAVING"), cond).map(lambda r: str(r[1]).strip())


def _extract_knn_from_where(where_raw: str) -> Tuple[str, Optional[Dict[str, Any]]]:
    knn_m = re.search(
        r"KNN\s*\(\s*([a-zA-Z0-9_\.]+)\s*,\s*(\[.*?\])\s*,\s*([0-9]+)\s*\)",
        where_raw,
        re.IGNORECASE,
    )
    if not knn_m:
        knn_m = re.search(
            r"([a-zA-Z0-9_\.]+)\s+KNN\s+(\[.*?\])\s+TOP\s+([0-9]+)",
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
    knn_query: Dict[str, Any] = {
        "column": knn_col,
        "vector": [float(x) for x in knn_vec],
        "top_k": top_k,
    }
    cleaned = where_raw.replace(knn_m.group(0), "").strip()
    cleaned = re.sub(r"^(AND|OR)\s+", "", cleaned, flags=re.IGNORECASE).strip()
    cleaned = re.sub(r"\s+(AND|OR)$", "", cleaned, flags=re.IGNORECASE).strip()
    return cleaned, knn_query


def _parse_single_term(t: str, parser: SQLExpressionParser) -> Dict[str, Any]:
    from .parser import _parse_where_clause_item

    legacy = _parse_where_clause_item(t)
    if legacy is not None:
        return legacy
    try:
        ex = parser.parse(t)
        leg = ex.to_legacy_dict()
        if leg:
            return leg
    except Exception:
        pass
    return {"column": t, "operator": "=", "value": True}


def _parse_where_condition_terms(where_str: str) -> List[Dict[str, Any]]:
    clean = where_str.strip()
    if not clean:
        return []
    from .parser import SQLParser

    dummy_parser = SQLParser()
    return dummy_parser._extract_where_clauses(clean)


def _make_plain_table_ref(r: List[Any]) -> TableRef:
    name_val = str(r[0])
    hint = r[1]
    alias_val = r[2]
    indexed = hint[1] if (hint and hint[0] == "INDEXED") else None
    not_idx = bool(hint and hint[0] == "NOT_INDEXED")
    return TableRef(
        name=name_val,
        alias=alias_val,
        indexed_by=indexed,
        not_indexed=not_idx,
    )


def _split_tvf_args(raw_args: Optional[str]) -> List[str]:
    if not raw_args:
        return []
    from .parser import _split_comma_expressions

    return _split_comma_expressions(raw_args)


def _build_func_args_parser() -> Parser[List[str]]:
    return Seq(
        _tok(Lit("(")),
        Opt(Reg(r"[^)]*")),
        _tok(Lit(")")),
    ).map(lambda r: _split_tvf_args(str(r[1]) if r[1] else None))


def _build_alias_parser() -> Parser[str]:
    non_res = _build_non_reserved_ident()
    with_as = Seq(_kw("AS"), _build_ident_parser()).map(lambda r: str(r[1]))
    return Choice(with_as, non_res)


def _build_table_ref_parser(select_ref: RuleRef) -> Parser[TableRef]:
    ident = _build_non_reserved_ident()
    alias_p = Opt(_build_alias_parser())

    idx_hint = Opt(
        Choice(
            Seq(_kw("INDEXED"), _kw("BY"), ident).map(lambda r: ("INDEXED", str(r[2]))),
            Seq(_kw("NOT"), _kw("INDEXED")).map(lambda _: ("NOT_INDEXED", None)),
        )
    )

    subquery_p = Seq(_tok(Lit("(")), select_ref, _tok(Lit(")")), alias_p).map(
        lambda r: TableRef(
            name=str(r[3] or ""),
            alias=r[3],
            subquery=cast(SelectStatement, r[1]),
        )
    )

    tvf_p = Seq(ident, _build_func_args_parser(), alias_p).map(
        lambda r: TableRef(
            name=str(r[0]),
            alias=r[2],
            function_name=str(r[0]),
            function_args=cast(List[str], r[1]),
        )
    )

    tbl_plain_1 = Seq(ident, alias_p, idx_hint).map(
        lambda r: TableRef(
            name=str(r[0]),
            alias=r[1],
            indexed_by=r[2][1] if (r[2] and r[2][0] == "INDEXED") else None,
            not_indexed=bool(r[2] and r[2][0] == "NOT_INDEXED"),
        )
    )
    tbl_plain_2 = Seq(ident, idx_hint, alias_p).map(_make_plain_table_ref)
    tbl_plain = Choice(tbl_plain_1, tbl_plain_2)
    return Choice(subquery_p, tvf_p, tbl_plain)


def _build_on_end() -> Parser[Any]:
    return Choice(
        _kw("NATURAL"),
        _kw("JOIN"),
        _kw("INNER"),
        _kw("LEFT"),
        _kw("RIGHT"),
        _kw("CROSS"),
        _kw("WHERE"),
        _kw("GROUP"),
        _kw("HAVING"),
        _kw("WINDOW"),
        _kw("ORDER"),
        _kw("LIMIT"),
        _kw("UNION"),
        _kw("INTERSECT"),
        _kw("EXCEPT"),
        Lit(";"),
    )


def _build_join_clause_parser(select_ref: RuleRef) -> Parser[JoinClause]:
    table_p = _build_table_ref_parser(select_ref)
    j_type = Opt(
        Choice(
            _kw("INNER").map(lambda _: "INNER"),
            Seq(_kw("LEFT"), Opt(_kw("OUTER"))).map(lambda _: "LEFT"),
            Seq(_kw("RIGHT"), Opt(_kw("OUTER"))).map(lambda _: "RIGHT"),
            _kw("CROSS").map(lambda _: "CROSS"),
        )
    ).map(lambda r: JoinType(r) if r else JoinType.INNER)

    end_kw = _build_on_end()
    on_expr = Seq(_kw("ON"), _build_delimited_expr(end_kw)).map(
        lambda r: _parse_where_condition_terms(str(r[1]))
    )

    using_cols = Seq(
        _kw("USING"),
        _tok(Lit("(")),
        Seq(
            _build_ident_parser(),
            ZeroOrMore(Seq(_tok(Lit(",")), _build_ident_parser())),
        ),
        _tok(Lit(")")),
    ).map(
        lambda r: [
            {
                "column": str(col),
                "operator": "=",
                "value": str(col),
            }
            for col in [r[2][0]] + [item[1] for item in cast(List[Any], r[2][1])]
        ]
    )

    cond_p = Choice(on_expr, using_cols)

    explicit_join = Seq(
        Opt(_kw("NATURAL")),
        j_type,
        _kw("JOIN"),
        table_p,
        Opt(cond_p),
    ).map(
        lambda r: JoinClause(
            join_type=cast(JoinType, r[1]),
            table=cast(TableRef, r[3]),
            on_conditions=cast(List[Dict[str, Any]], r[4] or []),
        )
    )

    comma_join = Seq(
        _tok(Lit(",")),
        table_p,
    ).map(
        lambda r: JoinClause(
            join_type=JoinType.CROSS,
            table=cast(TableRef, r[1]),
            on_conditions=[],
        )
    )

    return Choice(explicit_join, comma_join)


def _build_cte_parser(select_ref: RuleRef) -> Parser[List[CTEDefinition]]:
    ident = _build_ident_parser()
    col_list = Seq(
        _tok(Lit("(")),
        ident,
        ZeroOrMore(Seq(_tok(Lit(",")), ident)),
        _tok(Lit(")")),
    ).map(lambda r: [str(r[1])] + [str(it[1]) for it in cast(List[Any], r[2])])

    cte_entry = Seq(
        ident,
        Opt(col_list),
        _kw("AS"),
        _tok(Lit("(")),
        select_ref,
        _tok(Lit(")")),
    ).map(
        lambda r: CTEDefinition(
            name=str(r[0]),
            columns=cast(List[str], r[1] or []),
            statement=cast(SelectStatement, r[4]),
            is_recursive=False,
        )
    )

    cte_list = Seq(cte_entry, ZeroOrMore(Seq(_tok(Lit(",")), cte_entry))).map(
        lambda r: [cast(CTEDefinition, r[0])]
        + [cast(CTEDefinition, it[1]) for it in cast(List[Any], r[1])]
    )

    return Seq(
        _kw("WITH"),
        Opt(_kw("RECURSIVE")),
        cte_list,
    ).map(
        lambda r: [
            CTEDefinition(
                name=c.name,
                columns=c.columns,
                statement=c.statement,
                is_recursive=bool(r[1]),
            )
            for c in cast(List[CTEDefinition], r[2])
        ]
    )


def _build_standalone_values_parser() -> Parser[SelectStatement]:
    val_atom = Choice(
        _build_string_literal_parser(),
        _build_number_parser(),
        _kw("TRUE").map(lambda _: True),
        _kw("FALSE").map(lambda _: False),
        _kw("NULL").map(lambda _: None),
    )

    val_row = Seq(
        _tok(Lit("(")),
        val_atom,
        ZeroOrMore(Seq(_tok(Lit(",")), val_atom)),
        _tok(Lit(")")),
    ).map(lambda r: [r[1]] + [it[1] for it in cast(List[Any], r[2])])

    val_rows = Seq(
        _kw("VALUES"),
        val_row,
        ZeroOrMore(Seq(_tok(Lit(",")), val_row)),
    ).map(
        lambda r: [cast(List[Any], r[1])]
        + [cast(List[Any], it[1]) for it in cast(List[Any], r[2])]
    )

    order_p = Opt(_build_order_by_parser())
    limit_p = Opt(_build_limit_offset_parser())

    def _make_values_stmt(r: List[Any]) -> SelectStatement:
        rows = cast(List[List[Any]], r[0])
        order_info = r[1]
        lim_info = r[2]
        ncols = len(rows[0]) if rows else 0
        cols = [f"column{i + 1}" for i in range(ncols)]
        return SelectStatement(
            command_type=SQLCommandType.SELECT,
            raw_sql="",
            table_name="",
            columns=cols,
            values_rows=rows,
            order_by=order_info[0] if order_info else None,
            order_desc=order_info[1] if order_info else False,
            order_collate=order_info[2] if order_info else None,
            limit=lim_info[0] if lim_info else None,
            offset=lim_info[1] if lim_info else None,
        )

    return Seq(val_rows, order_p, limit_p).map(_make_values_stmt)


def _build_where_end() -> Parser[Any]:
    return Choice(
        _kw("GROUP"),
        _kw("HAVING"),
        _kw("WINDOW"),
        _kw("ORDER"),
        _kw("LIMIT"),
        _kw("UNION"),
        _kw("INTERSECT"),
        _kw("EXCEPT"),
        Lit(";"),
    )


def _build_single_select_parser(select_ref: RuleRef) -> Parser[SelectStatement]:
    proj_item = _build_projection_item()
    proj_list = Seq(proj_item, ZeroOrMore(Seq(_tok(Lit(",")), proj_item))).map(
        lambda r: [str(r[0])] + [str(it[1]) for it in cast(List[Any], r[1])]
    )

    distinct_p = Opt(Choice(_kw("DISTINCT"), _kw("ALL"))).map(
        lambda r: (r == "DISTINCT") if r else False
    )

    table_ref_p = _build_table_ref_parser(select_ref)
    joins_p = ZeroOrMore(_build_join_clause_parser(select_ref))

    from_clause = Opt(
        Seq(
            _kw("FROM"),
            table_ref_p,
            joins_p,
        )
    )

    end_where = _build_where_end()
    where_body = _build_delimited_expr(end_where)
    where_clause = Opt(Seq(_kw("WHERE"), where_body)).map(
        lambda r: str(r[1]) if r else None
    )

    group_p = Opt(_build_group_by_parser())
    having_p = Opt(_build_having_parser())
    order_p = Opt(_build_order_by_parser())
    limit_p = Opt(_build_limit_offset_parser())

    def _make_single_select(r: List[Any]) -> SelectStatement:
        dist = bool(r[1])
        cols = cast(List[str], r[2])
        from_part = r[3]
        where_raw = cast(Optional[str], r[4])
        group_cols = cast(Optional[List[str]], r[5]) or []
        having_raw = cast(Optional[str], r[6])
        order_info = r[7]
        lim_info = r[8]

        tbl_name = ""
        tbl_ref: Optional[TableRef] = None
        joins_list: List[JoinClause] = []
        if from_part:
            tbl_ref = cast(TableRef, from_part[1])
            tbl_name = tbl_ref.name or tbl_ref.alias or ""
            joins_list = cast(List[JoinClause], from_part[2])

        knn_query: Optional[Dict[str, Any]] = None
        where_clauses: List[Dict[str, Any]] = []
        if where_raw:
            clean_where, knn_query = _extract_knn_from_where(where_raw)
            where_clauses = _parse_where_condition_terms(clean_where)

        return SelectStatement(
            command_type=SQLCommandType.SELECT,
            raw_sql="",
            table_name=tbl_name,
            table_ref=tbl_ref,
            columns=cols,
            where_clauses=where_clauses,
            knn_query=knn_query,
            joins=joins_list,
            distinct=dist,
            group_by=group_cols,
            having=having_raw,
            order_by=order_info[0] if order_info else None,
            order_desc=order_info[1] if order_info else False,
            order_collate=order_info[2] if order_info else None,
            limit=lim_info[0] if lim_info else None,
            offset=lim_info[1] if lim_info else None,
        )

    return Seq(
        _kw("SELECT"),
        distinct_p,
        proj_list,
        from_clause,
        where_clause,
        group_p,
        having_p,
        order_p,
        limit_p,
    ).map(_make_single_select)


def _set_compound_attr(base: SelectStatement, op: str, part: SelectStatement) -> None:
    attr_map = {
        "UNION": "union",
        "UNION ALL": "union_all",
        "INTERSECT": "intersect",
        "EXCEPT": "except_",
    }
    field = attr_map.get(op)
    if field and getattr(base, field) is None:
        setattr(base, field, part)


def _apply_compounds(
    base: SelectStatement,
    compounds: List[Tuple[str, SelectStatement]],
) -> SelectStatement:
    for op, part in compounds:
        base.compounds.append((op, part))
        _set_compound_attr(base, op, part)
    return base


def _attach_ctes(r: List[Any]) -> SelectStatement:
    stmt = cast(SelectStatement, r[1])
    if r[0]:
        stmt.ctes = cast(List[CTEDefinition], r[0])
    return stmt


def _build_dql_grammar() -> Parser[SelectStatement]:
    select_ref = RuleRef("select")

    single_sel = _build_single_select_parser(select_ref)
    val_stmt = _build_standalone_values_parser()
    core_query = Choice(single_sel, val_stmt)

    compound_op = Choice(
        Seq(_kw("UNION"), _kw("ALL")).map(lambda _: "UNION ALL"),
        _kw("UNION"),
        _kw("INTERSECT"),
        _kw("EXCEPT"),
    )

    compound_query = Seq(
        core_query,
        ZeroOrMore(Seq(compound_op, core_query)),
    ).map(
        lambda r: _apply_compounds(
            cast(SelectStatement, r[0]),
            [
                (str(item[0]), cast(SelectStatement, item[1]))
                for item in cast(List[Any], r[1])
            ],
        )
    )

    cte_p = _build_cte_parser(select_ref)
    full_dql = Seq(Opt(cte_p), compound_query).map(_attach_ctes)

    select_ref.define(full_dql)

    leading_ws = Reg(r"(\s+|#[^\r\n]*|--[^\r\n]*)*")
    return Seq(leading_ws, full_dql, leading_ws).map(
        lambda r: cast(SelectStatement, r[1])
    )


class SQLDQLParser:
    """Packrat PEG Parser for full SQL DQL queries (SELECT, CTE, JOIN, UNION, VALUES)."""

    def __init__(self) -> None:
        self._grammar = _build_dql_grammar()

    def parse(self, text: str) -> SelectStatement:
        stripped = text.strip().rstrip(";")
        if not stripped:
            raise SQLParseError("Empty SQL query")
        try:
            stmt = self._grammar.parse(stripped)
            stmt.raw_sql = text
            return stmt
        except PEGSyntaxError as exc:
            raise SQLParseError(
                f"SQL DQL syntax error at line {exc.line}, col {exc.col}: {exc.message}"
            ) from exc


def parse_dql(text: str) -> SelectStatement:
    """Convenience helper to parse a DQL SQL string into SelectStatement AST."""
    parser = SQLDQLParser()
    return parser.parse(text)
