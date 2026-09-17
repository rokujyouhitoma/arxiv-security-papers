#!/usr/bin/env python3
"""
Multi-Field Schema & Postings Lists for Enterprise Search Engine.
Provides field-level indexing, term positions, offsets, and author metadata tracking.
"""

from collections import defaultdict
from enum import Enum
from typing import Any, Dict, List, Set, Tuple, cast


class FieldType(Enum):
    TEXT = "text"
    STRING = "string"
    NUMERIC = "numeric"


class MultiFieldPostingsIndex:
    """
    Multi-Field Inverted Index maintaining term frequencies and postings.
    When track_positions=True (default), maintains (doc_id, [positions]).
    When track_positions=False (high-performance / low-memory mode), maintains doc_id lists.
    """

    def __init__(self, track_positions: bool = True) -> None:
        self.track_positions = track_positions
        # If track_positions=True:  field_name -> term -> list of (doc_id, positions)
        # If track_positions=False: field_name -> term -> list of doc_id
        self.fields: Dict[str, Dict[str, Any]] = {
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
        self.total_field_tokens: Dict[str, int] = defaultdict(int)
        self.avg_field_lengths: Dict[str, float] = defaultdict(float)

    def _add_tokens_with_positions(
        self, doc_id: str, field_name: str, tokens: List[str]
    ) -> None:
        self.doc_lengths[doc_id][field_name] = len(tokens)
        positions_map: Dict[str, List[int]] = defaultdict(list)
        for pos, token in enumerate(tokens):
            norm = token.lower().strip()
            if norm:
                positions_map[norm].append(pos)
        for term, positions in positions_map.items():
            self.fields[field_name][term].append((doc_id, positions))

    def _add_tokens_compact(
        self, doc_id: str, field_name: str, tokens: List[str]
    ) -> None:
        seen: Set[str] = set()
        for token in tokens:
            norm = token.lower().strip()
            if norm and norm not in seen:
                seen.add(norm)
                self.fields[field_name][norm].append(doc_id)

    def add_field_tokens(self, doc_id: str, field_name: str, tokens: List[str]) -> None:
        """Indexes tokens for a specific document field."""
        if field_name not in self.fields:
            self.fields[field_name] = defaultdict(list)
        self.total_field_tokens[field_name] += len(tokens)
        if self.track_positions:
            self._add_tokens_with_positions(doc_id, field_name, tokens)
        else:
            self._add_tokens_compact(doc_id, field_name, tokens)

    def compute_field_statistics(self, total_docs: int) -> None:
        """Computes average field lengths for BM25 multi-field scoring."""
        if total_docs == 0:
            return
        for field_name in self.fields:
            if field_name in self.total_field_tokens:
                self.avg_field_lengths[field_name] = (
                    self.total_field_tokens[field_name] / total_docs
                )
            else:
                total_tokens = sum(
                    self.doc_lengths[d].get(field_name, 0) for d in self.doc_lengths
                )
                self.avg_field_lengths[field_name] = total_tokens / total_docs

    def get_postings(self, field_name: str, term: str) -> List[Tuple[str, Any]]:
        """Returns postings list for a given field and term."""
        norm_term = term.lower().strip()
        field_dict = self.fields.get(field_name, {})
        postings = field_dict.get(norm_term, [])
        if not self.track_positions:
            return [(doc_id, ()) for doc_id in postings]
        return cast(List[Tuple[str, Any]], postings)

    def _extract_doc_ids(self, postings: Any) -> Set[str]:
        if self.track_positions:
            return {doc_id for doc_id, _ in postings}
        return set(postings)

    def search_prefix(self, field_name: str, prefix: str) -> Set[str]:
        """Returns matching doc_ids for a term prefix (e.g. 'Nakat*')."""
        norm_p = prefix.lower().strip()
        doc_ids: Set[str] = set()
        field_dict = self.fields.get(field_name, {})
        for term, postings in field_dict.items():
            if term.startswith(norm_p):
                doc_ids.update(self._extract_doc_ids(postings))
        return doc_ids

    def search_fuzzy(
        self, field_name: str, target: str, max_distance: int = 1
    ) -> Set[str]:
        """Returns matching doc_ids within Levenshtein edit distance."""
        norm_t = target.lower().strip()
        doc_ids: Set[str] = set()
        field_dict = self.fields.get(field_name, {})
        for term, postings in field_dict.items():
            if abs(len(term) - len(norm_t)) > max_distance:
                continue
            if self._levenshtein_distance(term, norm_t) <= max_distance:
                doc_ids.update(self._extract_doc_ids(postings))
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
