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
    if not vals:
        return 0 if fn == "COUNT" else None
    dispatch = {
        "COUNT": len,
        "SUM": _agg_sum,
        "AVG": _agg_avg,
        "MIN": min,
        "MAX": max,
    }
    agg_func = dispatch.get(fn, len)
    return agg_func(vals)


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

    def _get_col_idx(self, col_name: str) -> int:
        col_idx = self._col_map.get(col_name)
        if col_idx is None:
            raise KeyError(f"Column {col_name!r} not in schema")
        return col_idx

    def _read_rows_as_dicts(self, view: memoryview) -> List[Dict[str, Any]]:
        rows = PAXPage.read_rows(view, self.schema)
        return [
            {name: row[idx] for idx, (name, _) in enumerate(self.schema)}
            for row in rows
        ]

    def _count_with_predicate(self, predicate: Callable[[Dict[str, Any]], bool]) -> int:
        match_count = 0
        for page in self.pages:
            for row_dict in self._read_rows_as_dicts(memoryview(page)):
                if predicate(row_dict):
                    match_count += 1
        return match_count

    def count(
        self,
        predicate: Optional[Callable[[Dict[str, Any]], bool]] = None,
    ) -> int:
        """Calculates total matching rows. Fast O(1) header sum if no predicate."""
        if predicate is not None:
            return self._count_with_predicate(predicate)
        total = 0
        for page in self.pages:
            if len(page) >= 12:
                magic, row_count, _ = struct.unpack_from("<8sHH", page, 0)
                if magic == PAX_MAGIC:
                    total += row_count
        return total

    def _sum_column_all(self, col_idx: int) -> float:
        total = 0.0
        for page in self.pages:
            for v in PAXPage.read_column(memoryview(page), col_idx, self.schema):
                if v is not None:
                    total += float(v)
        return total

    def _sum_column_filtered(
        self, col_idx: int, predicate: Callable[[Dict[str, Any]], bool]
    ) -> float:
        total = 0.0
        for page in self.pages:
            for row_dict in self._read_rows_as_dicts(memoryview(page)):
                if predicate(row_dict):
                    v = row_dict.get(self.schema[col_idx][0])
                    if v is not None:
                        total += float(v)
        return total

    def sum(
        self,
        col_name: str,
        predicate: Optional[Callable[[Dict[str, Any]], bool]] = None,
    ) -> float:
        """Sums values of col_name using projection-pruned column scanning."""
        col_idx = self._get_col_idx(col_name)
        if predicate is None:
            return self._sum_column_all(col_idx)
        return self._sum_column_filtered(col_idx, predicate)

    def avg(
        self,
        col_name: str,
        predicate: Optional[Callable[[Dict[str, Any]], bool]] = None,
    ) -> float:
        """Calculates average of col_name."""
        total = self.sum(col_name, predicate)
        cnt = self.count(predicate)
        return (total / cnt) if cnt > 0 else 0.0

    @staticmethod
    def _is_better_minmax(v: Any, result: Optional[Any], is_max: bool) -> bool:
        if result is None:
            return True
        return v > result if is_max else v < result

    def _scan_column_minmax(self, col_name: str, is_max: bool) -> Optional[Any]:
        col_idx = self._get_col_idx(col_name)
        result: Optional[Any] = None
        for page in self.pages:
            for v in PAXPage.read_column(memoryview(page), col_idx, self.schema):
                if v is not None and self._is_better_minmax(v, result, is_max):
                    result = v
        return result

    def min(self, col_name: str) -> Optional[Any]:
        """Finds minimum value in column."""
        return self._scan_column_minmax(col_name, is_max=False)

    def max(self, col_name: str) -> Optional[Any]:
        """Finds maximum value in column."""
        return self._scan_column_minmax(col_name, is_max=True)

    def group_by(
        self,
        group_col: str,
        agg_col: str,
        agg_fn: str = "COUNT",
    ) -> Dict[Any, Any]:
        """Executes fast GROUP BY aggregation by scanning only the 2 required Mini-Pages."""
        g_idx = self._get_col_idx(group_col)
        a_idx = self._get_col_idx(agg_col)
        fn = agg_fn.upper()
        groups: Dict[Any, List[Any]] = {}
        for page in self.pages:
            view = memoryview(page)
            for g, a in zip(
                PAXPage.read_column(view, g_idx, self.schema),
                PAXPage.read_column(view, a_idx, self.schema),
            ):
                groups.setdefault(g, []).append(a)
        return {g: _reduce_group_agg(vals, fn) for g, vals in groups.items()}
