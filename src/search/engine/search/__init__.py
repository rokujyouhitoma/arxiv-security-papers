#!/usr/bin/env python3
"""
Search, Scoring, Queries (Boolean, Phrase, Wildcard, Fuzzy, Boost), SpellChecker, and Sorter (Lucene Paradigm).
"""

import fnmatch
import math
from abc import ABC, abstractmethod
from enum import Enum
from typing import Any, Dict, List, Optional, Set, Tuple

from ..index import PostingEntry, Segment


class Similarity(ABC):
    """Abstract scoring similarity model."""

    @abstractmethod
    def score(
        self, tf: int, doc_len: int, avg_doc_len: float, doc_freq: int, total_docs: int
    ) -> float:
        raise NotImplementedError


class BM25Similarity(Similarity):
    """Okapi BM25 statistical relevance scoring model (k1=1.2, b=0.75)."""

    def __init__(self, k1: float = 1.2, b: float = 0.75) -> None:
        self.k1 = k1
        self.b = b

    def idf(self, doc_freq: int, total_docs: int) -> float:
        # Standard Lucene BM25 IDF formulation with smoothing
        return math.log(1.0 + (total_docs - doc_freq + 0.5) / (doc_freq + 0.5))

    def score(
        self, tf: int, doc_len: int, avg_doc_len: float, doc_freq: int, total_docs: int
    ) -> float:
        if tf <= 0 or total_docs <= 0:
            return 0.0
        idf_val = self.idf(doc_freq, total_docs)
        len_norm = 1.0 - self.b + self.b * (doc_len / max(avg_doc_len, 1.0))
        tf_norm = (tf * (self.k1 + 1.0)) / (tf + self.k1 * len_norm)
        return idf_val * tf_norm


class Occur(Enum):
    """Boolean clause occurrence constraint."""

    MUST = "+"
    SHOULD = " "
    MUST_NOT = "-"


class Query(ABC):
    """Abstract base class for all query types."""

    def __init__(self, boost: float = 1.0) -> None:
        self.boost = boost

    @abstractmethod
    def match(self, segment: Segment, similarity: Similarity) -> Dict[int, float]:
        """Returns a mapping from doc_id to relevance score for the given segment."""
        raise NotImplementedError


class BoostQuery(Query):
    """Wraps another query with a specific boost multiplier."""

    def __init__(self, subquery: Query, boost: float = 1.0) -> None:
        super().__init__(boost=boost)
        self.subquery = subquery

    def match(self, segment: Segment, similarity: Similarity) -> Dict[int, float]:
        scores = self.subquery.match(segment, similarity)
        return {doc_id: score * self.boost for doc_id, score in scores.items()}


class MatchAllDocsQuery(Query):
    """Matches all non-deleted documents in the segment."""

    def match(self, segment: Segment, similarity: Similarity) -> Dict[int, float]:
        scores: Dict[int, float] = {}
        for doc_id in range(segment.doc_count):
            if not segment.is_deleted(doc_id):
                scores[doc_id] = 1.0 * self.boost
        return scores


class TermQuery(Query):
    """Exact single term query on a specific field."""

    def __init__(self, field: str, term: str, boost: float = 1.0) -> None:
        super().__init__(boost=boost)
        self.field = field
        self.term = term.lower()

    def match(self, segment: Segment, similarity: Similarity) -> Dict[int, float]:
        key = f"{self.field}:{self.term}"
        plist = segment.postings.get(key)
        if not plist:
            return {}

        total_docs = max(segment.live_docs_count(), 1)
        doc_freq = plist.doc_freq()
        f_lens = segment.field_lengths.get(self.field, {})
        avg_doc_len = sum(f_lens.values()) / max(len(f_lens), 1) if f_lens else 1.0

        scores: Dict[int, float] = {}
        for entry in plist.get_postings():
            if segment.is_deleted(entry.doc_id):
                continue
            doc_len = f_lens.get(entry.doc_id, 1)
            raw_score = similarity.score(
                entry.tf, doc_len, avg_doc_len, doc_freq, total_docs
            )
            scores[entry.doc_id] = raw_score * self.boost
        return scores


