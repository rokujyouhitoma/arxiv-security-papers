#!/usr/bin/env python3
"""
Solr-style Facet and Aggregation Engine.
Leverages Columnar DocValues to compute fast facet counts and field histograms.
"""

from collections import Counter
from typing import Dict, List, Optional

from ...core.index.doc_values import DocValues


class FacetEngine:
    """
    Computes multidimensional facet counts (year, category, domain, tags) across search hits.
    """

    def __init__(self, doc_values: Optional[DocValues] = None) -> None:
        self.doc_values = doc_values or DocValues()

    def count_facets(
        self,
        doc_ids: List[str],
        facet_fields: List[str],
    ) -> Dict[str, Dict[str, int]]:
        """Calculates value frequencies for requested facet fields across doc_ids."""
        facet_results: Dict[str, Dict[str, int]] = {}

        for field in facet_fields:
            col = self.doc_values.get_column(field)
            counts: Counter[str] = Counter()
            for did in doc_ids:
                if did in col:
                    val = col[did]
                    if isinstance(val, (list, set, tuple)):
                        for v in val:
                            if v:
                                counts[str(v)] += 1
                    elif val:
                        counts[str(val)] += 1
            facet_results[field] = dict(counts.most_common(20))

        return facet_results
