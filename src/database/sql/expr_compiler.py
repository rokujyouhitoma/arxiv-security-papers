#!/usr/bin/env python3
"""Precompiler for SQL Expression ASTs into Reusable Row-Evaluation Closures.

Compiles typed ``SQLExpr`` AST nodes (from ``expr_parser.py``) and structured
WHERE / PROJECTION / HAVING clauses once per query into pure Python closures,
eliminating per-record regex matching and string re-parsing in ``executor.py``.

Security controls:
- Bounded AST recursion depth (``MAX_EXPR_AST_DEPTH = 64``, CWE-674)
- ReDoS-safe ``LIKE`` regex compilation with ``%`` collapsing & length cap (CWE-400)
- Bounded LRU compilation caches (CWE-400)
- Zero ``eval`` / ``exec`` / dynamic code generation (CWE-94)
"""

from __future__ import annotations

import fnmatch
import functools
import json
import math
import re
from typing import (
    Any,
    Callable,
    Dict,
    FrozenSet,
    List,
    Optional,
    Pattern,
    Sequence,
    Set,
    Tuple,
    Type,
    cast,
)

from .ast import SQLExecutionError
from .expr_parser import (
    BetweenExpr,
    BinaryOpExpr,
    CaseExpr,
    CollateExpr,
    ColumnRefExpr,
    ExistsExpr,
    FunctionCallExpr,
    InExpr,
    IsNullExpr,
    LikeExpr,
    LiteralExpr,
    SQLExpr,
    UnaryOpExpr,
    parse_sql_expr,
)
from .functions import BUILTIN_FUNCTIONS

MAX_EXPR_AST_DEPTH: int = 64
MAX_LIKE_PATTERN_LEN: int = 1024

RowEvaluator = Callable[[Dict[str, Any]], Any]
RowPredicate = Callable[[Dict[str, Any]], bool]
SubqueryRunner = Callable[[str, Dict[str, Any]], List[Dict[str, Any]]]
MatchRunner = Callable[[Dict[str, Any], str, str], bool]

_AS_ALIAS_RE = re.compile(r"\s+AS\s+([a-zA-Z0-9_]+)$", re.IGNORECASE)
_HAVING_CMP_RE = re.compile(r"^(.+?)\s*(=|!=|<>|>=|<=|>|<)\s*(.+)$")
_MULTI_PCT_RE = re.compile(r"%+")

_ARITH_OPS: Dict[str, Callable[[float, float], Optional[float]]] = {
    "+": lambda a, b: a + b,
    "-": lambda a, b: a - b,
    "*": lambda a, b: a * b,
    "/": lambda a, b: a / b if b != 0 else None,
    "%": lambda a, b: math.fmod(a, b) if b != 0 else None,
}
_REL_OPS: Dict[str, Callable[[Any, Any], bool]] = {
    ">=": lambda a, b: bool(a >= b),
    "<=": lambda a, b: bool(a <= b),
    ">": lambda a, b: bool(a > b),
    "<": lambda a, b: bool(a < b),
}
_HAVING_OPS: Dict[str, Callable[[Any, Any], bool]] = {
    "=": lambda a, b: bool(a == b),
    "==": lambda a, b: bool(a == b),
    "!=": lambda a, b: bool(a != b),
    "<>": lambda a, b: bool(a != b),
    ">": lambda a, b: bool(a > b),
    ">=": lambda a, b: bool(a >= b),
    "<": lambda a, b: bool(a < b),
    "<=": lambda a, b: bool(a <= b),
}


def is_sql_truthy(val: Any) -> bool:
    """Evaluates SQL truthiness consistently with legacy executor semantics."""
    return bool(val and val != 0 and val != "0" and val is not False)


def collate_transform(val: Any, collation: Optional[str]) -> Any:
    """Applies collation transformation to string values."""
    if not isinstance(val, str) or not collation:
        return val
    col = collation.upper()
    if col == "NOCASE":
        return val.lower()
    if col == "RTRIM":
        return val.rstrip(" ")
    return val