class PhraseQuery(Query):
    """
    Proximity and phrase query with configurable slop (maximum word distance).
    Matches terms in consecutive or near-consecutive positions.
    """

    def __init__(
        self, field: str, terms: List[str], slop: int = 0, boost: float = 1.0
    ) -> None:
        super().__init__(boost=boost)
        self.field = field
        self.terms = [t.lower() for t in terms]
        self.slop = slop

    def match(self, segment: Segment, similarity: Similarity) -> Dict[int, float]:
        if not self.terms:
            return {}
        if len(self.terms) == 1:
            return TermQuery(self.field, self.terms[0], boost=self.boost).match(
                segment, similarity
            )
        return self._match_multi_terms(segment, similarity)

    def _intersect_common_docs(
        self, term_postings: List[Dict[int, PostingEntry]]
    ) -> Set[int]:
        common_docs = set(term_postings[0].keys())
        for tp in term_postings[1:]:
            common_docs.intersection_update(tp.keys())
        return common_docs

    def _score_single_phrase_doc(
        self,
        doc_id: int,
        term_postings: List[Dict[int, PostingEntry]],
        segment: Segment,
        similarity: Similarity,
        f_lens: Dict[int, int],
        avg_doc_len: float,
        num_common_docs: int,
        total_docs: int,
    ) -> Optional[float]:
        if segment.is_deleted(doc_id):
            return None
        pos_lists = [tp[doc_id].positions for tp in term_postings]
        phrase_tf = self._count_phrase_matches(pos_lists, self.slop)
        if phrase_tf <= 0:
            return None
        doc_len = f_lens.get(doc_id, 1)
        raw_score = similarity.score(
            phrase_tf * 2, doc_len, avg_doc_len, num_common_docs, total_docs
        )
        return raw_score * self.boost

    def _score_all_phrase_docs(
        self,
        common_docs: Set[int],
        term_postings: List[Dict[int, PostingEntry]],
        segment: Segment,
        similarity: Similarity,
        f_lens: Dict[int, int],
        avg_doc_len: float,
        total_docs: int,
    ) -> Dict[int, float]:
        scores: Dict[int, float] = {}
        for doc_id in common_docs:
            doc_score = self._score_single_phrase_doc(
                doc_id,
                term_postings,
                segment,
                similarity,
                f_lens,
                avg_doc_len,
                len(common_docs),
                total_docs,
            )
            if doc_score is not None:
                scores[doc_id] = doc_score
        return scores

    def _match_multi_terms(
        self, segment: Segment, similarity: Similarity
    ) -> Dict[int, float]:
        term_postings = self._get_term_postings(segment)
        if len(term_postings) != len(self.terms):
            return {}

        common_docs = self._intersect_common_docs(term_postings)
        if not common_docs:
            return {}

        total_docs = max(segment.live_docs_count(), 1)
        f_lens = segment.field_lengths.get(self.field, {})
        avg_doc_len = sum(f_lens.values()) / max(len(f_lens), 1) if f_lens else 1.0

        return self._score_all_phrase_docs(
            common_docs,
            term_postings,
            segment,
            similarity,
            f_lens,
            avg_doc_len,
            total_docs,
        )

    def _get_term_postings(self, segment: Segment) -> List[Dict[int, PostingEntry]]:
        postings_list: List[Dict[int, PostingEntry]] = []
        for t in self.terms:
            key = f"{self.field}:{t}"
            plist = segment.postings.get(key)
            if not plist:
                return []
            postings_list.append(plist.postings)
        return postings_list

    def _check_match_from_pos(
        self, start_pos: int, pos_lists: List[List[int]], slop: int
    ) -> bool:
        cur_pos = start_pos
        for i in range(1, len(pos_lists)):
            valid = [p for p in pos_lists[i] if 0 < (p - cur_pos) <= (1 + slop)]
            if not valid:
                return False
            cur_pos = min(valid)
        return True

    def _count_phrase_matches(self, pos_lists: List[List[int]], slop: int) -> int:
        if not all(pos_lists):
            return 0
        matches = 0
        for start_pos in pos_lists[0]:
            if self._check_match_from_pos(start_pos, pos_lists, slop):
                matches += 1
        return matches


