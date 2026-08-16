#!/usr/bin/env python3
"""
Multi-Field Schema & Postings Lists for Enterprise Search Engine.
Provides field-level indexing, term positions, offsets, and author metadata tracking.
"""

from collections import defaultdict
from enum import Enum
from typing import Dict, List, Set, Tuple


class FieldType(Enum):
    TEXT = "text"
    STRING = "string"
    NUMERIC = "numeric"


class MultiFieldPostingsIndex:
    """
    Multi-Field Inverted Index maintaining term frequencies and positions.
    Structure: field_name -> term -> list of [doc_id, [positions]]
    """

    def __init__(self) -> None:
        self.fields: Dict[str, Dict[str, List[Tuple[str, List[int]]]]] = {
            "title": defaultdict(list),
            "author": defaultdict(list),
            "abstract": defaultdict(list),
            "content": defaultdict(list),
            "keywords": defaultdict(list),
            "tags": defaultdict(list),
        }
        self.doc_lengths: Dict[str, Dict[str, int]] = defaultdict(
            lambda: defaultdict(int)
        )
        self.avg_field_lengths: Dict[str, float] = defaultdict(float)

    def add_field_tokens(
        self, doc_id: str, field_name: str, tokens: List[str]
    ) -> None:
        """Indexes token positions for a specific document field."""
        if field_name not in self.fields:
            self.fields[field_name] = defaultdict(list)

        positions_map: Dict[str, List[int]] = defaultdict(list)
        for pos, token in enumerate(tokens):
            norm_token = token.lower().strip()
            if norm_token:
                positions_map[norm_token].append(pos)

        self.doc_lengths[doc_id][field_name] = len(tokens)

        for term, positions in positions_map.items():
            self.fields[field_name][term].append((doc_id, positions))

    def compute_field_statistics(self, total_docs: int) -> None:
        """Computes average field lengths for BM25 multi-field scoring."""
        if total_docs == 0:
            return
        for field_name in self.fields:
            total_tokens = sum(
                self.doc_lengths[d].get(field_name, 0)
                for d in self.doc_lengths
            )
            self.avg_field_lengths[field_name] = total_tokens / total_docs

    def get_postings(
        self, field_name: str, term: str
    ) -> List[Tuple[str, List[int]]]:
        """Returns postings list for a given field and term."""
        norm_term = term.lower().strip()
        field_dict = self.fields.get(field_name, {})
        return field_dict.get(norm_term, [])

    def search_prefix(
        self, field_name: str, prefix: str
    ) -> Set[str]:
        """Returns matching doc_ids for a term prefix (e.g. 'Nakat*')."""
        norm_p = prefix.lower().strip()
        doc_ids: Set[str] = set()
        field_dict = self.fields.get(field_name, {})
        for term, postings in field_dict.items():
            if term.startswith(norm_p):
                for doc_id, _ in postings:
                    doc_ids.add(doc_id)
        return doc_ids

    def search_fuzzy(
        self, field_name: str, target: str, max_distance: int = 1
    ) -> Set[str]:
        """Returns matching doc_ids within Levenshtein edit distance."""
        norm_t = target.lower().strip()
        doc_ids: Set[str] = set()
        field_dict = self.fields.get(field_name, {})

        for term, postings in field_dict.items():
            if abs(len(term) - len(norm_t)) <= max_distance:
                if self._levenshtein_distance(term, norm_t) <= max_distance:
                    for doc_id, _ in postings:
                        doc_ids.add(doc_id)
        return doc_ids

    @staticmethod
    def _levenshtein_distance(s1: str, s2: str) -> int:
        if len(s1) < len(s2):
            return MultiFieldPostingsIndex._levenshtein_distance(s2, s1)
        if len(s2) == 0:
            return len(s1)
        prev = list(range(len(s2) + 1))
        for i, c1 in enumerate(s1):
            curr = [i + 1]
            for j, c2 in enumerate(s2):
                insertions = prev[j + 1] + 1
                deletions = curr[j] + 1
                substitutions = prev[j] + (c1 != c2)
                curr.append(min(insertions, deletions, substitutions))
            prev = curr
        return prev[-1]