def _escape_like_segment(seg: str) -> str:
    collapsed = _MULTI_PCT_RE.sub("%", seg)
    return re.escape(collapsed).replace("%", ".*").replace("_", ".")


def _build_escaped_like_regex(exp_str: str, escape: str) -> str:
    parts = re.split(re.escape(escape) + "(.)", exp_str)
    out: List[str] = []
    for idx, part in enumerate(parts):
        out.append(re.escape(part) if idx % 2 == 1 else _escape_like_segment(part))
    return f"^{''.join(out)}$"


@functools.lru_cache(maxsize=1024)
def compile_like_pattern(pattern: str, escape: Optional[str] = None) -> Pattern[str]:
    """Compiles a SQL LIKE pattern into a ReDoS-safe case-insensitive regex."""
    if len(pattern) > MAX_LIKE_PATTERN_LEN:
        raise SQLExecutionError(
            f"LIKE pattern length exceeds limit ({MAX_LIKE_PATTERN_LEN})"
        )
    if escape:
        regex_str = _build_escaped_like_regex(pattern, escape)
    else:
        regex_str = f"^{_escape_like_segment(pattern)}$"
    return re.compile(regex_str, re.IGNORECASE)


def eval_is_null(op: str, actual: Any) -> bool:
    """Evaluates IS NULL / IS NOT NULL."""
    is_n = actual is None or actual == ""
    return is_n if op == "IS NULL" else not is_n


def eval_between(
    op: str, actual: Any, expected: Any, collate: Optional[str] = None
) -> bool:
    """Evaluates BETWEEN / NOT BETWEEN."""
    if not isinstance(expected, (list, tuple)) or len(expected) != 2:
        return False
    v1, v2 = expected
    try:
        res = float(str(v1)) <= float(str(actual)) <= float(str(v2))
    except (ValueError, TypeError):
        act_s = str(collate_transform(actual, collate))
        v1_s = str(collate_transform(v1, collate))
        v2_s = str(collate_transform(v2, collate))
        res = v1_s <= act_s <= v2_s
    return res if op == "BETWEEN" else not res


def _eval_numeric_rel(op: str, actual: Any, expected: Any) -> Optional[bool]:
    is_num = isinstance(actual, (int, float)) and isinstance(expected, (int, float))
    if not is_num or isinstance(actual, bool) or isinstance(expected, bool):
        return None
    return _REL_OPS[op](float(actual), float(expected))


def _eval_relational(op: str, actual: Any, expected: Any) -> bool:
    fast = _eval_numeric_rel(op, actual, expected)
    if fast is not None:
        return fast
    if isinstance(actual, str) and isinstance(expected, str):
        return _REL_OPS[op](actual, expected)
    try:
        return _REL_OPS[op](float(str(actual)), float(str(expected)))
    except (ValueError, TypeError):
        return _REL_OPS[op](str(actual), str(expected))


def _normalize_in_values(expected: Any, collate: Optional[str]) -> List[Any]:
    raw_list = (
        expected if isinstance(expected, (list, tuple, set, frozenset)) else [expected]
    )
    return [collate_transform(x, collate) for x in raw_list]


def _eval_membership(
    op: str, actual: Any, expected: Any, collate: Optional[str] = None
) -> bool:
    norm_act = collate_transform(actual, collate)
    norm_list = _normalize_in_values(expected, collate)
    str_match = str(norm_act) in [str(x) for x in norm_list]
    is_member = norm_act in norm_list or str_match
    return is_member if op == "IN" else not is_member


def _eval_glob_op(op: str, actual: Any, expected: Any) -> bool:
    matched = fnmatch.fnmatchcase(str(actual or ""), str(expected or ""))
    return matched if op == "GLOB" else not matched


def _eval_like_op(op: str, actual: Any, expected: Any, escape: Optional[str]) -> bool:
    pat = compile_like_pattern(str(expected or ""), escape)
    matched = bool(pat.search(str(actual or "")))
    return not matched if "NOT" in op else matched


