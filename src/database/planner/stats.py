#!/usr/bin/env python3
"""
Catalog Statistics Engine for Cost-Based Query Optimization.
Tracks row count, column distinct values (NDV), min/max ranges, and predicate selectivity.
"""

from typing import Any, Dict, List, Optional, Set


class ColumnStats:
    """Statistics for a single table column."""

    def __init__(self, column_name: str) -> None:
        self.column_name = column_name
        self.total_count: int = 0
        self.distinct_count: int = 0
        self.null_count: int = 0
        self.min_value: Optional[Any] = None
        self.max_value: Optional[Any] = None

    def update(self, values: List[Any]) -> None:
        """Updates statistics from a list of values."""
        self.total_count = len(values)
        non_nulls = [v for v in values if v is not None]
        self.null_count = self.total_count - len(non_nulls)
        distinct: Set[Any] = set(non_nulls)
        self.distinct_count = len(distinct)

        if non_nulls:
            try:
                self.min_value = min(non_nulls)
                self.max_value = max(non_nulls)
            except TypeError:
                self.min_value = None
                self.max_value = None

    def estimate_selectivity(self, op: str, value: Any) -> float:
        """Estimates selectivity (fraction of rows matching, 0.0 to 1.0)."""
        if self.total_count == 0:
            return 1.0

        if op in ("=", "=="):
            if self.distinct_count > 0:
                return max(0.001, min(1.0, 1.0 / self.distinct_count))
            return 0.1

        if op in (">", ">=", "<", "<="):
            return 0.33

        if op.upper() in ("LIKE", "CONTAINS"):
            return 0.20

        if op.upper() == "IN":
            if isinstance(value, (list, tuple, set)) and self.distinct_count > 0:
                return min(1.0, len(value) / max(1, self.distinct_count))
            return 0.25

        return 0.50


class TableStats:
    """Table-level catalog statistics."""

    def __init__(self, table_name: str, total_rows: int = 0) -> None:
        self.table_name = table_name
        self.total_rows = total_rows
        self.columns: Dict[str, ColumnStats] = {}

    def analyze_from_metadata(self, metadata: List[Dict[str, Any]]) -> None:
        """Collects statistics across all rows in table metadata."""
        self.total_rows = len(metadata)
        if not metadata:
            return

        all_keys: Set[str] = set()
        for row in metadata:
            all_keys.update(row.keys())

        for k in all_keys:
            col_stats = ColumnStats(k)
            values = [row.get(k) for row in metadata]
            col_stats.update(values)
            self.columns[k] = col_stats
