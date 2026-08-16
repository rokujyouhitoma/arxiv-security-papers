#!/usr/bin/env python3
"""
Search Package for arXiv Security Papers.
Modularized 2-tier search architecture:
- core: Lucene-equivalent core search engine (analysis, store, index, search)
- server: Solr-equivalent enterprise search server (schema, handler, facet, highlight, cache)
- legacy functional subpackages: ingestion, query, ranking, presentation, vector_engine
"""

import sys

# Subpackages
from . import core, ingestion, presentation, query, ranking, server
from .core import (
    Analyzer,
    BM25Similarity,
    BooleanClause,
    BooleanQuery,
    CharFilter,
    DeletedDocsBitset,
    Directory,
    DocValues,
    FSDirectory,
    FuzzyQuery,
    HTMLStripCharFilter,
    LowerCaseFilter,
    PhraseQuery,
    PostingsList,
    PrefixQuery,
    RAMDirectory,
    ScoreDoc,
    SegmentInfo,
    Similarity,
    StandardTokenizer,
    StopWordFilter,
    StoredFields,
    TermQuery,
    Token,
    TokenFilter,
    Tokenizer,
    TopDocs,
    TopDocsCollector,
    UnicodeNormalizeCharFilter,
)
from .ingestion import (
    FacetedIndex,
    FieldType,
    FMIndex,
    MultiFieldPostingsIndex,
    RAPTORTreeIndex,
    SearchAnalyzer,
    TokenOffset,
)
from .presentation import DynamicHighlighter
from .query import (
    EnterpriseQueryParser,
    QueryClause,
    QueryContext,
    QuerySemanticCache,
    SynonymExpander,
)
from .ranking import CitationNetworkIndex, KnowledgeGraphIndex, ProximityGraphIndex
from .server import (
    FacetEngine,
    FastVectorHighlighter,
    FieldDefinition,
    FilterCache,
    LRUCache,
    ManagedIndexSchema,
    QueryResultCache,
    SelectHandler,
)
from .utils import extract_abstract_from_okf
from .vector_engine import VectorEngine

# Backward compatibility aliases for legacy direct module imports (e.g. search.query_parser)
sys.modules[__name__ + ".analyzer"] = ingestion.analyzer
sys.modules[__name__ + ".field_schema"] = ingestion.field_schema
sys.modules[__name__ + ".fm_index"] = ingestion.fm_index
sys.modules[__name__ + ".faceted_index"] = ingestion.faceted_index
sys.modules[__name__ + ".raptor_tree"] = ingestion.raptor_tree
sys.modules[__name__ + ".query_parser"] = query.query_parser
sys.modules[__name__ + ".synonym_expander"] = query.synonym_expander
sys.modules[__name__ + ".query_cache"] = query.query_cache
sys.modules[__name__ + ".knowledge_graph"] = ranking.knowledge_graph
sys.modules[__name__ + ".proximity_graph"] = ranking.proximity_graph
sys.modules[__name__ + ".citation_network"] = ranking.citation_network
sys.modules[__name__ + ".highlighter"] = presentation.highlighter

__all__ = [
    "Analyzer",
    "BM25Similarity",
    "BooleanClause",
    "BooleanQuery",
    "CharFilter",
    "CitationNetworkIndex",
    "DeletedDocsBitset",
    "Directory",
    "DocValues",
    "DynamicHighlighter",
    "EnterpriseQueryParser",
    "FacetEngine",
    "FacetedIndex",
    "FastVectorHighlighter",
    "FieldDefinition",
    "FieldType",
    "FilterCache",
    "FMIndex",
    "FSDirectory",
    "FuzzyQuery",
    "HTMLStripCharFilter",
    "KnowledgeGraphIndex",
    "LRUCache",
    "LowerCaseFilter",
    "ManagedIndexSchema",
    "MultiFieldPostingsIndex",
    "PhraseQuery",
    "PostingsList",
    "PrefixQuery",
    "ProximityGraphIndex",
    "Query",
    "QueryClause",
    "QueryContext",
    "QueryResultCache",
    "QuerySemanticCache",
    "RAMDirectory",
    "RAPTORTreeIndex",
    "ScoreDoc",
    "SearchAnalyzer",
    "SegmentInfo",
    "SelectHandler",
    "Similarity",
    "StandardTokenizer",
    "StopWordFilter",
    "StoredFields",
    "SynonymExpander",
    "TermQuery",
    "Token",
    "TokenFilter",
    "TokenOffset",
    "Tokenizer",
    "TopDocs",
    "TopDocsCollector",
    "UnicodeNormalizeCharFilter",
    "VectorEngine",
    "core",
    "extract_abstract_from_okf",
    "ingestion",
    "presentation",
    "query",
    "ranking",
    "server",
]
