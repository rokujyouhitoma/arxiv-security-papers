#!/usr/bin/env python3
"""
Solr-style Facet and Aggregation Engine.
Leverages Columnar DocValues to compute fast facet counts and field histograms.
"""

from collections import Counter
from typing import Any, Dict, List, Optional

from ...core.index.doc_values import DocValues


class FacetEngine:
    """
    Computes multidimensional facet counts (year, category, domain, tags) across search hits.
    """

    def __init__(self, doc_values: Optional[DocValues] = None) -> None:
        self.doc_values = doc_values or DocValues()

    def _count_field_val(self, val: Any, counts: Counter[str]) -> None:
        if isinstance(val, (list, set, tuple)):
            for v in val:
                if v:
                    counts[str(v)] += 1
        elif val:
            counts[str(val)] += 1

    def _count_single_field(self, field: str, doc_ids: List[str]) -> Dict[str, int]:
        col = self.doc_values.get_column(field)
        counts: Counter[str] = Counter()
        for did in doc_ids:
            if did in col:
                self._count_field_val(col[did], counts)
        return dict(counts.most_common(20))

    def count_facets(
        self,
        doc_ids: List[str],
        facet_fields: List[str],
    ) -> Dict[str, Dict[str, int]]:
        """Calculates value frequencies for requested facet fields across doc_ids."""
        return {
            field: self._count_single_field(field, doc_ids) for field in facet_fields
        }
