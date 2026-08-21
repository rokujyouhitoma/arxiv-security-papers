#!/usr/bin/env python3
"""
Request Handlers (Select, Update, Admin) for Search Platform (Solr Paradigm).
"""

from typing import Any, Dict, List, Optional, Set

from ...engine.analysis import Analyzer, CJKAnalyzer
from ...engine.index import Segment
from ...engine.search import (
    BM25Similarity,
    BooleanQuery,
    FuzzyQuery,
    MatchAllDocsQuery,
    Occur,
    PhraseQuery,
    Query,
    Similarity,
    Sorter,
    SortField,
    SortOrder,
    SpellChecker,
    TermQuery,
    TopDocsCollector,
    WildcardQuery,
)
from ..cache import SolrCache
from ..elevation import QueryElevationComponent
from ..facet import FacetEngine
from ..highlight import DynamicHighlighter
from ..schema import ManagedSchema


class SelectHandler:
    """
    Search Request Handler (/api/search, /select) coordinating parsing,
    elevation, filtering, faceting, highlighting, and caching.
    """

    def __init__(
        self,
        schema: Optional[ManagedSchema] = None,
        analyzer: Optional[Analyzer] = None,
        similarity: Optional[Similarity] = None,
        cache: Optional[SolrCache] = None,
        elevation: Optional[QueryElevationComponent] = None,
    ) -> None:
        self.schema = schema or ManagedSchema()
        self.analyzer = analyzer or CJKAnalyzer()
        self.similarity = similarity or BM25Similarity()
        self.cache = cache or SolrCache()
        self.elevation = elevation or QueryElevationComponent()
        self.highlighter = DynamicHighlighter()
        self.facet_engine = FacetEngine()

    def parse_query(self, query_str: str, default_field: str = "title") -> Query:
        """Parses user query string supporting boolean syntax, wildcards (*), phrases, and field:term."""
        q = query_str.strip()
        if not q or q == "*:*":
            return MatchAllDocsQuery()
        if ":" in q and not q.startswith("http"):
            parts = q.split(":", 1)
            return self.parse_query(parts[1].strip(), default_field=parts[0].strip())
        return self._dispatch_query_type(q, default_field)

    def _dispatch_query_type(self, q: str, default_field: str) -> Query:
        if q.startswith('"') and q.endswith('"') and len(q) > 2:
            return PhraseQuery(
                default_field, self.analyzer.analyze(q[1:-1].strip()), slop=1
            )
        if "*" in q or "?" in q:
            return WildcardQuery(default_field, q)
        if "~" in q:
            return self._parse_fuzzy(q, default_field)
        return self._parse_terms(q, default_field)

    def _parse_fuzzy(self, q: str, default_field: str) -> Query:
        parts = q.split("~")
        term = parts[0]
        max_edits = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 2
        return FuzzyQuery(default_field, term, max_edits=max_edits)

    def _parse_terms(self, q: str, default_field: str) -> Query:
        tokens = self.analyzer.analyze(q)
        if not tokens:
            return MatchAllDocsQuery()
        b_query = BooleanQuery()
        for token in tokens:
            b_query.add(TermQuery(default_field, token), Occur.SHOULD)
            if default_field == "title":
                b_query.add(TermQuery("abstract", token, boost=0.6), Occur.SHOULD)
                b_query.add(TermQuery("_text_", token, boost=0.8), Occur.SHOULD)
        return b_query

    def handle_request(
        self, segment: Segment, params: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Executes search request with filtering, faceting, highlighting, and elevation."""
        query_str = params.get("q", "*:*").strip()
        start, rows = int(params.get("start", 0)), int(params.get("rows", 10))

        doc_scores = self.parse_query(query_str).match(segment, self.similarity)
        doc_scores = self._apply_filter_queries(
            segment, doc_scores, params.get("fq", [])
        )

        sorter = self._build_sorter(params.get("sort", "_score desc"))
        collector = TopDocsCollector(top_k=start + rows, sorter=sorter)
        top_docs = collector.collect(segment, doc_scores)

        def get_doc_by_id(doc_id_val: str) -> Optional[Dict[str, Any]]:
            for d_id in range(segment.doc_count):
                if not segment.is_deleted(d_id):
                    doc_data = segment.stored_fields.get(d_id)
                    if doc_data and str(doc_data.get("id", d_id)) == str(doc_id_val):
                        return doc_data
            return None

        top_docs = self.elevation.elevate(
            query_str, top_docs, id_field="id", get_doc_by_id_fn=get_doc_by_id
        )
        return self._build_response(
            segment, top_docs, doc_scores, query_str, start, rows, params
        )

    def _apply_filter_queries(
        self, segment: Segment, doc_scores: Dict[int, float], fq_list: Any
    ) -> Dict[int, float]:
        fqs = [fq_list] if isinstance(fq_list, str) else (fq_list or [])
        for fq_str in fqs:
            if not fq_str:
                continue
            cached_doc_ids = self.cache.filter_cache.get(fq_str)
            if cached_doc_ids is None:
                cached_doc_ids = self._resolve_filter_ids(segment, fq_str)
                self.cache.filter_cache.put(fq_str, cached_doc_ids)
            doc_scores = {d: s for d, s in doc_scores.items() if d in cached_doc_ids}
        return doc_scores

    def _resolve_filter_ids(self, segment: Segment, fq_str: str) -> Set[int]:
        field, val = fq_str.split(":", 1) if ":" in fq_str else ("category", fq_str)
        field, val = field.strip(), val.strip()

        matched = self._match_doc_values(segment, field, val)
        if matched:
            return matched

        fq_scores = self.parse_query(fq_str, default_field=field).match(
            segment, self.similarity
        )
        return set(fq_scores.keys())

    def _match_doc_values(self, segment: Segment, field: str, val: str) -> Set[int]:
        dv = segment.doc_values.get(field)
        if not dv:
            return set()
        matched: Set[int] = set()
        for d_id in range(segment.doc_count):
            if not segment.is_deleted(d_id):
                d_val = dv.get(d_id)
                if d_val is not None:
                    if isinstance(d_val, list):
                        if any(str(v).lower() == val.lower() for v in d_val):
                            matched.add(d_id)
                    elif str(d_val).lower() == val.lower():
                        matched.add(d_id)
        return matched

    def _build_response(
        self,
        segment: Segment,
        top_docs: Any,
        doc_scores: Dict[int, float],
        query_str: str,
        start: int,
        rows: int,
        params: Dict[str, Any],
    ) -> Dict[str, Any]:
        paginated_docs = [
            {"id": s.fields.get("id", s.doc_id), "score": round(s.score, 4), **s.fields}
            for s in top_docs.score_docs[start : start + rows]
        ]
        response: Dict[str, Any] = {
            "responseHeader": {"status": 0, "qTime": 1, "params": params},
            "response": {
                "numFound": top_docs.total_hits,
                "start": start,
                "docs": paginated_docs,
            },
        }
        if params.get("facet"):
            response["facet_counts"] = {
                "facet_fields": self.facet_engine.compute_facets(
                    segment, list(doc_scores.keys())
                )
            }
        if params.get("hl"):
            response["highlighting"] = self._compute_highlights(
                top_docs, query_str, start, rows
            )
        if top_docs.total_hits == 0 and query_str and query_str != "*:*":
            response["spellcheck"] = {
                "suggestions": SpellChecker(segment, field="title").suggest(query_str)
            }
        return response

    def _compute_highlights(
        self, top_docs: Any, query_str: str, start: int, rows: int
    ) -> Dict[str, Dict[str, str]]:
        highlight_res: Dict[str, Dict[str, str]] = {}
        q_tokens = self.analyzer.analyze(query_str)
        for sdoc in top_docs.score_docs[start : start + rows]:
            doc_key = str(sdoc.fields.get("id", sdoc.doc_id))
            hl_fields: Dict[str, str] = {}
            for fname in ["title", "abstract", "summary"]:
                f_val = sdoc.fields.get(fname, "")
                if f_val and isinstance(f_val, str):
                    hl_fields[fname] = self.highlighter.highlight(f_val, q_tokens)
            highlight_res[doc_key] = hl_fields
        return highlight_res

    def _build_sorter(self, sort_param: str) -> Sorter:
        sort_fields: List[SortField] = []
        for part in sort_param.split(","):
            tokens = part.strip().split()
            if not tokens:
                continue
            fname = tokens[0]
            order = (
                SortOrder.DESC
                if len(tokens) > 1 and tokens[1].lower() == "desc"
                else SortOrder.ASC
            )
            if fname in ["_score", "score"]:
                sort_fields.append(
                    SortField(field="_score", order=order, is_score=True)
                )
            else:
                sort_fields.append(SortField(field=fname, order=order, is_score=False))
        return Sorter(sort_fields)


class UpdateHandler:
    """Handles document indexing, dynamic field processing, copy fields, and commit operations."""

    def __init__(
        self,
        schema: Optional[ManagedSchema] = None,
        analyzer: Optional[Analyzer] = None,
    ) -> None:
        self.schema = schema or ManagedSchema()
        self.analyzer = analyzer or CJKAnalyzer()

    def add_document(self, segment: Segment, raw_doc: Dict[str, Any]) -> int:
        """Processes document through Schema (copyFields/dynamicFields) and indexes it into segment."""
        processed_doc = self.schema.process_document(raw_doc)
        doc_id = segment.doc_count

        analyzed_fields: Dict[str, List[str]] = {}
        for fname, val in processed_doc.items():
            fdef = self.schema.get_field_definition(fname)
            if fdef.indexed and val:
                if isinstance(val, str):
                    analyzed_fields[fname] = self.analyzer.analyze(val)
                elif isinstance(val, list):
                    analyzed_fields[fname] = self.analyzer.analyze(
                        " ".join(str(v) for v in val)
                    )

        segment.add_document(
            doc_id, fields=processed_doc, analyzed_fields=analyzed_fields
        )
        return doc_id

    def delete_by_id(self, segment: Segment, doc_id: int) -> None:
        segment.deleted_docs.delete(doc_id)