class WildcardQuery(Query):
    """
    Wildcard query supporting '*' (any sequence) and '?' (single character).
    """

    def __init__(self, field: str, pattern: str, boost: float = 1.0) -> None:
        super().__init__(boost=boost)
        self.field = field
        self.pattern = pattern.lower()

    def _find_matching_keys(self, segment: Segment, prefix: str) -> List[str]:
        return [
            k
            for k in segment.postings.keys()
            if k.startswith(prefix) and fnmatch.fnmatch(k[len(prefix) :], self.pattern)
        ]

    def match(self, segment: Segment, similarity: Similarity) -> Dict[int, float]:
        prefix = f"{self.field}:"
        matching_keys = self._find_matching_keys(segment, prefix)
        if not matching_keys:
            return {}

        combined_scores: Dict[int, float] = {}
        for k in matching_keys:
            term = k[len(prefix) :]
            sub_scores = TermQuery(self.field, term, boost=self.boost).match(
                segment, similarity
            )
            for doc_id, score in sub_scores.items():
                combined_scores[doc_id] = combined_scores.get(doc_id, 0.0) + score
        return combined_scores


def _step_levenshtein_row(
    c1: str, s2: str, previous_row: List[int], i: int, max_distance: Optional[int]
) -> Optional[List[int]]:
    current_row = [i + 1]
    for j, c2 in enumerate(s2):
        val = min(
            previous_row[j + 1] + 1,
            current_row[j] + 1,
            previous_row[j] + (c1 != c2),
        )
        current_row.append(val)
    if max_distance is not None and min(current_row) > max_distance:
        return None
    return current_row


def _compute_levenshtein_dp(s1: str, s2: str, max_distance: Optional[int]) -> int:
    previous_row = list(range(len(s2) + 1))
    for i, c1 in enumerate(s1):
        next_row = _step_levenshtein_row(c1, s2, previous_row, i, max_distance)
        if next_row is None:
            return (max_distance + 1) if max_distance is not None else 999
        previous_row = next_row
    return previous_row[-1]


def _check_len_diff(s1: str, s2: str, max_distance: Optional[int]) -> Optional[int]:
    len_diff = abs(len(s1) - len(s2))
    threshold = max_distance if max_distance is not None else 999
    if len_diff > threshold:
        return (max_distance + 1) if max_distance is not None else len_diff
    return None


def compute_levenshtein(s1: str, s2: str, max_distance: Optional[int] = None) -> int:
    """Computes Levenshtein distance with early exit threshold."""
    diff = _check_len_diff(s1, s2, max_distance)
    if diff is not None:
        return diff
    if len(s1) < len(s2):
        return compute_levenshtein(s2, s1, max_distance)
    if not s2:
        return len(s1)
    return _compute_levenshtein_dp(s1, s2, max_distance)


class FuzzyQuery(Query):
    """
    Fuzzy query based on Levenshtein edit distance for typo tolerance.
    """

    def __init__(
        self, field: str, term: str, max_edits: int = 2, boost: float = 1.0
    ) -> None:
        super().__init__(boost=boost)
        self.field = field
        self.term = term.lower()
        self.max_edits = max_edits

    def _levenshtein(self, s1: str, s2: str, max_distance: Optional[int] = None) -> int:
        return compute_levenshtein(s1, s2, max_distance)

    def _score_fuzzy_term(
        self,
        term: str,
        segment: Segment,
        similarity: Similarity,
        combined_scores: Dict[int, float],
    ) -> None:
        if abs(len(term) - len(self.term)) > self.max_edits:
            return
        dist = compute_levenshtein(self.term, term, self.max_edits)
        if dist <= self.max_edits:
            decay = 1.0 - (dist / (self.max_edits + 1))
            sub_scores = TermQuery(self.field, term, boost=self.boost * decay).match(
                segment, similarity
            )
            for doc_id, score in sub_scores.items():
                combined_scores[doc_id] = max(combined_scores.get(doc_id, 0.0), score)

    def match(self, segment: Segment, similarity: Similarity) -> Dict[int, float]:
        prefix = f"{self.field}:"
        combined_scores: Dict[int, float] = {}
        for k in segment.postings.keys():
            if k.startswith(prefix):
                self._score_fuzzy_term(
                    k[len(prefix) :], segment, similarity, combined_scores
                )
        return combined_scores


