#!/usr/bin/env python3
"""
Faceted and Temporal Index for Fast Bitmap/Set Boolean Filtering.
"""

from collections import defaultdict
from typing import Dict, List, Optional, Set


class FacetedIndex:
    """
    Faceted and Temporal Index for Fast Bitmap/Set Boolean Filtering.
    """

    def __init__(self) -> None:
        self.years: Dict[str, Set[str]] = defaultdict(set)
        self.categories: Dict[str, Set[str]] = defaultdict(set)
        self.tags: Dict[str, Set[str]] = defaultdict(set)
        self.domains: Dict[str, Set[str]] = defaultdict(set)

    def _add_single_tag(self, tag: str, doc_id: str) -> None:
        t_clean = tag.strip().lower()
        if t_clean.startswith("cs."):
            self.categories[t_clean].add(doc_id)
        else:
            self.tags[t_clean].add(doc_id)

    def add_document(
        self,
        doc_id: str,
        published_date: str,
        tags: List[str],
        annotated_keywords: List[str],
    ) -> None:
        if published_date and len(published_date) >= 4:
            self.years[published_date[:4]].add(doc_id)

        for t in tags:
            self._add_single_tag(t, doc_id)

        for kw in annotated_keywords:
            self.domains[kw.strip().lower()].add(doc_id)

    def _intersect_candidates(
        self, candidates: Optional[Set[str]], target_docs: Set[str]
    ) -> Set[str]:
        if candidates is None:
            return target_docs
        return candidates & target_docs

    def _filter_facet(
        self,
        val: Optional[str],
        mapping: Dict[str, Set[str]],
        candidates: Optional[Set[str]],
    ) -> Optional[Set[str]]:
        if not val:
            return candidates
        clean_val = val.strip().lower()
        target_docs = mapping.get(clean_val, set())
        return self._intersect_candidates(candidates, target_docs)

    def filter(
        self,
        year: Optional[str] = None,
        category: Optional[str] = None,
        tag: Optional[str] = None,
        domain: Optional[str] = None,
    ) -> Optional[Set[str]]:
        candidates: Optional[Set[str]] = None
        if year and year in self.years:
            candidates = set(self.years[year])

        candidates = self._filter_facet(category, self.categories, candidates)
        candidates = self._filter_facet(tag, self.tags, candidates)
        candidates = self._filter_facet(domain, self.domains, candidates)

        return candidates
