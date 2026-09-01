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
        self._init_schema_similarity(schema, analyzer, similarity)
        self._init_cache_elevation(cache, elevation)
        self.highlighter = DynamicHighlighter()
        self.facet_engine = FacetEngine()

    def _init_schema_similarity(
        self,
        schema: Optional[ManagedSchema],
        analyzer: Optional[Analyzer],
        similarity: Optional[Similarity],
    ) -> None:
        self.schema = schema or ManagedSchema()
        self.analyzer = analyzer or CJKAnalyzer()
        self.similarity = similarity or BM25Similarity()

    def _init_cache_elevation(
        self,
        cache: Optional[SolrCache],
        elevation: Optional[QueryElevationComponent],
    ) -> None:
        self.cache = cache or SolrCache()
        self.elevation = elevation or QueryElevationComponent()

    def parse_query(self, query_str: str, default_field: str = "title") -> Query:
        """Parses user query string supporting boolean syntax, wildcards (*), phrases, and field:term."""
        q = query_str.strip()
        if not q or q == "*:*":
            return MatchAllDocsQuery()
        if ":" in q and not q.startswith("http"):
            parts = q.split(":", 1)
            return self.parse_query(parts[1].strip(), default_field=parts[0].strip())
        return self._dispatch_query_type(q, default_field)

    def _is_phrase_query(self, q: str) -> bool:
        return bool(q.startswith('"') and q.endswith('"') and len(q) > 2)

    def _dispatch_query_type(self, q: str, default_field: str) -> Query:
        if self._is_phrase_query(q):
            return PhraseQuery(default_field, self.analyzer.analyze(q[1:-1].strip()), slop=1)
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

    def _get_doc_by_id_fn(self, segment: Segment) -> Any:
        def get_doc_by_id(doc_id_val: str) -> Optional[Dict[str, Any]]:
            for d_id in range(segment.doc_count):
                if not segment.is_deleted(d_id):
                    doc_data = segment.stored_fields.get(d_id)
                    if doc_data and str(doc_data.get("id", d_id)) == str(doc_id_val):
                        return doc_data
            return None
        return get_doc_by_id

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

        top_docs = self.elevation.elevate(
            query_str, top_docs, id_field="id", get_doc_by_id_fn=self._get_doc_by_id_fn(segment)
        )
        return self._build_response(
            segment, top_docs, doc_scores, query_str, start, rows, params
        )

    def _resolve_single_fq(self, segment: Segment, fq_str: str) -> Set[int]:
        cached_doc_ids = self.cache.filter_cache.get(fq_str)
        if cached_doc_ids is None:
            cached_doc_ids = self._resolve_filter_ids(segment, fq_str)
            self.cache.filter_cache.put(fq_str, cached_doc_ids)
        return cached_doc_ids

    def _apply_single_filter(self, segment: Segment, doc_scores: Dict[int, float], fq_str: str) -> Dict[int, float]:
        if not fq_str:
            return doc_scores
        cached_ids = self._resolve_single_fq(segment, fq_str)
        return {d: s for d, s in doc_scores.items() if d in cached_ids}

    def _apply_filter_queries(
        self, segment: Segment, doc_scores: Dict[int, float], fq_list: Any
    ) -> Dict[int, float]:
        fqs = [fq_list] if isinstance(fq_list, str) else (fq_list or [])
        for fq_str in fqs:
            doc_scores = self._apply_single_filter(segment, doc_scores, fq_str)
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

    def _check_doc_value_match(self, d_val: Any, val: str) -> bool:
        if d_val is None:
            return False
        if isinstance(d_val, list):
            return any(str(v).lower() == val.lower() for v in d_val)
        return str(d_val).lower() == val.lower()

    def _match_doc_values(self, segment: Segment, field: str, val: str) -> Set[int]:
        dv = segment.doc_values.get(field)
        if not dv:
            return set()
        matched: Set[int] = set()
        for d_id in range(segment.doc_count):
            if not segment.is_deleted(d_id) and self._check_doc_value_match(dv.get(d_id), val):
                matched.add(d_id)
        return matched

    def _append_spellcheck(self, response: Dict[str, Any], segment: Segment, top_docs: Any, query_str: str) -> None:
        if top_docs.total_hits == 0 and query_str and query_str != "*:*":
            response["spellcheck"] = {
                "suggestions": SpellChecker(segment, field="title").suggest(query_str)
            }

    def _append_facets_and_highlights(
        self, response: Dict[str, Any], segment: Segment, top_docs: Any, doc_scores: Dict[int, float], query_str: str, start: int, rows: int, params: Dict[str, Any]
    ) -> None:
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
        self._append_spellcheck(response, segment, top_docs, query_str)

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
        self._append_facets_and_highlights(response, segment, top_docs, doc_scores, query_str, start, rows, params)
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

    def _parse_sort_field(self, part: str) -> Optional[SortField]:
        tokens = part.strip().split()
        if not tokens:
            return None
        fname = tokens[0]
        order = (
            SortOrder.DESC
            if len(tokens) > 1 and tokens[1].lower() == "desc"
            else SortOrder.ASC
        )
        is_score = fname in ["_score", "score"]
        field_name = "_score" if is_score else fname
        return SortField(field=field_name, order=order, is_score=is_score)

    def _build_sorter(self, sort_param: str) -> Sorter:
        sort_fields = [
            sf for part in sort_param.split(",")
            if (sf := self._parse_sort_field(part)) is not None
        ]
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

    def _analyze_field_val(self, val: Any) -> List[str]:
        if isinstance(val, str):
            return self.analyzer.analyze(val)
        if isinstance(val, list):
            return self.analyzer.analyze(" ".join(str(v) for v in val))
        return []

    def add_document(self, segment: Segment, raw_doc: Dict[str, Any]) -> int:
        """Processes document through Schema (copyFields/dynamicFields) and indexes it into segment."""
        processed_doc = self.schema.process_document(raw_doc)
        doc_id = segment.doc_count

        analyzed_fields: Dict[str, List[str]] = {}
        for fname, val in processed_doc.items():
            fdef = self.schema.get_field_definition(fname)
            if fdef.indexed and val:
                analyzed = self._analyze_field_val(val)
                if analyzed:
                    analyzed_fields[fname] = analyzed

        segment.add_document(
            doc_id, fields=processed_doc, analyzed_fields=analyzed_fields
        )
        return doc_id

    def delete_by_id(self, segment: Segment, doc_id: int) -> None:
        segment.deleted_docs.delete(doc_id)
