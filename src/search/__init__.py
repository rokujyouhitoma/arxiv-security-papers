#!/usr/bin/env python3
"""
Search Package for arXiv Security Papers.
Modularized enterprise search architecture structured into functional subpackages:
- ingestion: SearchAnalyzer, MultiFieldPostingsIndex, FMIndex, FacetedIndex, RAPTORTreeIndex
- query: EnterpriseQueryParser, QueryClause, QueryContext, SynonymExpander, QuerySemanticCache
- ranking: CitationNetworkIndex, KnowledgeGraphIndex, ProximityGraphIndex
- presentation: DynamicHighlighter
- vector_engine: VectorEngine
"""

import sys

# Subpackages
from . import ingestion, presentation, query, ranking
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
    "CitationNetworkIndex",
    "DynamicHighlighter",
    "EnterpriseQueryParser",
    "FacetedIndex",
    "FieldType",
    "FMIndex",
    "KnowledgeGraphIndex",
    "MultiFieldPostingsIndex",
    "ProximityGraphIndex",
    "QueryClause",
    "QueryContext",
    "QuerySemanticCache",
    "RAPTORTreeIndex",
    "SearchAnalyzer",
    "SynonymExpander",
    "TokenOffset",
    "VectorEngine",
    "extract_abstract_from_okf",
    "ingestion",
    "presentation",
    "query",
    "ranking",
]
