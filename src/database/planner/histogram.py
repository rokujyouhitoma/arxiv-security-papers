#!/usr/bin/env python3
"""
Equi-Depth Statistical Histogram for Cost-Based Query Optimization.
Partitions skewed and continuous column distributions into equal-depth buckets
for high-accuracy range and equality selectivity estimation.
"""

from typing import Any, List, Optional


class EquiDepthBucket:
    """A single bucket in an equi-depth histogram containing equal row counts."""

    def __init__(
        self,
        min_val: Any,
        max_val: Any,
        count: int,
        distinct_count: int,
    ) -> None:
        self.min_val = min_val
        self.max_val = max_val
        self.count = count
        self.distinct_count = max(1, distinct_count)


def _lt_fraction_at_max(b: EquiDepthBucket) -> float:
    return (b.distinct_count - 1.0) / b.distinct_count if b.distinct_count > 1 else 0.0


def _calc_bucket_lt_fraction(
    b: EquiDepthBucket,
    val: Any,
    inclusive: bool,
) -> float:
    """Calculates linear interpolation fraction inside a bucket for < comparisons."""
    span = b.max_val - b.min_val
    if span == 0:
        return 1.0 if inclusive else 0.0
    if not inclusive and val == b.max_val:
        return _lt_fraction_at_max(b)
    return float((val - b.min_val) / span)


class EquiDepthHistogram:
    """
    Equi-Depth Histogram managing equal-sized data partitions.
    """

    def __init__(self, num_buckets: int = 10) -> None:
        self.num_buckets = num_buckets
        self.buckets: List[EquiDepthBucket] = []
        self.total_count: int = 0

    def _build_buckets(self, sorted_vals: List[Any], k: int) -> None:
        n = len(sorted_vals)
        bucket_size = n // k
        remainder = n % k
        start = 0
        for i in range(k):
            size = bucket_size + (1 if i < remainder else 0)
            if size == 0:
                continue
            slice_vals = sorted_vals[start : start + size]
            start += size
            self.buckets.append(
                EquiDepthBucket(
                    min_val=slice_vals[0],
                    max_val=slice_vals[-1],
                    count=len(slice_vals),
                    distinct_count=len(set(slice_vals)),
                )
            )

    @staticmethod
    def _try_sort_values(clean: List[Any]) -> Optional[List[Any]]:
        try:
            return sorted(clean)
        except TypeError:
            return None

    def _populate_sorted_buckets(self, sorted_vals: List[Any]) -> None:
        k = min(self.num_buckets, len(sorted_vals))
        if k > 0:
            self._build_buckets(sorted_vals, k)

    def build(self, values: List[Any]) -> None:
        """Constructs equi-depth buckets from a collection of values."""
        clean = [v for v in values if v is not None]
        self.total_count = len(clean)
        self.buckets.clear()
        if clean:
            sorted_vals = self._try_sort_values(clean)
            if sorted_vals:
                self._populate_sorted_buckets(sorted_vals)

    def _select_gt_estimate(self, op: str, val1: Any) -> float:
        return max(0.0, min(1.0, 1.0 - self._estimate_lt(val1, inclusive=(op == ">"))))

    def _select_between_estimate(self, val1: Any, val2: Any) -> float:
        return max(
            0.001,
            min(
                1.0,
                self._estimate_lt(val2, inclusive=True)
                - self._estimate_lt(val1, inclusive=False),
            ),
        )

    def _select_range_estimate(
        self, op: str, val1: Any, val2: Optional[Any]
    ) -> Optional[float]:
        if op in (">", ">="):
            return self._select_gt_estimate(op, val1)
        if op.upper() == "BETWEEN" and val2 is not None:
            return self._select_between_estimate(val1, val2)
        return None

    def _select_op_estimate(
        self, op: str, val1: Any, val2: Optional[Any]
    ) -> Optional[float]:
        """Dispatches to appropriate estimate method based on op; returns None if unknown."""
        if op in ("=", "=="):
            return self._estimate_eq(val1)
        if op in ("<", "<="):
            return self._estimate_lt(val1, inclusive=(op == "<="))
        return self._select_range_estimate(op, val1, val2)

    def estimate_selectivity(
        self,
        op: str,
        val1: Any,
        val2: Optional[Any] = None,
    ) -> float:
        """
        Estimates predicate selectivity (0.0 to 1.0) using bucket interpolation.
        """
        if not self.buckets or self.total_count == 0:
            return 0.50
        result = self._select_op_estimate(op, val1, val2)
        return result if result is not None else 0.33

    def _estimate_eq(self, val: Any) -> float:
        """Estimates equality selectivity across all matching buckets."""
        total_sel = 0.0
        for b in self.buckets:
            try:
                if b.min_val <= val <= b.max_val:
                    bucket_sel = b.count / self.total_count
                    total_sel += bucket_sel / b.distinct_count
            except TypeError:
                continue
        return max(0.001, min(1.0, total_sel)) if total_sel > 0 else 0.001

    @staticmethod
    def _is_above_bucket_max(b: EquiDepthBucket, val: Any, inclusive: bool) -> bool:
        if val > b.max_val:
            return True
        return inclusive and val == b.max_val

    def _process_lt_bucket(
        self, b: EquiDepthBucket, val: Any, inclusive: bool
    ) -> "tuple[float, bool]":
        """Returns (matched_count_contribution, stop) for this bucket."""
        try:
            if val < b.min_val:
                return 0.0, True
            if self._is_above_bucket_max(b, val, inclusive):
                return float(b.count), False
            fraction = _calc_bucket_lt_fraction(b, val, inclusive)
            return b.count * max(0.0, min(1.0, fraction)), True
        except TypeError:
            return 0.0, False

    def _estimate_lt(self, val: Any, inclusive: bool = False) -> float:
        """Estimates less-than selectivity."""
        matched_count = 0.0
        for b in self.buckets:
            contrib, stop = self._process_lt_bucket(b, val, inclusive)
            matched_count += contrib
            if stop:
                break
        return max(0.001, min(1.0, matched_count / self.total_count))