def _eval_pattern_op(
    op: str,
    actual: Any,
    expected: Any,
    escape: Optional[str] = None,
) -> Optional[bool]:
    if op in ("GLOB", "NOT GLOB"):
        return _eval_glob_op(op, actual, expected)
    if op in ("LIKE", "NOT LIKE"):
        return _eval_like_op(op, actual, expected, escape)
    return None


def _eval_pattern_or_between(
    op: str, actual: Any, expected: Any, c_dict: Optional[Dict[str, Any]]
) -> Optional[bool]:
    if op in ("BETWEEN", "NOT BETWEEN"):
        return eval_between(op, actual, expected, (c_dict or {}).get("collate"))
    return _eval_pattern_op(op, actual, expected, (c_dict or {}).get("escape"))


def _eval_comparison_branches(
    op: str, actual: Any, expected: Any, c_dict: Optional[Dict[str, Any]] = None
) -> bool:
    pat_res = _eval_pattern_or_between(op, actual, expected, c_dict)
    if pat_res is not None:
        return pat_res
    if op in _REL_OPS:
        return _eval_relational(op, actual, expected)
    if op in ("IN", "NOT IN"):
        return _eval_membership(op, actual, expected, (c_dict or {}).get("collate"))
    return True


def _eval_equality(op: str, norm_act: Any, norm_exp: Any) -> Optional[bool]:
    if op == "=":
        return str(norm_act) == str(norm_exp)
    if op in ("!=", "<>"):
        return str(norm_act) != str(norm_exp)
    return None


def eval_comparison(
    op: str, actual: Any, expected: Any, c_dict: Optional[Dict[str, Any]] = None
) -> bool:
    """Evaluates any SQL comparison or predicate operator."""
    if op in ("IS NULL", "IS NOT NULL"):
        return eval_is_null(op, actual)
    collate = (c_dict or {}).get("collate")
    norm_act = collate_transform(actual, collate)
    norm_exp = collate_transform(expected, collate)
    eq_res = _eval_equality(op, norm_act, norm_exp)
    if eq_res is not None:
        return eq_res
    if actual is None:
        return False
    return _eval_comparison_branches(op, norm_act, norm_exp, c_dict)


def _cast_arith_val(res: Optional[float], v1: Any, v2: Any, op: str) -> Optional[Any]:
    if res is None:
        return None
    if isinstance(v1, int) and isinstance(v2, int) and op != "/":
        return int(res)
    return res


def _invoke_arith_fn(
    fn: Callable[[float, float], Optional[float]], v1: Any, v2: Any
) -> Optional[float]:
    try:
        return fn(float(v1), float(v2))
    except (ValueError, TypeError):
        return None


def _safe_eval_arith(op: str, v1: Any, v2: Any) -> Optional[Any]:
    fn = _ARITH_OPS.get(op)
    if fn is None or v1 is None or v2 is None:
        return None
    res = _invoke_arith_fn(fn, v1, v2)
    return _cast_arith_val(res, v1, v2, op)


def _normalize_json_key(raw_path: str) -> str:
    key = raw_path.strip().strip("'\"")
    if key.startswith("$."):
        return key[2:]
    if key.startswith("$"):
        return key[1:]
    return key


def _parse_json_dict(raw_obj: Any) -> Optional[Dict[str, Any]]:
    if isinstance(raw_obj, str):
        try:
            raw_obj = json.loads(raw_obj)
        except Exception:
            return None
    return raw_obj if isinstance(raw_obj, dict) else None


def _lookup_column(record: Dict[str, Any], full_name: str, col: str) -> Any:
    if full_name in record:
        return record[full_name]
    return record.get(col)


def _compile_literal(node: LiteralExpr, _depth: int) -> RowEvaluator:
    val = node.value
    return lambda _r: val


def _compile_json_column(node: ColumnRefExpr) -> RowEvaluator:
    full_name = node.full_name
    col = node.column
    norm_key = _normalize_json_key(node.json_path or "")
    unquote = node.json_unquote

    def _eval(record: Dict[str, Any]) -> Any:
        raw = _lookup_column(record, full_name, col)
        dict_obj = _parse_json_dict(raw)
        if not dict_obj:
            return None
        val = dict_obj.get(norm_key)
        if val is None:
            return None
        return str(val) if unquote else val

    return _eval