class BooleanClause:
    """Clause encapsulating a subquery and an occurrence constraint."""

    def __init__(self, query: Query, occur: Occur) -> None:
        self.query = query
        self.occur = occur


class BooleanQuery(Query):
    """Boolean combination of MUST (+), SHOULD (OR), and MUST_NOT (-) clauses."""

    def __init__(
        self, clauses: Optional[List[BooleanClause]] = None, boost: float = 1.0
    ) -> None:
        super().__init__(boost=boost)
        self.clauses: List[BooleanClause] = clauses or []

    def add(self, query: Query, occur: Occur) -> "BooleanQuery":
        self.clauses.append(BooleanClause(query, occur))
        return self

    def _get_clauses_for(self, occur: Occur) -> List[BooleanClause]:
        return [c for c in self.clauses if c.occur == occur]

    def _collect_clauses_by_occur(
        self,
    ) -> Tuple[List[BooleanClause], List[BooleanClause], List[BooleanClause]]:
        return (
            self._get_clauses_for(Occur.MUST),
            self._get_clauses_for(Occur.SHOULD),
            self._get_clauses_for(Occur.MUST_NOT),
        )

    def match(self, segment: Segment, similarity: Similarity) -> Dict[int, float]:
        if not self.clauses:
            return {}

        must_clauses, should_clauses, must_not_clauses = (
            self._collect_clauses_by_occur()
        )
        scores = (
            self._match_must_clauses(must_clauses, should_clauses, segment, similarity)
            if must_clauses
            else self._match_should_clauses(should_clauses, segment, similarity)
        )

        self._exclude_must_not(scores, must_not_clauses, segment, similarity)
        return {d: s * self.boost for d, s in scores.items()}

    def _intersect_must_scores(
        self,
        must_clauses: List[BooleanClause],
        segment: Segment,
        similarity: Similarity,
    ) -> Tuple[Set[int], List[Dict[int, float]]]:
        first_scores = must_clauses[0].query.match(segment, similarity)
        matching_docs = set(first_scores.keys())
        all_must_scores = [first_scores]

        for c in must_clauses[1:]:
            sub_scores = c.query.match(segment, similarity)
            matching_docs.intersection_update(sub_scores.keys())
            all_must_scores.append(sub_scores)
        return matching_docs, all_must_scores

    def _add_should_scores_to_must(
        self,
        candidate_scores: Dict[int, float],
        should_clauses: List[BooleanClause],
        segment: Segment,
        similarity: Similarity,
    ) -> None:
        for c in should_clauses:
            sub_scores = c.query.match(segment, similarity)
            for doc_id in candidate_scores:
                if doc_id in sub_scores:
                    candidate_scores[doc_id] += sub_scores[doc_id]

    def _match_must_clauses(
        self,
        must_clauses: List[BooleanClause],
        should_clauses: List[BooleanClause],
        segment: Segment,
        similarity: Similarity,
    ) -> Dict[int, float]:
        matching_docs, all_must_scores = self._intersect_must_scores(
            must_clauses, segment, similarity
        )
        candidate_scores: Dict[int, float] = {
            doc_id: sum(sc.get(doc_id, 0.0) for sc in all_must_scores)
            for doc_id in matching_docs
        }
        self._add_should_scores_to_must(
            candidate_scores, should_clauses, segment, similarity
        )
        return candidate_scores

    def _match_should_clauses(
        self,
        should_clauses: List[BooleanClause],
        segment: Segment,
        similarity: Similarity,
    ) -> Dict[int, float]:
        scores: Dict[int, float] = {}
        for c in should_clauses:
            sub_scores = c.query.match(segment, similarity)
            for doc_id, score in sub_scores.items():
                scores[doc_id] = scores.get(doc_id, 0.0) + score
        return scores

    def _exclude_must_not(
        self,
        scores: Dict[int, float],
        must_not_clauses: List[BooleanClause],
        segment: Segment,
        similarity: Similarity,
    ) -> None:
        for c in must_not_clauses:
            sub_scores = c.query.match(segment, similarity)
            for doc_id in sub_scores:
                if doc_id in scores:
                    del scores[doc_id]


