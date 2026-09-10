#!/usr/bin/env python3
"""
Catalog Statistics Engine for Cost-Based Query Optimization.
Tracks row count, column distinct values (NDV via HyperLogLog),
min/max ranges, and predicate selectivity via Equi-Depth Histograms.
"""

from typing import Any, Dict, List, Optional, Set

from .histogram import EquiDepthHistogram
from .hll import HyperLogLog


def _estimate_eq_sel(distinct_count: int) -> float:
    return max(0.001, min(1.0, 1.0 / distinct_count)) if distinct_count > 0 else 0.1


def _estimate_in_sel(value: Any, distinct_count: int) -> float:
    if isinstance(value, (list, tuple, set)) and distinct_count > 0:
        return min(1.0, len(value) / max(1, distinct_count))
    return 0.25


def _estimate_op_selectivity(
    op: str,
    value: Any,
    distinct_count: int,
) -> float:
    """Estimates fallback selectivity when histogram is absent."""
    if op in ("=", "=="):
        return _estimate_eq_sel(distinct_count)
    if op in (">", ">=", "<", "<="):
        return 0.33
    if op.upper() in ("LIKE", "CONTAINS"):
        return 0.20
    if op.upper() == "IN":
        return _estimate_in_sel(value, distinct_count)
    return 0.50


class ColumnStats:
    """Statistics for a single table column with Equi-Depth Histogram and HLL."""

    def __init__(self, column_name: str) -> None:
        self.column_name = column_name
        self.total_count: int = 0
        self.distinct_count: int = 0
        self.null_count: int = 0
        self.min_value: Optional[Any] = None
        self.max_value: Optional[Any] = None
        self.histogram: Optional[EquiDepthHistogram] = None
        self.hll: Optional[HyperLogLog] = None

    def _update_hll_distinct(self, non_nulls: List[Any]) -> None:
        self.hll = HyperLogLog(p=8)
        for v in non_nulls:
            self.hll.add(v)
        self.distinct_count = self.hll.estimate_cardinality()
        try:
            distinct: Set[Any] = set(non_nulls)
            if len(distinct) < 16:
                self.distinct_count = len(distinct)
        except TypeError:
            pass

    def _update_min_max(self, non_nulls: List[Any]) -> None:
        try:
            self.min_value = min(non_nulls)
            self.max_value = max(non_nulls)
        except TypeError:
            self.min_value = None
            self.max_value = None

    def update(self, values: List[Any]) -> None:
        """Updates statistics from a list of values."""
        self.total_count = len(values)
        non_nulls = [v for v in values if v is not None]
        self.null_count = self.total_count - len(non_nulls)
        self._update_hll_distinct(non_nulls)
        if non_nulls:
            self._update_min_max(non_nulls)
            self.histogram = EquiDepthHistogram(num_buckets=10)
            self.histogram.build(non_nulls)

    def estimate_selectivity(self, op: str, value: Any) -> float:
        """Estimates selectivity (fraction of rows matching, 0.0 to 1.0)."""
        if self.total_count == 0:
            return 1.0

        if self.histogram and len(self.histogram.buckets) > 0:
            if op in ("=", "==", "<", "<=", ">", ">="):
                return self.histogram.estimate_selectivity(op, value)

        return _estimate_op_selectivity(op, value, self.distinct_count)


def _is_sampleable_col(val: Any) -> bool:
    """Filters out extremely long texts or heavy blobs from statistical sampling."""
    if isinstance(val, (str, bytes)) and len(val) > 2048:
        return False
    return True


def _extract_sample_keys(sample: List[Dict[str, Any]]) -> Set[str]:
    keys: Set[str] = set()
    for row in sample:
        for k in row.keys():
            if _is_sampleable_col(row.get(k)):
                keys.add(k)
    return keys


def _compute_columns_stats(
    sample: List[Dict[str, Any]], keys: Set[str]
) -> Dict[str, ColumnStats]:
    cols: Dict[str, ColumnStats] = {}
    for k in keys:
        cs = ColumnStats(k)
        cs.update([row.get(k) for row in sample])
        cols[k] = cs
    return cols


class TableStats:
    """Statistics container for an entire table."""

    def __init__(self, table_name: str, total_rows: int = 0) -> None:
        self.table_name = table_name
        self.total_rows = total_rows
        self.columns: Dict[str, ColumnStats] = {}

    def analyze_from_metadata(self, metadata: List[Dict[str, Any]]) -> None:
        """Collects statistics across table metadata using sampling for large tables."""
        self.total_rows = len(metadata)
        if not metadata:
            return
        sample = metadata[:200] if len(metadata) > 200 else metadata
        keys = _extract_sample_keys(sample)
        self.columns = _compute_columns_stats(sample, keys)