def _compile_column_ref(node: ColumnRefExpr, _depth: int) -> RowEvaluator:
    if node.json_path is not None:
        return _compile_json_column(node)
    full_name = node.full_name
    col = node.column
    if full_name == col:
        return lambda r: r.get(col)
    return lambda r: r[full_name] if full_name in r else r.get(col)


def _negate_value(val: Any) -> Any:
    if val is None:
        return None
    try:
        return -val
    except TypeError:
        return None


def _compile_unary(node: UnaryOpExpr, depth: int) -> RowEvaluator:
    inner_fn = _compile_node(node.operand, depth + 1)
    op = node.op
    if op == "NOT":
        return lambda r: not is_sql_truthy(inner_fn(r))
    if op == "-":
        return lambda r: _negate_value(inner_fn(r))
    return inner_fn


def _compile_concat_op(left_fn: RowEvaluator, right_fn: RowEvaluator) -> RowEvaluator:
    def _eval(record: Dict[str, Any]) -> Optional[str]:
        lv = left_fn(record)
        if lv is None:
            return None
        rv = right_fn(record)
        if rv is None:
            return None
        return f"{lv}{rv}"

    return _eval


def _compile_logical_op(
    op: str, left_fn: RowEvaluator, right_fn: RowEvaluator
) -> RowEvaluator:
    if op == "AND":
        return lambda r: is_sql_truthy(left_fn(r)) and is_sql_truthy(right_fn(r))
    return lambda r: is_sql_truthy(left_fn(r)) or is_sql_truthy(right_fn(r))


def _compile_binary(node: BinaryOpExpr, depth: int) -> RowEvaluator:
    left_fn = _compile_node(node.left, depth + 1)
    right_fn = _compile_node(node.right, depth + 1)
    op = node.op
    if op in ("AND", "OR"):
        return _compile_logical_op(op, left_fn, right_fn)
    if op == "||":
        return _compile_concat_op(left_fn, right_fn)
    if op in _ARITH_OPS:
        return lambda r: _safe_eval_arith(op, left_fn(r), right_fn(r))
    return lambda r: eval_comparison(op, left_fn(r), right_fn(r))


def _compile_is_null(node: IsNullExpr, depth: int) -> RowEvaluator:
    inner_fn = _compile_node(node.expr, depth + 1)
    op = "IS NOT NULL" if node.is_not else "IS NULL"
    return lambda r: eval_is_null(op, inner_fn(r))


def _compile_between(node: BetweenExpr, depth: int) -> RowEvaluator:
    expr_fn = _compile_node(node.expr, depth + 1)
    low_fn = _compile_node(node.low, depth + 1)
    high_fn = _compile_node(node.high, depth + 1)
    op = "NOT BETWEEN" if node.is_not else "BETWEEN"
    return lambda r: eval_between(op, expr_fn(r), [low_fn(r), high_fn(r)])


def _safe_frozenset(vals: Sequence[Any]) -> FrozenSet[Any]:
    try:
        return frozenset(vals)
    except TypeError:
        return frozenset()


def _build_const_in_sets(
    values: Sequence[SQLExpr], collate: Optional[str] = None
) -> Optional[Tuple[FrozenSet[Any], FrozenSet[str]]]:
    for v in values:
        if not isinstance(v, LiteralExpr):
            return None
    raw_vals = [collate_transform(cast(LiteralExpr, v).value, collate) for v in values]
    return _safe_frozenset(raw_vals), frozenset(str(v) for v in raw_vals)


def _compile_in(node: InExpr, depth: int) -> RowEvaluator:
    expr_fn = _compile_node(node.expr, depth + 1)
    is_not = node.is_not
    const_sets = _build_const_in_sets(node.values)
    if const_sets is not None:
        val_set, str_set = const_sets

        def _eval_const(record: Dict[str, Any]) -> bool:
            act = expr_fn(record)
            hit = act in val_set or str(act) in str_set
            return not hit if is_not else hit

        return _eval_const
    elem_fns = tuple(_compile_node(v, depth + 1) for v in node.values)
    op = "NOT IN" if is_not else "IN"
    return lambda r: _eval_membership(op, expr_fn(r), [fn(r) for fn in elem_fns])