class SpellChecker:
    """Spellchecker and 'Did you mean' suggest engine based on index vocabulary."""

    def __init__(self, segment: Segment, field: str = "text") -> None:
        self.segment = segment
        self.field = field

    def _levenshtein(self, s1: str, s2: str, max_distance: Optional[int] = None) -> int:
        return compute_levenshtein(s1, s2, max_distance)

    def _collect_suggestion_candidate(
        self,
        term: str,
        w: str,
        max_edits: int,
        plist: Any,
        candidates: List[Tuple[str, int, int]],
    ) -> None:
        if abs(len(term) - len(w)) > max_edits:
            return
        dist = compute_levenshtein(w, term, max_edits)
        if 0 < dist <= max_edits:
            candidates.append((term, dist, plist.doc_freq()))

    def suggest(
        self, word: str, max_suggestions: int = 3, max_edits: int = 2
    ) -> List[str]:
        w = word.lower()
        prefix = f"{self.field}:"
        candidates: List[Tuple[str, int, int]] = []

        for k, plist in self.segment.postings.items():
            if k.startswith(prefix):
                self._collect_suggestion_candidate(
                    k[len(prefix) :], w, max_edits, plist, candidates
                )

        candidates.sort(key=lambda x: (x[1], -x[2]))
        return [c[0] for c in candidates[:max_suggestions]]


class SortOrder(Enum):
    ASC = "asc"
    DESC = "desc"


class SortField:
    """Definition of a sort criterion."""

    def __init__(
        self, field: str, order: SortOrder = SortOrder.DESC, is_score: bool = False
    ) -> None:
        self.field = field
        self.order = order
        self.is_score = is_score


class Sorter:
    """Multi-field composite sorter for search results."""

    def __init__(self, sort_fields: Optional[List[SortField]] = None) -> None:
        self.sort_fields = sort_fields or [SortField(field="_score", is_score=True)]

    def sort(
        self, segment: Segment, doc_scores: Dict[int, float]
    ) -> List[Tuple[int, float]]:
        """Sorts doc_ids according to configured multi-field criteria."""
        items = list(doc_scores.items())

        def sort_key(item: Tuple[int, float]) -> Tuple[Any, ...]:
            doc_id, score = item
            key_tuple: List[Any] = []
            for sf in self.sort_fields:
                val: Any
                if sf.is_score:
                    val = score if sf.order == SortOrder.ASC else -score
                else:
                    dv = segment.doc_values.get(sf.field)
                    raw_val = dv.get(doc_id) if dv else ""
                    if raw_val is None:
                        raw_val = ""
                    val = (
                        raw_val
                        if sf.order == SortOrder.ASC
                        else (
                            -(float(raw_val))
                            if isinstance(raw_val, (int, float))
                            else str(raw_val)
                        )
                    )
                key_tuple.append(val)
            return tuple(key_tuple)

        items.sort(key=sort_key)
        return items


class ScoreDoc:
    """Scored document result item."""

    __slots__ = ("doc_id", "score", "fields")

    def __init__(
        self, doc_id: int, score: float, fields: Optional[Dict[str, Any]] = None
    ) -> None:
        self.doc_id = doc_id
        self.score = score
        self.fields: Dict[str, Any] = fields or {}


class TopDocs:
    """Container for Top-N search result documents."""

    def __init__(self, total_hits: int, score_docs: List[ScoreDoc]) -> None:
        self.total_hits = total_hits
        self.score_docs = score_docs


class TopDocsCollector:
    """Collector aggregating top K ranked documents."""

    def __init__(self, top_k: int = 10, sorter: Optional[Sorter] = None) -> None:
        self.top_k = top_k
        self.sorter = sorter or Sorter()

    def collect(self, segment: Segment, doc_scores: Dict[int, float]) -> TopDocs:
        sorted_pairs = self.sorter.sort(segment, doc_scores)
        top_pairs = sorted_pairs[: self.top_k]
        score_docs = [
            ScoreDoc(
                doc_id=doc_id,
                score=score,
                fields=segment.stored_fields.get(doc_id) or {},
            )
            for doc_id, score in top_pairs
        ]
        return TopDocs(total_hits=len(sorted_pairs), score_docs=score_docs)
