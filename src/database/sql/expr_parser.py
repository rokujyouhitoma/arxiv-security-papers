#!/usr/bin/env python3
"""Pure-Python Packrat PEG SQL Expression Parser.

Parses arbitrary SQL expressions into typed AST objects:
- Literals (integers, floats, single/double quoted strings, booleans, NULL)
- Identifiers / Column references (with optional table prefix, e.g. table.col, col->>'key')
- Arithmetic expressions (+, -, *, /, %) with proper precedence
- Comparisons (=, !=, <>, <, <=, >, >=)
- Predicates (IS NULL, IS NOT NULL, BETWEEN, IN, LIKE, GLOB, MATCH)
- Logical operators (AND, OR, NOT) and arbitrarily nested parentheses
- Function calls (e.g. COUNT(*), UPPER(col), JSON_EXTRACT(...))
- CASE expressions (CASE [expr] WHEN cond THEN result ... [ELSE def] END)

Zero external dependencies. Conforms to DSN-25 Phase 2 / DSN-05.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional, Tuple, cast

from core.structures.peg import (
    Choice,
    Lit,
    OneOrMore,
    Opt,
    Parser,
    Reg,
    RuleRef,
    Seq,
    ZeroOrMore,
)


class SQLExpr(ABC):
    """Abstract Base Class for all SQL Expression AST nodes."""

    @abstractmethod
    def to_sql(self) -> str:
        """Serializes the AST node back to standard SQL expression string."""
        pass

    @abstractmethod
    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        """Converts simple predicate expressions to legacy engine WHERE dict."""
        pass

    def __repr__(self) -> str:
        return self.to_sql()


class LiteralExpr(SQLExpr):
    """Represents a literal constant value."""

    def __init__(self, value: Any) -> None:
        self.value = value

    def to_sql(self) -> str:
        if self.value is None:
            return "NULL"
        if isinstance(self.value, bool):
            return "TRUE" if self.value else "FALSE"
        if isinstance(self.value, str):
            escaped = self.value.replace("'", "''")
            return f"'{escaped}'"
        return str(self.value)

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        return None


class ColumnRefExpr(SQLExpr):
    """Represents a column identifier, optionally table-qualified or with json path."""

    def __init__(
        self,
        column: str,
        table: Optional[str] = None,
        json_path: Optional[str] = None,
    ) -> None:
        self.column = column
        self.table = table
        self.json_path = json_path

    @property
    def column_name(self) -> str:
        return self.column

    @property
    def table_name(self) -> Optional[str]:
        return self.table

    @property
    def full_name(self) -> str:
        if self.table:
            return f"{self.table}.{self.column}"
        return self.column

    def to_sql(self) -> str:
        base = self.full_name
        if self.json_path is not None:
            return f"{base}->>'{self.json_path}'"
        return base

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        return None


class UnaryOpExpr(SQLExpr):
    """Represents a unary operation (e.g. -x, NOT cond)."""

    def __init__(self, op: str, operand: SQLExpr) -> None:
        self.op = op.upper()
        self.operand = operand

    @property
    def operator(self) -> str:
        return self.op

    def to_sql(self) -> str:
        if self.op in ("+", "-"):
            return f"{self.op}{self.operand.to_sql()}"
        return f"{self.op} {self.operand.to_sql()}"

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        return None


def _eval_unary_constant(op: str, inner: Any) -> Optional[Any]:
    if op == "-":
        try:
            return -inner
        except TypeError:
            return None
    if op == "+":
        return inner
    return None


def _eval_constant(expr: SQLExpr) -> Optional[Any]:
    if isinstance(expr, LiteralExpr):
        return cast(Any, expr.value)
    if isinstance(expr, UnaryOpExpr):
        inner = _eval_constant(expr.operand)
        if inner is not None:
            return _eval_unary_constant(expr.op, inner)
    return None


class BinaryOpExpr(SQLExpr):
    """Represents a binary operation (+, -, *, /, AND, OR, =, !=, <, etc.)."""

    def __init__(self, op: str, left: SQLExpr, right: SQLExpr) -> None:
        self.op = op.upper()
        self.left = left
        self.right = right

    @property
    def operator(self) -> str:
        return self.op

    def to_sql(self) -> str:
        return f"({self.left.to_sql()} {self.op} {self.right.to_sql()})"

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        if not isinstance(self.left, ColumnRefExpr):
            return None
        const_val = _eval_constant(self.right)
        if const_val is not None:
            val: Any = const_val
        elif isinstance(self.right, ColumnRefExpr):
            val = self.right.full_name
        else:
            return None
        return {
            "column": self.left.full_name,
            "operator": self.op,
            "value": val,
        }


class BetweenExpr(SQLExpr):
    """Represents an expr [NOT] BETWEEN low AND high predicate."""

    def __init__(
        self,
        expr: SQLExpr,
        low: SQLExpr,
        high: SQLExpr,
        is_not: bool = False,
    ) -> None:
        self.expr = expr
        self.low = low
        self.high = high
        self.is_not = is_not

    def to_sql(self) -> str:
        op = "NOT BETWEEN" if self.is_not else "BETWEEN"
        return f"{self.expr.to_sql()} {op} {self.low.to_sql()} AND {self.high.to_sql()}"

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        low_val = _eval_constant(self.low)
        high_val = _eval_constant(self.high)
        if (
            isinstance(self.expr, ColumnRefExpr)
            and low_val is not None
            and high_val is not None
        ):
            op = "NOT BETWEEN" if self.is_not else "BETWEEN"
            return {
                "column": self.expr.full_name,
                "operator": op,
                "value": [low_val, high_val],
            }
        return None


def _in_expr_to_legacy(
    col: ColumnRefExpr,
    values: List[SQLExpr],
    subquery: Optional[str],
    is_not: bool,
) -> Dict[str, Any]:
    op = "NOT IN" if is_not else "IN"
    if subquery:
        return {
            "column": col.full_name,
            "operator": op,
            "subquery": subquery,
        }
    val_list = [v.value for v in values if isinstance(v, LiteralExpr)]
    return {
        "column": col.full_name,
        "operator": op,
        "value": val_list,
    }


class InExpr(SQLExpr):
    """Represents an expr [NOT] IN (val1, val2, ...) or subquery predicate."""

    def __init__(
        self,
        expr: SQLExpr,
        values: List[SQLExpr],
        subquery: Optional[str] = None,
        is_not: bool = False,
    ) -> None:
        self.expr = expr
        self.values = values
        self.subquery = subquery
        self.is_not = is_not

    def to_sql(self) -> str:
        op = "NOT IN" if self.is_not else "IN"
        if self.subquery:
            return f"{self.expr.to_sql()} {op} ({self.subquery})"
        vals = ", ".join(v.to_sql() for v in self.values)
        return f"{self.expr.to_sql()} {op} ({vals})"

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        if not isinstance(self.expr, ColumnRefExpr):
            return None
        return _in_expr_to_legacy(self.expr, self.values, self.subquery, self.is_not)


class IsNullExpr(SQLExpr):
    """Represents an expr IS [NOT] NULL predicate."""

    def __init__(self, expr: SQLExpr, is_not: bool = False) -> None:
        self.expr = expr
        self.is_not = is_not

    def to_sql(self) -> str:
        op = "IS NOT NULL" if self.is_not else "IS NULL"
        return f"{self.expr.to_sql()} {op}"

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        if isinstance(self.expr, ColumnRefExpr):
            op = "IS NOT NULL" if self.is_not else "IS NULL"
            return {
                "column": self.expr.full_name,
                "operator": op,
                "value": None,
            }
        return None


def _like_expr_to_legacy(
    col: ColumnRefExpr,
    pat: LiteralExpr,
    operator: str,
    escape: Optional[str],
    is_not: bool,
) -> Dict[str, Any]:
    op = f"NOT {operator}" if (is_not and not operator.startswith("NOT")) else operator
    d: Dict[str, Any] = {
        "column": col.full_name,
        "operator": op,
        "value": pat.value,
    }
    if escape:
        d["escape"] = escape
    return d


class LikeExpr(SQLExpr):
    """Represents LIKE, GLOB, or MATCH predicate."""

    def __init__(
        self,
        expr: SQLExpr,
        pattern: SQLExpr,
        operator: str = "LIKE",
        escape: Optional[str] = None,
        is_not: bool = False,
    ) -> None:
        self.expr = expr
        self.pattern = pattern
        self.operator = operator.upper()
        self.escape = escape
        self.is_not = is_not

    def to_sql(self) -> str:
        prefix = "NOT " if self.is_not else ""
        esc = f" ESCAPE '{self.escape}'" if self.escape else ""
        return (
            f"{self.expr.to_sql()} {prefix}{self.operator} {self.pattern.to_sql()}{esc}"
        )

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        if isinstance(self.expr, ColumnRefExpr) and isinstance(
            self.pattern, LiteralExpr
        ):
            return _like_expr_to_legacy(
                self.expr,
                self.pattern,
                self.operator,
                self.escape,
                self.is_not,
            )
        return None


class FunctionCallExpr(SQLExpr):
    """Represents a SQL function invocation (e.g. COUNT(*), LOWER(x))."""

    def __init__(
        self,
        name: str,
        args: List[SQLExpr],
        is_star: bool = False,
        is_distinct: bool = False,
    ) -> None:
        self.name = name.upper()
        self.args = args
        self.is_star = is_star
        self.is_distinct = is_distinct

    @property
    def func_name(self) -> str:
        return self.name

    def to_sql(self) -> str:
        if self.is_star:
            return f"{self.name}(*)"
        dist = "DISTINCT " if self.is_distinct else ""
        arg_str = ", ".join(a.to_sql() for a in self.args)
        return f"{self.name}({dist}{arg_str})"

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        return None


class CaseExpr(SQLExpr):
    """Represents a CASE [base] WHEN c THEN r ... [ELSE d] END expression."""

    def __init__(
        self,
        base_expr: Optional[SQLExpr],
        when_then_list: List[Tuple[SQLExpr, SQLExpr]],
        else_expr: Optional[SQLExpr] = None,
    ) -> None:
        self.base_expr = base_expr
        self.when_then_list = when_then_list
        self.else_expr = else_expr

    @property
    def when_branches(self) -> List[Tuple[SQLExpr, SQLExpr]]:
        return self.when_then_list

    def to_sql(self) -> str:
        parts = ["CASE"]
        if self.base_expr:
            parts.append(self.base_expr.to_sql())
        for cond, res in self.when_then_list:
            parts.append(f"WHEN {cond.to_sql()} THEN {res.to_sql()}")
        if self.else_expr:
            parts.append(f"ELSE {self.else_expr.to_sql()}")
        parts.append("END")
        return " ".join(parts)

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        return None


_ALLOWED_COLLATIONS: set[str] = {"BINARY", "NOCASE", "RTRIM"}


class CollateExpr(SQLExpr):
    """Represents an expression with COLLATE collation_name."""

    def __init__(self, expr: SQLExpr, collation: str) -> None:
        self.expr = expr
        c_up = collation.strip().upper()
        if c_up not in _ALLOWED_COLLATIONS:
            from .parser import SQLParseError

            raise SQLParseError(f"no such collation sequence: {collation.strip()}")
        self.collation = c_up

    def to_sql(self) -> str:
        return f"{self.expr.to_sql()} COLLATE {self.collation}"

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        d = self.expr.to_legacy_dict()
        if d is not None:
            res = dict(d)
            res["collate"] = self.collation
            return res
        return None


class ExistsExpr(SQLExpr):
    """Represents [NOT] EXISTS (subquery) predicate."""

    def __init__(self, subquery: str, is_not: bool = False) -> None:
        self.subquery = subquery.strip()
        self.is_not = is_not

    def to_sql(self) -> str:
        op = "NOT EXISTS" if self.is_not else "EXISTS"
        return f"{op} ({self.subquery})"

    def to_legacy_dict(self) -> Optional[Dict[str, Any]]:
        op = "NOT EXISTS" if self.is_not else "EXISTS"
        return {
            "column": "*",
            "operator": op,
            "subquery": self.subquery,
        }


def _tok(p: Parser[Any]) -> Parser[Any]:
    ws = Reg(r"(\s+|#[^\r\n]*)*")
    return Seq(p, ws).map(lambda r: r[0])


def _kw(word: str) -> Parser[str]:
    """Case-insensitive SQL keyword parser with trailing whitespace stripping."""
    return _tok(Reg(rf"(?i){word}\b")).map(lambda s: s.upper())


def _fold_binary_chain(r: List[Any]) -> SQLExpr:
    first = cast(SQLExpr, r[0])
    pairs = cast(List[Tuple[str, SQLExpr]], r[1])
    node = first
    for op, right in pairs:
        node = BinaryOpExpr(op, node, right)
    return node


def _build_number_parser() -> Parser[SQLExpr]:
    num_re = Reg(r"[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?")

    def _parse_num(s: str) -> SQLExpr:
        if "." in s or "e" in s or "E" in s:
            return LiteralExpr(float(s))
        return LiteralExpr(int(s))

    return _tok(num_re).map(_parse_num)


def _build_string_parser() -> Parser[SQLExpr]:
    single_quote = Reg(r"'([^']|'')*'")
    double_quote = Reg(r'"([^"\\]|\\.)*"')

    def _strip_quote(s: str) -> SQLExpr:
        if s.startswith("'"):
            content = s[1:-1].replace("''", "'")
            return LiteralExpr(content)
        return LiteralExpr(s[1:-1])

    return _tok(Choice(single_quote, double_quote)).map(_strip_quote)


def _build_literal_parser() -> Parser[SQLExpr]:
    b_true = _kw("TRUE").map(lambda _: LiteralExpr(True))
    b_false = _kw("FALSE").map(lambda _: LiteralExpr(False))
    null_val = _kw("NULL").map(lambda _: LiteralExpr(None))
    num = _build_number_parser()
    s = _build_string_parser()
    return Choice(b_true, b_false, null_val, num, s)


def _build_column_ref_parser() -> Parser[SQLExpr]:
    ident = Reg(r"[a-zA-Z_][a-zA-Z0-9_]*")
    json_extract = Seq(
        ident,
        Opt(Seq(_tok(Lit(".")), ident)),
        Opt(Seq(_tok(Lit("->>")), _tok(Reg(r"'[^']*'")))),
    )

    def _make_col(r: List[Any]) -> SQLExpr:
        first = str(r[0])
        tbl: Optional[str] = None
        col = first
        if r[1]:
            tbl = first
            col = str(r[1][1])
        path: Optional[str] = None
        if r[2]:
            path = str(r[2][1]).strip("'\"")
        return ColumnRefExpr(column=col, table=tbl, json_path=path)

    return _tok(json_extract).map(_make_col)


def _build_func_call_parser(expr_ref: RuleRef) -> Parser[SQLExpr]:
    fname = _tok(Reg(r"[a-zA-Z_][a-zA-Z0-9_]*"))
    star_arg = Seq(_tok(Lit("(")), _tok(Lit("*")), _tok(Lit(")"))).map(lambda _: True)

    arg_list = Seq(
        _tok(Lit("(")),
        Opt(_kw("DISTINCT")),
        expr_ref,
        ZeroOrMore(Seq(_tok(Lit(",")), expr_ref)),
        _tok(Lit(")")),
    )

    def _make_arg_call(name: str, r: List[Any]) -> SQLExpr:
        is_dist = bool(r[1])
        args = [cast(SQLExpr, r[2])] + [
            cast(SQLExpr, item[1]) for item in cast(List[Any], r[3])
        ]
        return FunctionCallExpr(name, args, is_distinct=is_dist)

    def _make_func(name_str: str, args_res: Any) -> SQLExpr:
        if args_res is True:
            return FunctionCallExpr(name_str, [], is_star=True)
        return _make_arg_call(name_str, cast(List[Any], args_res))

    return Seq(fname, Choice(star_arg, arg_list)).map(
        lambda r: _make_func(str(r[0]), r[1])
    )


def _build_case_parser(expr_ref: RuleRef, atom_ref: Parser[SQLExpr]) -> Parser[SQLExpr]:
    when_then = Seq(
        _kw("WHEN"),
        expr_ref,
        _kw("THEN"),
        expr_ref,
    ).map(lambda r: (cast(SQLExpr, r[1]), cast(SQLExpr, r[3])))

    else_tail = Seq(_kw("ELSE"), expr_ref).map(lambda r: cast(SQLExpr, r[1]))

    # Searched CASE: CASE WHEN ...
    searched_case = Seq(
        _kw("CASE"),
        OneOrMore(when_then),
        Opt(else_tail),
        _kw("END"),
    ).map(
        lambda r: CaseExpr(
            base_expr=None,
            when_then_list=cast(List[Tuple[SQLExpr, SQLExpr]], r[1]),
            else_expr=cast(Optional[SQLExpr], r[2]),
        )
    )

    # Simple CASE: CASE <atom> WHEN ...
    simple_case = Seq(
        _kw("CASE"),
        atom_ref,
        OneOrMore(when_then),
        Opt(else_tail),
        _kw("END"),
    ).map(
        lambda r: CaseExpr(
            base_expr=cast(SQLExpr, r[1]),
            when_then_list=cast(List[Tuple[SQLExpr, SQLExpr]], r[2]),
            else_expr=cast(Optional[SQLExpr], r[3]),
        )
    )

    return Choice(searched_case, simple_case)


def _build_primary_parser(expr_ref: RuleRef) -> Parser[SQLExpr]:
    paren = Seq(_tok(Lit("(")), expr_ref, _tok(Lit(")"))).map(
        lambda r: cast(SQLExpr, r[1])
    )
    func_p = _build_func_call_parser(expr_ref)
    lit_p = _build_literal_parser()
    col_p = _build_column_ref_parser()
    atom = Choice(paren, func_p, lit_p, col_p)
    case_p = _build_case_parser(expr_ref, atom)
    return Choice(paren, case_p, func_p, lit_p, col_p)


def _build_unary_parser(expr_ref: RuleRef) -> Parser[SQLExpr]:
    primary = _build_primary_parser(expr_ref)
    exists_p = Seq(
        Opt(_kw("NOT")),
        _kw("EXISTS"),
        _tok(Lit("(")),
        Reg(r"[^)]+"),
        _tok(Lit(")")),
    ).map(lambda r: ExistsExpr(str(r[3]), is_not=bool(r[0])))
    u_op = Choice(
        _tok(Lit("+")),
        _tok(Lit("-")),
        _kw("NOT"),
    )
    return Choice(
        exists_p,
        Seq(u_op, primary).map(lambda r: UnaryOpExpr(str(r[0]), cast(SQLExpr, r[1]))),
        primary,
    )


def _build_mult_parser(expr_ref: RuleRef) -> Parser[SQLExpr]:
    unary = _build_unary_parser(expr_ref)
    m_op = Choice(
        _tok(Lit("*")),
        _tok(Lit("/")),
        _tok(Lit("%")),
    )
    return Seq(
        unary,
        ZeroOrMore(Seq(m_op, unary).map(lambda r: (str(r[0]), cast(SQLExpr, r[1])))),
    ).map(_fold_binary_chain)


def _build_add_parser(expr_ref: RuleRef) -> Parser[SQLExpr]:
    mult = _build_mult_parser(expr_ref)
    a_op = Choice(
        _tok(Lit("+")),
        _tok(Lit("-")),
    )
    return Seq(
        mult,
        ZeroOrMore(Seq(a_op, mult).map(lambda r: (str(r[0]), cast(SQLExpr, r[1])))),
    ).map(_fold_binary_chain)


def _build_is_null_suffix() -> Parser[Tuple[str, bool]]:
    return Seq(
        _kw("IS"),
        Opt(_kw("NOT")),
        _kw("NULL"),
    ).map(lambda r: ("IS_NULL", bool(r[1])))


def _build_between_suffix(
    add: Parser[SQLExpr],
) -> Parser[Tuple[str, bool, SQLExpr, SQLExpr]]:
    return Seq(
        Opt(_kw("NOT")),
        _kw("BETWEEN"),
        add,
        _kw("AND"),
        add,
    ).map(lambda r: ("BETWEEN", bool(r[0]), cast(SQLExpr, r[2]), cast(SQLExpr, r[4])))


def _build_like_suffix(
    add: Parser[SQLExpr],
) -> Parser[Tuple[str, bool, str, SQLExpr, Optional[str]]]:
    like_op = Choice(_kw("LIKE"), _kw("GLOB"), _kw("MATCH"))
    return Seq(
        Opt(_kw("NOT")),
        like_op,
        add,
        Opt(Seq(_kw("ESCAPE"), _tok(Reg(r"'[^']*'")))),
    ).map(
        lambda r: (
            "LIKE",
            bool(r[0]),
            str(r[1]),
            cast(SQLExpr, r[2]),
            str(r[3][1])[1:-1] if r[3] else None,
        )
    )


def _build_in_suffix(
    add: Parser[SQLExpr],
) -> Parser[Tuple[str, bool, Optional[List[SQLExpr]], Optional[str]]]:
    in_subquery = Seq(
        _tok(Lit("(")),
        _tok(Reg(r"(?i)SELECT\b[^;)]*(?:\([^;)]*\)[^;)]*)*")),
        _tok(Lit(")")),
    ).map(lambda r: (None, str(r[1]).strip()))
    in_val_list = Seq(
        _tok(Lit("(")),
        add,
        ZeroOrMore(Seq(_tok(Lit(",")), add)),
        _tok(Lit(")")),
    ).map(
        lambda r: (
            [cast(SQLExpr, r[1])]
            + [cast(SQLExpr, item[1]) for item in cast(List[Any], r[2])],
            None,
        )
    )
    in_body = Choice(in_subquery, in_val_list)
    return Seq(
        Opt(_kw("NOT")),
        _kw("IN"),
        in_body,
    ).map(lambda r: ("IN", bool(r[0]), r[2][0], r[2][1]))


def _build_cmp_suffix(add: Parser[SQLExpr]) -> Parser[Tuple[str, str, SQLExpr]]:
    cmp_op = Choice(
        _tok(Lit(">=")),
        _tok(Lit("<=")),
        _tok(Lit("<>")),
        _tok(Lit("!=")),
        _tok(Lit("=")),
        _tok(Lit(">")),
        _tok(Lit("<")),
    )
    return Seq(cmp_op, add).map(lambda r: ("CMP", str(r[0]), cast(SQLExpr, r[1])))


def _dispatch_match_or_in(base: SQLExpr, suf: Any) -> SQLExpr:
    kind = suf[0]
    if kind == "LIKE":
        return LikeExpr(base, suf[3], operator=suf[2], escape=suf[4], is_not=suf[1])
    if kind == "IN":
        return InExpr(base, suf[2] or [], subquery=suf[3], is_not=suf[1])
    return BinaryOpExpr(suf[1], base, suf[2])


def _dispatch_pred(base: SQLExpr, suf: Any) -> SQLExpr:
    kind = suf[0]
    if kind == "IS_NULL":
        return IsNullExpr(base, is_not=suf[1])
    if kind == "BETWEEN":
        return BetweenExpr(base, suf[2], suf[3], is_not=suf[1])
    return _dispatch_match_or_in(base, suf)


def _build_predicate_parser(expr_ref: RuleRef) -> Parser[SQLExpr]:
    add = _build_add_parser(expr_ref)
    is_null = _build_is_null_suffix()
    between_p = _build_between_suffix(add)
    like_p = _build_like_suffix(add)
    in_p = _build_in_suffix(add)
    cmp_p = _build_cmp_suffix(add)
    pred_suffix = Choice(is_null, between_p, like_p, in_p, cmp_p)
    collate_suffix = Opt(Seq(_kw("COLLATE"), _tok(Reg(r"[a-zA-Z0-9_]+"))))

    def _resolve_pred(r: List[Any]) -> SQLExpr:
        base = cast(SQLExpr, r[0])
        suf = r[1]
        coll = r[2]
        expr = _dispatch_pred(base, suf) if suf else base
        if coll:
            return CollateExpr(expr, str(coll[1]))
        return expr

    return Seq(add, Opt(pred_suffix), collate_suffix).map(_resolve_pred)


def _build_and_parser(expr_ref: RuleRef) -> Parser[SQLExpr]:
    pred = _build_predicate_parser(expr_ref)
    return Seq(
        pred,
        ZeroOrMore(Seq(_kw("AND"), pred).map(lambda r: ("AND", cast(SQLExpr, r[1])))),
    ).map(_fold_binary_chain)


def _build_or_parser(expr_ref: RuleRef) -> Parser[SQLExpr]:
    and_p = _build_and_parser(expr_ref)
    return Seq(
        and_p,
        ZeroOrMore(Seq(_kw("OR"), and_p).map(lambda r: ("OR", cast(SQLExpr, r[1])))),
    ).map(_fold_binary_chain)


from database.sql.generated_sql_expr_parser import (  # noqa: E402
    SQLExprParser as _AOTSQLExprParser,
)


class SQLExpressionParser:
    """Packrat PEG Parser for SQL expressions with operator precedence and nested parens.

    Delegates to AOT-compiled SQLExprParser for sub-millisecond parsing and zero startup overhead.
    """

    def __init__(self) -> None:
        self._aot_parser = _AOTSQLExprParser()

    def parse(self, text: str) -> SQLExpr:
        """Parses a SQL expression string into an SQLExpr AST."""
        stripped = text.strip()
        if not stripped:
            raise ValueError("Empty SQL expression")
        return cast(SQLExpr, self._aot_parser.parse(stripped))


def parse_sql_expr(text: str) -> SQLExpr:
    """Convenience helper to parse a SQL expression string."""
    parser = SQLExpressionParser()
    return parser.parse(text)