def _compile_like(node: LikeExpr, depth: int) -> RowEvaluator:
    expr_fn = _compile_node(node.expr, depth + 1)
    is_not = node.is_not
    if node.operator == "LIKE" and isinstance(node.pattern, LiteralExpr):
        compiled_re = compile_like_pattern(str(node.pattern.value or ""), node.escape)

        def _eval_re(record: Dict[str, Any]) -> bool:
            matched = bool(compiled_re.search(str(expr_fn(record) or "")))
            return not matched if is_not else matched

        return _eval_re
    pat_fn = _compile_node(node.pattern, depth + 1)
    op = f"NOT {node.operator}" if is_not else node.operator
    esc = node.escape
    return lambda r: bool(_eval_pattern_op(op, expr_fn(r), pat_fn(r), esc))


def _call_builtin_safe(fn: Callable[..., Any], args: List[Any]) -> Any:
    try:
        return fn(*args)
    except Exception:
        return None


def _compile_function_call(node: FunctionCallExpr, depth: int) -> RowEvaluator:
    fn = BUILTIN_FUNCTIONS.get(node.name)
    if fn is None:
        return lambda _r: None
    arg_fns = tuple(_compile_node(a, depth + 1) for a in node.args)
    return lambda r: _call_builtin_safe(fn, [af(r) for af in arg_fns])


def _compile_simple_case(
    base_fn: RowEvaluator,
    branches: Tuple[Tuple[RowEvaluator, RowEvaluator], ...],
    else_fn: Optional[RowEvaluator],
) -> RowEvaluator:
    def _eval(record: Dict[str, Any]) -> Any:
        base_str = str(base_fn(record))
        for cond_fn, res_fn in branches:
            if base_str == str(cond_fn(record)):
                return res_fn(record)
        return else_fn(record) if else_fn is not None else None

    return _eval


def _compile_searched_case(
    branches: Tuple[Tuple[RowEvaluator, RowEvaluator], ...],
    else_fn: Optional[RowEvaluator],
) -> RowEvaluator:
    def _eval(record: Dict[str, Any]) -> Any:
        for cond_fn, res_fn in branches:
            if is_sql_truthy(cond_fn(record)):
                return res_fn(record)
        return else_fn(record) if else_fn is not None else None

    return _eval


def _compile_case(node: CaseExpr, depth: int) -> RowEvaluator:
    branches = tuple(
        (_compile_node(c, depth + 1), _compile_node(res, depth + 1))
        for c, res in node.when_then_list
    )
    else_fn = _compile_node(node.else_expr, depth + 1) if node.else_expr else None
    if node.base_expr is not None:
        base_fn = _compile_node(node.base_expr, depth + 1)
        return _compile_simple_case(base_fn, branches, else_fn)
    return _compile_searched_case(branches, else_fn)


def _compile_collate(node: CollateExpr, depth: int) -> RowEvaluator:
    inner = node.expr
    col = node.collation
    if isinstance(inner, BinaryOpExpr) and inner.op in (
        "=",
        "!=",
        "<>",
        "<",
        "<=",
        ">",
        ">=",
    ):
        l_fn = _compile_node(inner.left, depth + 1)
        r_fn = _compile_node(inner.right, depth + 1)
        c_dict = {"collate": col}
        return lambda r: eval_comparison(inner.op, l_fn(r), r_fn(r), c_dict)
    inner_fn = _compile_node(inner, depth + 1)
    return lambda r: collate_transform(inner_fn(r), col)


def _compile_exists(_node: ExistsExpr, _depth: int) -> RowEvaluator:
    return lambda _r: None


