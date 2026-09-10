#!/usr/bin/env python3
"""src/cli/formatter.py

Pure-Python ASCII border table formatter for query results and CLI inspection.
Conforms to DSN-24 Section 4.4, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import shutil
from typing import Any, Dict, List, Sequence


def _stringify_value(val: Any) -> str:
    """Formats a scalar or compound value into a display string."""
    if val is None:
        return "NULL"
    if isinstance(val, (dict, list)):
        import json

        return json.dumps(val, ensure_ascii=False)
    return str(val)


def _compute_col_width(header: str, values: Sequence[str], max_cell: int) -> int:
    """Computes the appropriate column width capped by max_cell."""
    max_len = len(header)
    for v in values:
        if len(v) > max_len:
            max_len = len(v)
    return min(max_len, max_cell)


def _calculate_widths(
    headers: List[str], rows: List[List[str]], term_width: int
) -> List[int]:
    """Calculates column widths keeping total within terminal bounds."""
    num_cols = len(headers)
    if num_cols == 0:
        return []

    overhead = num_cols * 3 + 1
    avail = max(40, term_width - overhead)
    max_per_col = max(10, avail // num_cols * 2)

    widths: List[int] = []
    for idx, header in enumerate(headers):
        col_vals = [r[idx] for r in rows]
        w = _compute_col_width(header, col_vals, max_per_col)
        widths.append(max(w, len(header), 4))
    return widths


def _render_border(widths: List[int]) -> str:
    """Builds a horizontal border line like +------+------+."""
    parts = ["-" * (w + 2) for w in widths]
    return "+" + "+".join(parts) + "+"


def _format_cell(text: str, width: int) -> str:
    """Pads or truncates text to fit exactly in width."""
    if len(text) > width:
        return text[: width - 3] + "..." if width > 3 else text[:width]
    return text.ljust(width)


def _render_row(cells: List[str], widths: List[int]) -> str:
    """Formats a single row with vertical pipes."""
    formatted = [_format_cell(c, widths[i]) for i, c in enumerate(cells)]
    return "| " + " | ".join(formatted) + " |"


def _assemble_table_lines(
    border: str, header_line: str, rows: List[List[str]], widths: List[int]
) -> List[str]:
    lines = [border, header_line, border]
    for r in rows:
        lines.append(_render_row(r, widths))
    lines.append(border)
    return lines


def format_ascii_table(
    headers: List[str],
    data_rows: List[List[Any]],
    max_width: int | None = None,
) -> str:
    """Renders tabular data into a GitHub/psql-styled ASCII bordered table."""
    if not headers:
        return ""

    term_width = max_width or shutil.get_terminal_size((80, 24)).columns
    str_rows = [[_stringify_value(c) for c in row] for row in data_rows]
    widths = _calculate_widths(headers, str_rows, term_width)

    border = _render_border(widths)
    header_line = _render_row(headers, widths)
    lines = _assemble_table_lines(border, header_line, str_rows, widths)
    return "\n".join(lines)


def format_query_result(rows: List[Dict[str, Any]]) -> str:
    """Formats a list of row dictionaries (SQLExecutor output) into an ASCII table."""
    if not rows:
        return "(0 rows)"

    headers = list(rows[0].keys())
    data = [[row.get(h) for h in headers] for row in rows]
    return format_ascii_table(headers, data)
