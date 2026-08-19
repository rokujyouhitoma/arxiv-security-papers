#!/usr/bin/env python3
"""
Lucene-style Postings Lists & Multi-Field Inverted Index.
"""

from collections import defaultdict
from typing import Dict, List, Optional, Set, Tuple


class PostingsList:
    """Represents an inverted list of (doc_id, term_frequency, positions) for a single term."""

    def __init__(self) -> None:
        self.doc_entries: Dict[str, List[int]] = defaultdict(list)

    def add_occurrence(self, doc_id: str, position: int) -> None:
        self.doc_entries[doc_id].append(position)

    def get_docs(self) -> List[Tuple[str, int]]:
        """Returns list of (doc_id, term_freq)."""
        return [
            (doc_id, len(positions)) for doc_id, positions in self.doc_entries.items()
        ]

    def doc_frequency(self) -> int:
        return len(self.doc_entries)


class MultiFieldPostingsIndex:
    """
    Manages field-specific inverted indexes with prefix and fuzzy matching.
    """

    def __init__(self) -> None:
        self.field_indexes: Dict[str, Dict[str, PostingsList]] = defaultdict(
            lambda: defaultdict(PostingsList)
        )

    def add_term(self, field: str, term: str, doc_id: str, position: int = 0) -> None:
        if not field or not term or not doc_id:
            return
        self.field_indexes[field][term.lower()].add_occurrence(doc_id, position)

    def get_postings(self, field: str, term: str) -> List[Tuple[str, int]]:
        term_clean = term.lower()
        if field in self.field_indexes and term_clean in self.field_indexes[field]:
            return self.field_indexes[field][term_clean].get_docs()
        return []

    def search_prefix(self, field: str, prefix: str) -> Set[str]:
        matched_docs: Set[str] = set()
        pfx_lower = prefix.lower()
        if field in self.field_indexes:
            for term, plist in self.field_indexes[field].items():
                if term.startswith(pfx_lower):
                    for doc_id, _ in plist.get_docs():
                        matched_docs.add(doc_id)
        return matched_docs

    def search_fuzzy(self, field: str, term: str, max_distance: int = 1) -> Set[str]:
        matched_docs: Set[str] = set()
        term_lower = term.lower()
        if field not in self.field_indexes:
            return matched_docs

        for t, plist in self.field_indexes[field].items():
            if abs(len(t) - len(term_lower)) > max_distance:
                continue
            if (
                self._levenshtein(t, term_lower, max_distance=max_distance)
                <= max_distance
            ):
                for doc_id, _ in plist.get_docs():
                    matched_docs.add(doc_id)
        return matched_docs

    @staticmethod
    def _compute_dp_row(
        c1: str, s2: str, v0: List[int], v1: List[int], row_idx: int
    ) -> int:
        v1[0] = row_idx
        min_val = row_idx
        for j, c2 in enumerate(s2):
            cost = 0 if c1 == c2 else 1
            val = min(v1[j] + 1, v0[j + 1] + 1, v0[j] + cost)
            v1[j + 1] = val
            if val < min_val:
                min_val = val
        return min_val

    @classmethod
    def _levenshtein(cls, s1: str, s2: str, max_distance: Optional[int] = None) -> int:
        if s1 == s2:
            return 0
        if not s1 or not s2:
            return max(len(s1), len(s2))
        if len(s1) < len(s2):
            s1, s2 = s2, s1

        len_s1, len_s2 = len(s1), len(s2)
        if max_distance is not None and (len_s1 - len_s2) > max_distance:
            return max_distance + 1

        v0 = list(range(len_s2 + 1))
        v1 = [0] * (len_s2 + 1)

        for i, c1 in enumerate(s1):
            min_val = cls._compute_dp_row(c1, s2, v0, v1, i + 1)
            if max_distance is not None and min_val > max_distance:
                return max_distance + 1
            v0, v1 = v1, v0

        return v0[len_s2]