_NODE_COMPILERS: Dict[Type[SQLExpr], Callable[[Any, int], RowEvaluator]] = {
    LiteralExpr: _compile_literal,
    ColumnRefExpr: _compile_column_ref,
    UnaryOpExpr: _compile_unary,
    BinaryOpExpr: _compile_binary,
    IsNullExpr: _compile_is_null,
    BetweenExpr: _compile_between,
    InExpr: _compile_in,
    LikeExpr: _compile_like,
    FunctionCallExpr: _compile_function_call,
    CaseExpr: _compile_case,
    CollateExpr: _compile_collate,
    ExistsExpr: _compile_exists,
}


def _compile_node(node: SQLExpr, depth: int = 0) -> RowEvaluator:
    if depth > MAX_EXPR_AST_DEPTH:
        raise SQLExecutionError(
            f"SQL expression nesting depth exceeds limit ({MAX_EXPR_AST_DEPTH})"
        )
    compiler = _NODE_COMPILERS.get(type(node))
    if compiler is None:
        return lambda _r: None
    return compiler(node, depth)


def _fallback_lookup_eval(clean: str) -> RowEvaluator:
    def _eval(record: Dict[str, Any]) -> Any:
        if clean in record:
            return record[clean]
        if "." in clean:
            parts = clean.split(".")
            if parts[-1] in record:
                return record[parts[-1]]
            return record.get(".".join(parts[1:]))
        return None

    return _eval


def _wrap_direct_key_lookup(clean: str, inner_fn: RowEvaluator) -> RowEvaluator:
    return lambda r: r[clean] if clean in r else inner_fn(r)


@functools.lru_cache(maxsize=2048)
def compile_sql_expr(expr: str) -> RowEvaluator:
    """Compiles a SQL expression string once into a reusable row evaluator closure."""
    if not expr:
        return lambda _r: None
    clean = expr.strip()
    if not clean:
        return lambda _r: None
    try:
        ast_node = parse_sql_expr(clean)
    except Exception:
        return _fallback_lookup_eval(clean)
    compiled_fn = _compile_node(ast_node, 0)
    return _wrap_direct_key_lookup(clean, compiled_fn)


def _parse_projection_item(col_expr: str) -> Tuple[str, RowEvaluator]:
    stripped = col_expr.strip()
    as_m = _AS_ALIAS_RE.search(stripped)
    if as_m:
        out_key = as_m.group(1).strip()
        raw_col = stripped[: as_m.start()].strip()
        return out_key, compile_sql_expr(raw_col)
    out_key = stripped
    if "." in out_key and "->" not in out_key:
        out_key = out_key.split(".")[-1]
    return out_key, compile_sql_expr(stripped)


def _project_wildcard_row(record: Dict[str, Any], table_name: str) -> Dict[str, Any]:
    prefix = f"{table_name}."
    return {
        k: v
        for k, v in record.items()
        if not k.startswith("_") and ("." not in k or k.startswith(prefix))
    }


def _build_projection_plan(
    columns: List[str],
) -> Tuple[Tuple[str, RowEvaluator], ...]:
    plan: List[Tuple[str, RowEvaluator]] = []
    used_keys: Set[str] = set()
    for col_expr in columns:
        stripped = col_expr.strip()
        k, eval_fn = _parse_projection_item(stripped)
        if k in used_keys:
            k = stripped
        used_keys.add(k)
        plan.append((k, eval_fn))
    return tuple(plan)


def compile_projection(
    columns: List[str], table_name: str
) -> Callable[[Dict[str, Any]], Dict[str, Any]]:
    """Precompiles SELECT projection column aliases and expressions once per query."""
    if "*" in columns and len(columns) == 1:
        return lambda r: _project_wildcard_row(r, table_name)
    frozen_plan = _build_projection_plan(columns)
    return lambda r: {k: fn(r) for k, fn in frozen_plan}


def _compile_expected_resolver(expected_val: Any) -> RowEvaluator:
    if not isinstance(expected_val, str):
        return lambda _r: expected_val
    val_str = expected_val
    compiled_ref = compile_sql_expr(val_str)
    has_sep = "." in val_str or "->" in val_str

    def _resolve(record: Dict[str, Any]) -> Any:
        if has_sep or val_str in record:
            resolved = compiled_ref(record)
            if resolved is not None:
                return resolved
        return val_str

    return _resolve


