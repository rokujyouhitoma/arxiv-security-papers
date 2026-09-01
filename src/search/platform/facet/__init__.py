#!/usr/bin/env python3
"""
Facet and Aggregation Engine (Solr Paradigm).
Computes field facets and range facets using in-memory DocValues.
"""

from collections import Counter
from typing import Any, Dict, List

from ...engine.index import Segment


class FieldFacet:
    """Term frequency count facet for a discrete field."""

    def __init__(self, field: str, limit: int = 10, min_count: int = 1) -> None:
        self.field = field
        self.limit = limit
        self.min_count = min_count

    def _count_doc_value(self, val: Any, counter: Counter[str]) -> None:
        if val is None:
            return
        if isinstance(val, list):
            for v in val:
                counter[str(v)] += 1
        else:
            counter[str(val)] += 1

    def _filter_and_sort(self, counter: Counter[str]) -> Dict[str, int]:
        filtered = {k: v for k, v in counter.items() if v >= self.min_count}
        sorted_items = sorted(filtered.items(), key=lambda x: (-x[1], x[0]))[
            : self.limit
        ]
        return dict(sorted_items)

    def compute(self, segment: Segment, doc_ids: List[int]) -> Dict[str, int]:
        dv = segment.doc_values.get(self.field)
        if not dv:
            return {}

        counter: Counter[str] = Counter()
        for doc_id in doc_ids:
            if not segment.is_deleted(doc_id):
                self._count_doc_value(dv.get(doc_id), counter)

        return self._filter_and_sort(counter)


class RangeFacet:
    """Range aggregation bucket facet (e.g. for years, dates, or scores)."""

    def __init__(self, field: str, start: float, end: float, gap: float) -> None:
        self.field = field
        self.start = start
        self.end = end
        self.gap = gap

    def compute(self, segment: Segment, doc_ids: List[int]) -> Dict[str, int]:
        dv = segment.doc_values.get(self.field)
        if not dv or self.gap <= 0:
            return {}

        buckets = self._init_buckets()
        bucket_keys = list(buckets.keys())

        for doc_id in doc_ids:
            if not segment.is_deleted(doc_id):
                val = dv.get(doc_id)
                self._increment_bucket(val, buckets, bucket_keys)

        return buckets

    def _init_buckets(self) -> Dict[str, int]:
        def format_bound(val: float) -> str:
            return str(int(val)) if val.is_integer() else str(val)

        buckets: Dict[str, int] = {}
        cur = self.start
        while cur < self.end:
            next_cur = cur + self.gap
            b_key = f"[{format_bound(cur)} TO {format_bound(next_cur)}]"
            buckets[b_key] = 0
            cur = next_cur
        return buckets

    def _increment_bucket(
        self, val: Any, buckets: Dict[str, int], bucket_keys: List[str]
    ) -> None:
        try:
            num_val = float(val)
            for idx, b_key in enumerate(bucket_keys):
                parts = b_key.strip("[]").split(" TO ")
                b_start, b_end = float(parts[0]), float(parts[1])
                is_last = idx == len(bucket_keys) - 1
                if (
                    (b_start <= num_val <= b_end)
                    if is_last
                    else (b_start <= num_val < b_end)
                ):
                    buckets[b_key] += 1
                    break
        except (ValueError, TypeError):
            pass


class FacetEngine:
    """Orchestrates multi-dimensional faceted search aggregations."""

    def __init__(self) -> None:
        self.field_facets: Dict[str, FieldFacet] = {}
        self.range_facets: Dict[str, RangeFacet] = {}

    def add_field_facet(
        self, field: str, limit: int = 10, min_count: int = 1
    ) -> "FacetEngine":
        self.field_facets[field] = FieldFacet(field, limit, min_count)
        return self

    def add_range_facet(
        self, field: str, start: float, end: float, gap: float
    ) -> "FacetEngine":
        self.range_facets[field] = RangeFacet(field, start, end, gap)
        return self

    def compute_facets(
        self, segment: Segment, doc_ids: List[int]
    ) -> Dict[str, Dict[str, int]]:
        results: Dict[str, Dict[str, int]] = {}
        for fname, ff in self.field_facets.items():
            results[fname] = ff.compute(segment, doc_ids)
        for rname, rf in self.range_facets.items():
            results[rname] = rf.compute(segment, doc_ids)
        return results
