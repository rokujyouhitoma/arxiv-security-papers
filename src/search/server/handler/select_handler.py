#!/usr/bin/env python3
"""
Solr-style Select Request Handler (/select).
Orchestrates Query Parsing, FilterCache evaluation, Core Index Retrieval, BM25 Scoring, Faceting, and Highlighting.
"""

import time
from typing import Any, Dict, List, Optional, Set

from ...core.analysis.token_filter import Analyzer
from ...core.index.doc_values import DocValues
from ...core.index.postings import MultiFieldPostingsIndex
from ...core.index.stored_fields import StoredFields
from ...core.search.collector import TopDocsCollector
from ...core.search.similarity import BM25Similarity
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
        self.schema = schema or ManagedIndexSchema()
        self.analyzer = analyzer or Analyzer()
        self.postings = postings_index or MultiFieldPostingsIndex()
        self.doc_values = doc_values or DocValues()
        self.stored_fields = stored_fields or StoredFields()

        self.similarity = BM25Similarity()
        self.facet_engine = FacetEngine(self.doc_values)
        self.highlighter = FastVectorHighlighter()
        self.filter_cache = FilterCache(max_size=200)
        self.query_cache = QueryResultCache(max_size=500)

    def handle_select(
        self,
        query: str,
        filter_queries: Optional[Dict[str, str]] = None,
        facet_fields: Optional[List[str]] = None,
        top_k: int = 10,
    ) -> Dict[str, Any]:
        """Executes full search, filtering, faceting, and highlighting."""
        t0 = time.perf_counter()
        q_clean = (query or "").strip()
        tokens = self.analyzer.analyze(q_clean)
        q_terms = [t.text.lower() for t in tokens]

        # 1. Apply Filter Queries (using FilterCache)
        filtered_doc_ids: Optional[Set[str]] = None
        if filter_queries:
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

        # 2. Candidate Retrieval & Scoring
        collector = TopDocsCollector(top_k=top_k)
        all_docs = self.stored_fields.all_documents()
        total_docs = len(all_docs)

        for doc in all_docs:
            doc_id = doc.get("id", "")
            if filtered_doc_ids is not None and doc_id not in filtered_doc_ids:
                continue

            score = 0.0
            if not q_terms:
                score = 1.0
            else:
                for term in q_terms:
                    # Check fields in schema with boosts
                    for fname, fdef in self.schema.fields.items():
                        postings = self.postings.get_postings(fname, term)
                        for pid, tf in postings:
                            if pid == doc_id:
                                idf = self.similarity.compute_idf(
                                    len(postings), total_docs
                                )
                                bm25 = self.similarity.score(tf, 100, 100.0, idf)
                                score += bm25 * fdef.boost

            if score > 0:
                collector.collect(doc_id, score)

        top_docs = collector.get_top_docs()

        # 3. Retrieve Stored Fields & Generate Highlights
        results: List[Dict[str, Any]] = []
        hit_ids: List[str] = []
        for sdoc in top_docs.score_docs:
            hit_ids.append(sdoc.doc_id)
            doc_payload = self.stored_fields.get_document(sdoc.doc_id) or {}
            hl_snippets = self.highlighter.highlight_document(doc_payload, q_terms)

            result_entry = dict(doc_payload)
            result_entry["score"] = round(sdoc.score, 4)
            result_entry["highlight"] = hl_snippets.get(
                "description"
            ) or hl_snippets.get("title", "")
            results.append(result_entry)

        # 4. Facet Aggregations
        facets_data: Dict[str, Dict[str, int]] = {}
        if facet_fields:
            facets_data = self.facet_engine.count_facets(
                hit_ids or [d.get("id", "") for d in all_docs], facet_fields
            )

        t_end = time.perf_counter()
        return {
            "responseHeader": {
                "status": 0,
                "QTime": round((t_end - t0) * 1000, 2),
                "params": {"q": query, "top_k": top_k},
            },
            "response": {
                "numFound": top_docs.total_hits,
                "start": 0,
                "docs": results,
            },
            "facet_counts": facets_data,
        }