def _compile_subquery_exists(
    subquery_sql: str, subquery_runner: SubqueryRunner, want_nonempty: bool
) -> RowPredicate:
    return lambda r: (len(subquery_runner(subquery_sql, r)) > 0) == want_nonempty


def _compile_subquery_in(
    c: Dict[str, Any],
    subquery_sql: str,
    subquery_runner: SubqueryRunner,
    want_in: bool,
) -> RowPredicate:
    field_fn = compile_sql_expr(str(c.get("field") or c.get("column") or ""))

    def _eval(record: Dict[str, Any]) -> bool:
        inner_rows = subquery_runner(subquery_sql, record)
        flat_vals = [v for row in inner_rows for v in row.values()]
        actual = field_fn(record)
        hit = actual in flat_vals or str(actual) in (str(x) for x in flat_vals)
        return hit if want_in else not hit

    return _eval


def _read_cond_op(c: Dict[str, Any]) -> str:
    raw = c.get("op")
    if raw is not None:
        return str(raw)
    alt = c.get("operator")
    return str(alt) if alt is not None else "="


def _read_cond_field(c: Dict[str, Any]) -> str:
    raw = c.get("field")
    if raw is not None:
        return str(raw)
    alt = c.get("column")
    return str(alt) if alt is not None else ""


def _compile_subquery_cond(
    c: Dict[str, Any],
    subquery_runner: Optional[SubqueryRunner],
) -> RowPredicate:
    subquery_sql = str(c.get("subquery") or "")
    if subquery_runner is None or not subquery_sql:
        return lambda _r: False
    op = _read_cond_op(c).upper()
    if "EXISTS" in op:
        return _compile_subquery_exists(subquery_sql, subquery_runner, op == "EXISTS")
    return _compile_subquery_in(c, subquery_sql, subquery_runner, op == "IN")


def _compile_match_cond(
    field: str,
    expected_val: Any,
    match_runner: Optional[MatchRunner],
) -> RowPredicate:
    if match_runner is None:
        return lambda _r: False
    exp_fn = _compile_expected_resolver(expected_val)
    return lambda r: match_runner(r, field, str(exp_fn(r)))


def _compile_like_cond(
    c: Dict[str, Any], field_fn: RowEvaluator, op: str, expected_val: Any
) -> Optional[RowPredicate]:
    if op not in ("LIKE", "NOT LIKE") or not isinstance(expected_val, str):
        return None
    if "->" in expected_val:
        return None
    pat_re = compile_like_pattern(expected_val, c.get("escape"))
    is_not = "NOT" in op

    def _eval(record: Dict[str, Any]) -> bool:
        if expected_val in record:
            return eval_comparison(op, field_fn(record), record[expected_val], c)
        matched = bool(pat_re.search(str(field_fn(record) or "")))
        return not matched if is_not else matched

    return _eval


def _compile_const_in_cond(
    c: Dict[str, Any], field_fn: RowEvaluator, op: str, expected_val: Any
) -> Optional[RowPredicate]:
    if op not in ("IN", "NOT IN") or not isinstance(expected_val, (list, tuple, set)):
        return None
    collate = c.get("collate")
    norm_list = [collate_transform(x, collate) for x in expected_val]
    val_set = _safe_frozenset(norm_list)
    str_set = frozenset(str(x) for x in norm_list)
    want_in = op == "IN"

    def _eval(record: Dict[str, Any]) -> bool:
        act = field_fn(record)
        if act is None:
            return False
        norm_act = collate_transform(act, collate)
        hit = norm_act in val_set or str(norm_act) in str_set
        return hit if want_in else not hit

    return _eval


def _compile_standard_condition(
    c: Dict[str, Any], field_fn: RowEvaluator, op: str, expected_val: Any
) -> RowPredicate:
    like_pred = _compile_like_cond(c, field_fn, op, expected_val)
    if like_pred is not None:
        return like_pred
    in_pred = _compile_const_in_cond(c, field_fn, op, expected_val)
    if in_pred is not None:
        return in_pred
    exp_fn = _compile_expected_resolver(expected_val)
    return lambda r: eval_comparison(op, field_fn(r), exp_fn(r), c)


