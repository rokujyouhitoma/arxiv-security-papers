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

    def add_document(
        self,
        doc_id: str,
        published_date: str,
        tags: List[str],
        annotated_keywords: List[str],
    ) -> None:
        if published_date and len(published_date) >= 4:
            year = published_date[:4]
            self.years[year].add(doc_id)

        for t in tags:
            t_clean = t.strip().lower()
            if t_clean.startswith("cs."):
                self.categories[t_clean].add(doc_id)
            else:
                self.tags[t_clean].add(doc_id)

        for kw in annotated_keywords:
            self.domains[kw.strip().lower()].add(doc_id)

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

        if category:
            cat_clean = category.strip().lower()
            cat_docs = self.categories.get(cat_clean, set())
            candidates = cat_docs if candidates is None else (candidates & cat_docs)

        if tag:
            tag_clean = tag.strip().lower()
            tag_docs = self.tags.get(tag_clean, set())
            candidates = tag_docs if candidates is None else (candidates & tag_docs)

        if domain:
            dom_clean = domain.strip().lower()
            dom_docs = self.domains.get(dom_clean, set())
            candidates = dom_docs if candidates is None else (candidates & dom_docs)

        return candidates
