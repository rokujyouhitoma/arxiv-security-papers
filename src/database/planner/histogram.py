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


def _calc_bucket_lt_fraction(
    b: EquiDepthBucket,
    val: Any,
    inclusive: bool,
) -> float:
    """Calculates linear interpolation fraction inside a bucket for < comparisons."""
    span = b.max_val - b.min_val
    if span == 0:
        return 1.0 if inclusive else 0.0
    if not inclusive and val == b.max_val and b.distinct_count > 1:
        return (b.distinct_count - 1.0) / b.distinct_count
    return float((val - b.min_val) / span)


class EquiDepthHistogram:
    """
    Equi-Depth Histogram managing equal-sized data partitions.
    """

    def __init__(self, num_buckets: int = 10) -> None:
        self.num_buckets = num_buckets
        self.buckets: List[EquiDepthBucket] = []
        self.total_count: int = 0

    def build(self, values: List[Any]) -> None:
        """Constructs equi-depth buckets from a collection of values."""
        clean = [v for v in values if v is not None]
        self.total_count = len(clean)
        self.buckets.clear()

        if not clean:
            return

        try:
            sorted_vals = sorted(clean)
        except TypeError:
            return

        n = len(sorted_vals)
        k = min(self.num_buckets, n)
        if k == 0:
            return

        bucket_size = n // k
        remainder = n % k

        start = 0
        for i in range(k):
            size = bucket_size + (1 if i < remainder else 0)
            if size == 0:
                continue
            slice_vals = sorted_vals[start : start + size]
            start += size

            bucket = EquiDepthBucket(
                min_val=slice_vals[0],
                max_val=slice_vals[-1],
                count=len(slice_vals),
                distinct_count=len(set(slice_vals)),
            )
            self.buckets.append(bucket)

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

        if op in ("=", "=="):
            return self._estimate_eq(val1)
        if op in ("<", "<="):
            return self._estimate_lt(val1, inclusive=(op == "<="))
        if op in (">", ">="):
            lt_sel = self._estimate_lt(val1, inclusive=(op == ">"))
            return max(0.0, min(1.0, 1.0 - lt_sel))
        if op.upper() == "BETWEEN" and val2 is not None:
            sel_high = self._estimate_lt(val2, inclusive=True)
            sel_low = self._estimate_lt(val1, inclusive=False)
            return max(0.001, min(1.0, sel_high - sel_low))

        return 0.33

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

    def _estimate_lt(self, val: Any, inclusive: bool = False) -> float:
        """Estimates less-than selectivity."""
        matched_count = 0.0

        for b in self.buckets:
            try:
                if val < b.min_val:
                    break
                if val > b.max_val or (inclusive and val == b.max_val):
                    matched_count += b.count
                else:
                    fraction = _calc_bucket_lt_fraction(b, val, inclusive)
                    matched_count += b.count * max(0.0, min(1.0, fraction))
                    break
            except TypeError:
                continue

        return max(0.001, min(1.0, matched_count / self.total_count))