def _compile_single_condition(
    c: Dict[str, Any],
    subquery_runner: Optional[SubqueryRunner] = None,
    match_runner: Optional[MatchRunner] = None,
) -> RowPredicate:
    if "subquery" in c:
        return _compile_subquery_cond(c, subquery_runner)
    field = _read_cond_field(c)
    op = _read_cond_op(c)
    expected_val = c.get("value")
    if op == "MATCH":
        return _compile_match_cond(field, expected_val, match_runner)
    return _compile_standard_condition(c, compile_sql_expr(field), op, expected_val)


def _compile_and_list(
    clauses: List[Dict[str, Any]],
    subquery_runner: Optional[SubqueryRunner],
    match_runner: Optional[MatchRunner],
) -> RowPredicate:
    preds = tuple(
        _compile_single_condition(c, subquery_runner, match_runner) for c in clauses
    )
    return lambda r: all(p(r) for p in preds)


def _compile_or_branches(
    clauses: List[Dict[str, Any]],
    subquery_runner: Optional[SubqueryRunner],
    match_runner: Optional[MatchRunner],
) -> RowPredicate:
    branch_preds = tuple(
        _compile_and_list(c.get("clauses", []), subquery_runner, match_runner)
        for c in clauses
    )
    return lambda r: any(bp(r) for bp in branch_preds)


def compile_where_clauses(
    clauses: List[Dict[str, Any]],
    subquery_runner: Optional[SubqueryRunner] = None,
    match_runner: Optional[MatchRunner] = None,
) -> RowPredicate:
    """Precompiles legacy WHERE/JOIN condition dicts into a single row predicate."""
    if not clauses:
        return lambda _r: True
    for c in clauses:
        if c.get("logic") == "OR_BRANCH":
            return _compile_or_branches(clauses, subquery_runner, match_runner)
    return _compile_and_list(clauses, subquery_runner, match_runner)


def _coerce_having_rhs(raw_rhs: str) -> Tuple[Any, Optional[float]]:
    cleaned = raw_rhs.strip("'\"")
    try:
        return cleaned, float(cleaned)
    except ValueError:
        return cleaned, None


def _resolve_having_lhs(
    row: Dict[str, Any], left_expr: str, upper_left: str, fallback_fn: RowEvaluator
) -> Any:
    if left_expr in row:
        return row[left_expr]
    for k, v in row.items():
        if k.upper() == upper_left:
            return v
    return fallback_fn(row)


@functools.lru_cache(maxsize=1024)
def compile_having_expr(having_expr: str) -> RowPredicate:
    """Precompiles a HAVING clause expression into a row predicate."""
    m = _HAVING_CMP_RE.match(having_expr.strip())
    if not m:
        return lambda _r: True
    left_expr, op, right_expr = (
        m.group(1).strip(),
        m.group(2).strip(),
        m.group(3).strip(),
    )
    cmp_fn = _HAVING_OPS.get(op)
    if cmp_fn is None:
        return lambda _r: False
    upper_left = left_expr.upper()
    fallback_fn = compile_sql_expr(left_expr)
    str_exp, num_exp = _coerce_having_rhs(right_expr)

    def _eval(row: Dict[str, Any]) -> bool:
        act_val = _resolve_having_lhs(row, left_expr, upper_left, fallback_fn)
        is_num = isinstance(act_val, (int, float)) and num_exp is not None
        act, exp = (act_val, num_exp) if is_num else (str(act_val), str_exp)
        try:
            return cmp_fn(act, exp)
        except TypeError:
            return False

    return _eval


def clear_sql_expr_compiler_cache() -> None:
    """Clears all LRU caches maintained by the SQL expression compiler."""
    compile_sql_expr.cache_clear()
    compile_like_pattern.cache_clear()
    compile_having_expr.cache_clear()
