#!/usr/bin/env python3
"""
Query Elevation Component for Fixed/Promoted Search Results (Solr Paradigm).
Enables pinning specific papers/documents to the top of search results for designated query terms.
"""

from typing import Any, Dict, List, Optional, Set

from ...engine.search import ScoreDoc, TopDocs


class ElevationRule:
    """Rule defining elevated and excluded document IDs for a query phrase."""

    def __init__(
        self,
        query_phrase: str,
        elevated_ids: List[str],
        excluded_ids: Optional[List[str]] = None,
    ) -> None:
        self.query_phrase = query_phrase.strip().lower()
        self.elevated_ids = elevated_ids
        self.excluded_ids = excluded_ids or []


class QueryElevationComponent:
    """
    Solr QueryElevationComponent equivalent.
    Overrides natural relevance ranking by forcing promoted/fixed documents to the top.
    """

    def __init__(self) -> None:
        self._rules: Dict[str, ElevationRule] = {}

    def add_elevation_rule(
        self,
        query_phrase: str,
        elevated_ids: List[str],
        excluded_ids: Optional[List[str]] = None,
    ) -> "QueryElevationComponent":
        rule = ElevationRule(query_phrase, elevated_ids, excluded_ids)
        self._rules[rule.query_phrase] = rule
        return self

    def _partition_docs(
        self,
        score_docs: List[ScoreDoc],
        id_field: str,
        excluded_set: Set[str],
        elevated_list: List[str],
    ) -> tuple[Dict[str, ScoreDoc], List[ScoreDoc]]:
        existing_elevated: Dict[str, ScoreDoc] = {}
        filtered_docs: List[ScoreDoc] = []
        for sdoc in score_docs:
            doc_id_val = str(sdoc.fields.get(id_field, sdoc.doc_id))
            if doc_id_val in excluded_set:
                continue
            if doc_id_val in elevated_list:
                existing_elevated[doc_id_val] = sdoc
            else:
                filtered_docs.append(sdoc)
        return existing_elevated, filtered_docs

    def _build_promoted_doc(
        self,
        idx: int,
        promoted_id: str,
        existing_elevated: Dict[str, ScoreDoc],
        get_doc_by_id_fn: Optional[Any],
    ) -> Optional[ScoreDoc]:
        if promoted_id in existing_elevated:
            sdoc = existing_elevated[promoted_id]
            return ScoreDoc(doc_id=sdoc.doc_id, score=1000.0 - idx, fields=sdoc.fields)
        if get_doc_by_id_fn:
            doc_fields = get_doc_by_id_fn(promoted_id)
            if doc_fields:
                return ScoreDoc(doc_id=-1, score=1000.0 - idx, fields=doc_fields)
        return None

    def elevate(
        self,
        query_str: str,
        top_docs: TopDocs,
        id_field: str = "id",
        get_doc_by_id_fn: Optional[Any] = None,
    ) -> TopDocs:
        """Applies elevation rules to promote/exclude documents in TopDocs."""
        q_norm = query_str.strip().lower()
        rule = self._rules.get(q_norm)
        if not rule:
            return top_docs

        existing_elevated, filtered_docs = self._partition_docs(
            top_docs.score_docs, id_field, set(rule.excluded_ids), rule.elevated_ids
        )

        promoted_docs = [
            pdoc
            for idx, pid in enumerate(rule.elevated_ids)
            if (
                pdoc := self._build_promoted_doc(
                    idx, pid, existing_elevated, get_doc_by_id_fn
                )
            )
            is not None
        ]

        final_score_docs = promoted_docs + filtered_docs
        return TopDocs(total_hits=len(final_score_docs), score_docs=final_score_docs)
