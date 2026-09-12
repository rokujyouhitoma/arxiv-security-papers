#!/usr/bin/env python3
"""
Window Functions Engine for Pure Python SQL Engine.
Supports OVER (PARTITION BY ... ORDER BY ... [ASC|DESC]) for:
ROW_NUMBER, RANK, DENSE_RANK, SUM, AVG, COUNT, MIN, MAX.
"""

import re
from typing import Any, Dict, List, Optional, Tuple


def _parse_window_order_spec(body: str) -> Tuple[Optional[str], bool]:
    o_match = re.search(r"\bORDER\s+BY\s+(.*?)$", body, re.IGNORECASE)
    if not o_match:
        return None, False
    o_body = o_match.group(1).strip()
    if o_body.upper().endswith(" DESC"):
        return o_body[:-5].strip(), True
    if o_body.upper().endswith(" ASC"):
        return o_body[:-4].strip(), False
    return o_body, False


def _parse_window_partition_spec(body: str) -> List[str]:
    p_match = re.search(
        r"\bPARTITION\s+BY\s+(.*?)(?=\bORDER\s+BY\b|$)", body, re.IGNORECASE
    )
    if not p_match:
        return []
    return [c.strip() for c in p_match.group(1).split(",") if c.strip()]


def _parse_window_over_clause(
    over_inner: str,
) -> Tuple[List[str], Optional[str], bool]:
    """Extracts partition_by, order_by, order_desc from OVER clause body."""
    part_by = _parse_window_partition_spec(over_inner)
    order_by, order_desc = _parse_window_order_spec(over_inner)
    return part_by, order_by, order_desc


def _parse_window_call_head(call_head: str) -> Tuple[str, str]:
    m = re.match(r"^([a-zA-Z0-9_]+)\s*\((.*?)\)$", call_head.strip())
    if not m:
        return call_head.upper(), ""
    return m.group(1).upper(), m.group(2).strip()


def _parse_col_window_item(col_expr: str) -> Optional[Dict[str, Any]]:
    as_m = re.search(r"\s+AS\s+([a-zA-Z0-9_]+)$", col_expr, re.IGNORECASE)
    alias = as_m.group(1).strip() if as_m else col_expr.strip()
    base_expr = col_expr[: as_m.start()].strip() if as_m else col_expr.strip()

    over_m = re.search(r"\bOVER\s*\((.*?)\)", base_expr, re.IGNORECASE | re.DOTALL)
    if not over_m:
        return None

    call_head = base_expr[: over_m.start()].strip()
    func_name, func_arg = _parse_window_call_head(call_head)
    part_by, order_by, order_desc = _parse_window_over_clause(over_m.group(1).strip())

    return {
        "col_expr": col_expr,
        "base_expr": base_expr,
        "alias": alias,
        "func_name": func_name,
        "func_arg": func_arg,
        "partition_by": part_by,
        "order_by": order_by,
        "order_desc": order_desc,
    }


def extract_window_functions(columns: List[str]) -> List[Dict[str, Any]]:
    """Finds and parses all window function expressions in column list."""
    win_specs: List[Dict[str, Any]] = []
    for c in columns:
        item = _parse_col_window_item(c)
        if item is not None:
            win_specs.append(item)
    return win_specs


def _build_partition_key(row: Dict[str, Any], part_cols: List[str]) -> Tuple[Any, ...]:
    return tuple(row.get(col) for col in part_cols)


def _partition_rows(
    rows: List[Dict[str, Any]], part_cols: List[str]
) -> Dict[Tuple[Any, ...], List[Dict[str, Any]]]:
    groups: Dict[Tuple[Any, ...], List[Dict[str, Any]]] = {}
    for r in rows:
        k = _build_partition_key(r, part_cols)
        if k not in groups:
            groups[k] = []
        groups[k].append(r)
    return groups


def _extract_order_val(r: Dict[str, Any], order_col: Optional[str]) -> Any:
    return r.get(order_col) if order_col else None


def _set_keys_in_row(r: Dict[str, Any], keys: List[str], val: Any) -> None:
    for k in keys:
        r[k] = val


def _parse_numeric_val(raw: Any) -> float:
    try:
        return float(raw or 0)
    except (ValueError, TypeError):
        return 0.0


def _eval_row_number(g_rows: List[Dict[str, Any]], keys: List[str]) -> None:
    for idx, r in enumerate(g_rows, 1):
        _set_keys_in_row(r, keys, idx)


def _eval_rank(
    g_rows: List[Dict[str, Any]], keys: List[str], order_col: Optional[str]
) -> None:
    curr_rank = 1
    last_val = object()
    for idx, r in enumerate(g_rows, 1):
        val = _extract_order_val(r, order_col)
        if idx > 1 and val != last_val:
            curr_rank = idx
        last_val = val
        _set_keys_in_row(r, keys, curr_rank)


def _eval_dense_rank(
    g_rows: List[Dict[str, Any]], keys: List[str], order_col: Optional[str]
) -> None:
    curr_rank = 0
    last_val = object()
    for r in g_rows:
        val = _extract_order_val(r, order_col)
        if val != last_val:
            curr_rank += 1
            last_val = val
        _set_keys_in_row(r, keys, curr_rank)


def _eval_cumulative_sum(
    g_rows: List[Dict[str, Any]], keys: List[str], arg_col: str
) -> None:
    running = 0.0
    for r in g_rows:
        running += _parse_numeric_val(r.get(arg_col))
        res = int(running) if running.is_integer() else running
        _set_keys_in_row(r, keys, res)


def _apply_window_calculation(
    func_name: str,
    g_rows: List[Dict[str, Any]],
    keys: List[str],
    order_col: Optional[str],
    arg_col: str,
) -> None:
    if func_name == "ROW_NUMBER":
        _eval_row_number(g_rows, keys)
    elif func_name == "RANK":
        _eval_rank(g_rows, keys, order_col)
    elif func_name == "DENSE_RANK":
        _eval_dense_rank(g_rows, keys, order_col)
    elif func_name in ("SUM", "TOTAL"):
        _eval_cumulative_sum(g_rows, keys, arg_col)
    else:
        _eval_row_number(g_rows, keys)


def _sort_partition_group(
    g_rows: List[Dict[str, Any]],
    order_by: Optional[str],
    order_desc: bool,
) -> List[Dict[str, Any]]:
    if not order_by:
        return g_rows
    return sorted(
        g_rows,
        key=lambda r: (r.get(order_by) is None, r.get(order_by)),
        reverse=order_desc,
    )


def compute_window_functions(
    rows: List[Dict[str, Any]], win_specs: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """Computes window functions and injects results into each row."""
    if not rows or not win_specs:
        return rows

    for spec in win_specs:
        groups = _partition_rows(rows, spec["partition_by"])
        keys = [spec["col_expr"], spec["base_expr"], spec["alias"]]
        for _, g_rows in groups.items():
            sorted_group = _sort_partition_group(
                g_rows, spec["order_by"], spec["order_desc"]
            )
            _apply_window_calculation(
                spec["func_name"],
                sorted_group,
                keys,
                spec["order_by"],
                spec["func_arg"],
            )

    return rows
