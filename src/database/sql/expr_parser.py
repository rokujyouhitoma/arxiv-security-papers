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
