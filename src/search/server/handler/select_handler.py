#!/usr/bin/env python3
"""
Solr-style Select Request Handler (/select).
Orchestrates Query Parsing, FilterCache evaluation, Core Index Retrieval, BM25 Scoring, Faceting, and Highlighting.
"""

from typing import Any, Dict, List, Optional, Set

from ...core.analysis.token_filter import Analyzer
from ...core.index.doc_values import DocValues
from ...core.index.postings import MultiFieldPostingsIndex
from ...core.index.stored_fields import StoredFields
from ...core.search.collector import TopDocsCollector
from ...core.search.similarity import BM25Similarity
from ...utils.profiler import ExecutionProfiler
from ..cache.solr_cache import FilterCache, QueryResultCache
from ..facet.facet_engine import FacetEngine
from ..highlight.highlighter import FastVectorHighlighter
from ..schema.managed_schema import ManagedIndexSchema


class SelectHandler:
    """
    Handles search requests similar to Solr's SearchHandler.
    """

    def __init__(
        self,
        schema: Optional[ManagedIndexSchema] = None,
        analyzer: Optional[Analyzer] = None,
        postings_index: Optional[MultiFieldPostingsIndex] = None,
        doc_values: Optional[DocValues] = None,
        stored_fields: Optional[StoredFields] = None,
    ) -> None:
        self._init_schema_analyzer(schema, analyzer)
        self._init_storage_components(postings_index, doc_values, stored_fields)
        self.similarity = BM25Similarity()
        self.facet_engine = FacetEngine(self.doc_values)
        self.highlighter = FastVectorHighlighter()
        self.filter_cache = FilterCache(max_size=200)
        self.query_cache = QueryResultCache(max_size=500)

    def _init_schema_analyzer(
        self,
        schema: Optional[ManagedIndexSchema],
        analyzer: Optional[Analyzer],
    ) -> None:
        self.schema = schema or ManagedIndexSchema()
        self.analyzer = analyzer or Analyzer()

    def _init_storage_components(
        self,
        postings_index: Optional[MultiFieldPostingsIndex],
        doc_values: Optional[DocValues],
        stored_fields: Optional[StoredFields],
    ) -> None:
        self.postings = postings_index or MultiFieldPostingsIndex()
        self.doc_values = doc_values or DocValues()
        self.stored_fields = stored_fields or StoredFields()

    def _apply_filter_queries(
        self, filter_queries: Optional[Dict[str, str]]
    ) -> Optional[Set[str]]:
        if not filter_queries:
            return None
        filtered_doc_ids: Optional[Set[str]] = None
        for field, val in filter_queries.items():
            cache_key = f"{field}:{val}"
            cached_ids = self.filter_cache.get_filter_docs(cache_key)
            if cached_ids is None:
                matched = self.doc_values.get_doc_ids_matching(field, val)
                self.filter_cache.put_filter_docs(cache_key, matched)
                cached_ids = matched
            filtered_doc_ids = (
                cached_ids
                if filtered_doc_ids is None
                else (filtered_doc_ids & cached_ids)
            )
        return filtered_doc_ids

    def _score_postings_for_field(
        self,
        postings: List[tuple[str, int]],
        boost: float,
        filtered_doc_ids: Optional[Set[str]],
        total_docs: int,
        doc_scores: Dict[str, float],
    ) -> None:
        idf = self.similarity.compute_idf(len(postings), total_docs)
        for pid, tf in postings:
            if filtered_doc_ids is None or pid in filtered_doc_ids:
                bm25 = self.similarity.score(tf, 100, 100.0, idf)
                doc_scores[pid] = doc_scores.get(pid, 0.0) + bm25 * boost

    def _accumulate_term_postings(
        self,
        term: str,
        filtered_doc_ids: Optional[Set[str]],
        total_docs: int,
        doc_scores: Dict[str, float],
    ) -> None:
        for fname, fdef in self.schema.fields.items():
            postings = self.postings.get_postings(fname, term)
            if postings:
                self._score_postings_for_field(
                    postings, fdef.boost, filtered_doc_ids, total_docs, doc_scores
                )

    def _score_all_docs_fallback(
        self, all_docs: List[Dict[str, Any]], filtered_doc_ids: Optional[Set[str]]
    ) -> Dict[str, float]:
        doc_scores: Dict[str, float] = {}
        for doc in all_docs:
            did = doc.get("id", "")
            if filtered_doc_ids is None or did in filtered_doc_ids:
                doc_scores[did] = 1.0
        return doc_scores

    def _score_candidates(
        self,
        q_terms: List[str],
        filtered_doc_ids: Optional[Set[str]],
        total_docs: int,
        all_docs: List[Dict[str, Any]],
    ) -> Dict[str, float]:
        if not q_terms:
            return self._score_all_docs_fallback(all_docs, filtered_doc_ids)

        doc_scores: Dict[str, float] = {}
        for term in q_terms:
            self._accumulate_term_postings(
                term, filtered_doc_ids, total_docs, doc_scores
            )
        return doc_scores

    def _build_response_docs(
        self, score_docs: List[Any], q_terms: List[str]
    ) -> tuple[List[Dict[str, Any]], List[str]]:
        results: List[Dict[str, Any]] = []
        hit_ids: List[str] = []
        for sdoc in score_docs:
            hit_ids.append(sdoc.doc_id)
            doc_payload = self.stored_fields.get_document(sdoc.doc_id) or {}
            hl_snippets = self.highlighter.highlight_document(doc_payload, q_terms)
            result_entry = dict(doc_payload)
            result_entry["score"] = round(sdoc.score, 4)
            result_entry["highlight"] = hl_snippets.get(
                "description"
            ) or hl_snippets.get("title", "")
            results.append(result_entry)
        return results, hit_ids

    def _collect_top_docs(self, doc_scores: Dict[str, float], top_k: int) -> Any:
        collector = TopDocsCollector(top_k=top_k)
        for did, score in doc_scores.items():
            if score > 0:
                collector.collect(did, score)
        return collector.get_top_docs()

    def _compute_facet_counts(
        self,
        facet_fields: Optional[List[str]],
        hit_ids: List[str],
        all_docs: List[Dict[str, Any]],
    ) -> Dict[str, Dict[str, int]]:
        if not facet_fields:
            return {}
        return self.facet_engine.count_facets(
            hit_ids or [d.get("id", "") for d in all_docs], facet_fields
        )

    def _format_select_response(
        self,
        prof: ExecutionProfiler,
        query: str,
        top_k: int,
        top_docs: Any,
        results: List[Dict[str, Any]],
        facets_data: Dict[str, Dict[str, int]],
    ) -> Dict[str, Any]:
        return {
            "responseHeader": {
                "status": 0,
                "QTime": prof.total_ms,
                "cpu_time_ms": prof.cpu_ms,
                "peak_memory_kb": prof.peak_memory_kb,
                "params": {"q": query, "rows": top_k},
            },
            "response": {
                "numFound": top_docs.total_hits,
                "start": 0,
                "maxScore": top_docs.max_score,
                "docs": results,
            },
            "facet_counts": {
                "facet_fields": facets_data,
                **facets_data,
            },
            "performance": {
                "total_ms": prof.total_ms,
                "cpu_time_ms": prof.cpu_ms,
                "peak_memory_kb": prof.peak_memory_kb,
            },
        }

    def handle_select(
        self,
        query: str,
        filter_queries: Optional[Dict[str, str]] = None,
        facet_fields: Optional[List[str]] = None,
        top_k: int = 10,
    ) -> Dict[str, Any]:
        """Executes full search, filtering, faceting, and highlighting with full observability."""
        with ExecutionProfiler("select_handler") as prof:
            q_clean = (query or "").strip()
            tokens = self.analyzer.analyze(q_clean)
            q_terms = [t.text.lower() for t in tokens]

            filtered_doc_ids = self._apply_filter_queries(filter_queries)
            all_docs = self.stored_fields.all_documents()
            doc_scores = self._score_candidates(
                q_terms, filtered_doc_ids, len(all_docs), all_docs
            )

            top_docs = self._collect_top_docs(doc_scores, top_k)
            results, hit_ids = self._build_response_docs(top_docs.score_docs, q_terms)
            facets_data = self._compute_facet_counts(facet_fields, hit_ids, all_docs)

            return self._format_select_response(
                prof, query, top_k, top_docs, results, facets_data
            )
