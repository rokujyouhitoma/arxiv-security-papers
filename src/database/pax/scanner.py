#!/usr/bin/env python3
"""
PAX High-Speed Analytics Scanner (OLAP Vector Scanner).
Performs projection-pruned aggregations (COUNT, SUM, AVG, MIN, MAX, GROUP BY)
by scanning only the requested column Mini-Pages and skipping irrelevant data.
"""

import struct
from typing import Any, Callable, Dict, List, Optional, Tuple

from .pax_page import PAX_MAGIC, PAXPage


def _agg_sum(vals: List[Any]) -> float:
    return sum(float(v) for v in vals if v is not None)


def _agg_avg(vals: List[Any]) -> float:
    valid = [float(v) for v in vals if v is not None]
    return (sum(valid) / len(valid)) if valid else 0.0


def _reduce_group_agg(vals: List[Any], fn: str) -> Any:
    """Applies aggregation function to group values."""
    if fn == "COUNT":
        return len(vals)
    if fn == "SUM":
        return _agg_sum(vals)
    if fn == "AVG":
        return _agg_avg(vals)
    if fn == "MIN":
        return min(vals) if vals else None
    if fn == "MAX":
        return max(vals) if vals else None
    return len(vals)


class PAXScanner:
    """
    OLAP Vectorized Aggregation Scanner operating on PAX Columnar Pages.
    """

    def __init__(
        self,
        pages: List[bytes],
        schema: List[Tuple[str, str]],
    ) -> None:
        self.pages = pages
        self.schema = schema
        self._col_map: Dict[str, int] = {
            name: idx for idx, (name, _) in enumerate(schema)
        }

    def count(
        self,
        predicate: Optional[Callable[[Dict[str, Any]], bool]] = None,
    ) -> int:
        """Calculates total matching rows. Fast O(1) header sum if no predicate."""
        if predicate is None:
            total = 0
            for page in self.pages:
                if len(page) >= 12:
                    magic, row_count, _ = struct.unpack_from("<8sHH", page, 0)
                    if magic == PAX_MAGIC:
                        total += row_count
            return total

        match_count = 0
        for page in self.pages:
            view = memoryview(page)
            rows = PAXPage.read_rows(view, self.schema)
            for row in rows:
                row_dict = {name: row[idx] for idx, (name, _) in enumerate(self.schema)}
                if predicate(row_dict):
                    match_count += 1
        return match_count

    def sum(
        self,
        col_name: str,
        predicate: Optional[Callable[[Dict[str, Any]], bool]] = None,
    ) -> float:
        """Sums values of col_name using projection-pruned column scanning."""
        col_idx = self._col_map.get(col_name)
        if col_idx is None:
            raise KeyError(f"Column {col_name!r} not in schema")

        total = 0.0
        for page in self.pages:
            view = memoryview(page)
            if predicate is None:
                vals = PAXPage.read_column(view, col_idx, self.schema)
                for v in vals:
                    if v is not None:
                        total += float(v)
            else:
                rows = PAXPage.read_rows(view, self.schema)
                for row in rows:
                    row_dict = {
                        name: row[idx] for idx, (name, _) in enumerate(self.schema)
                    }
                    if predicate(row_dict) and row[col_idx] is not None:
                        total += float(row[col_idx])
        return total

    def avg(
        self,
        col_name: str,
        predicate: Optional[Callable[[Dict[str, Any]], bool]] = None,
    ) -> float:
        """Calculates average of col_name."""
        total = self.sum(col_name, predicate)
        cnt = self.count(predicate)
        return (total / cnt) if cnt > 0 else 0.0

    def min(self, col_name: str) -> Optional[Any]:
        """Finds minimum value in column."""
        col_idx = self._col_map.get(col_name)
        if col_idx is None:
            raise KeyError(f"Column {col_name!r} not in schema")

        min_val: Optional[Any] = None
        for page in self.pages:
            view = memoryview(page)
            vals = PAXPage.read_column(view, col_idx, self.schema)
            for v in vals:
                if v is not None and (min_val is None or v < min_val):
                    min_val = v
        return min_val

    def max(self, col_name: str) -> Optional[Any]:
        """Finds maximum value in column."""
        col_idx = self._col_map.get(col_name)
        if col_idx is None:
            raise KeyError(f"Column {col_name!r} not in schema")

        max_val: Optional[Any] = None
        for page in self.pages:
            view = memoryview(page)
            vals = PAXPage.read_column(view, col_idx, self.schema)
            for v in vals:
                if v is not None and (max_val is None or v > max_val):
                    max_val = v
        return max_val

    def group_by(
        self,
        group_col: str,
        agg_col: str,
        agg_fn: str = "COUNT",
    ) -> Dict[Any, Any]:
        """Executes fast GROUP BY aggregation by scanning only the 2 required Mini-Pages."""
        g_idx = self._col_map.get(group_col)
        a_idx = self._col_map.get(agg_col)
        if g_idx is None or a_idx is None:
            raise KeyError(f"Invalid columns: {group_col!r}, {agg_col!r}")

        fn = agg_fn.upper()
        groups: Dict[Any, List[Any]] = {}

        for page in self.pages:
            view = memoryview(page)
            g_vals = PAXPage.read_column(view, g_idx, self.schema)
            a_vals = PAXPage.read_column(view, a_idx, self.schema)

            for g, a in zip(g_vals, a_vals):
                if g not in groups:
                    groups[g] = []
                groups[g].append(a)

        return {g: _reduce_group_agg(vals, fn) for g, vals in groups.items()}
