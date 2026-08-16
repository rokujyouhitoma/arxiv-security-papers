#!/usr/bin/env python3
"""
Search Package for arXiv Security Papers.
Modularized enterprise search components providing:
- MultiFieldPostingsIndex (Multi-Field Inverted Index & Postings Lists)
- SearchAnalyzer (Multi-Stage Analyzer Pipeline)
- EnterpriseQueryParser (Multi-Field, Boolean, Phrase, Prefix, Fuzzy Query Parser)
- DynamicHighlighter (Safe Snippet Highlighter)
- FMIndex (Suffix Array / BWT Substring Search)
- QuerySemanticCache (Semantic Cache & Fast Lookup)
- FacetedIndex (Faceted & Temporal Filter)
- KnowledgeGraphIndex (Entity Relationships & GraphRAG)
- CitationNetworkIndex (Citation Authority & PageRank)
- RAPTORTreeIndex (Hierarchical Clustering & Summaries)
- SynonymExpander (Security Synonyms & IR Recall Boost)
- ProximityGraphIndex (Paper-to-Paper Topological k-NN Proximity Graph)
- VectorEngine (Enterprise Multi-Field & Hybrid RAG Engine)
"""

from .analyzer import SearchAnalyzer
from .citation_network import CitationNetworkIndex
from .faceted_index import FacetedIndex
from .field_schema import FieldType, MultiFieldPostingsIndex
from .fm_index import FMIndex
from .highlighter import DynamicHighlighter
from .knowledge_graph import KnowledgeGraphIndex
from .proximity_graph import ProximityGraphIndex
from .query_cache import QuerySemanticCache
from .query_parser import EnterpriseQueryParser, QueryClause
from .raptor_tree import RAPTORTreeIndex
from .synonym_expander import SynonymExpander
from .utils import extract_abstract_from_okf
from .vector_engine import VectorEngine

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
    "QuerySemanticCache",
    "RAPTORTreeIndex",
    "SearchAnalyzer",
    "SynonymExpander",
    "VectorEngine",
    "extract_abstract_from_okf",
]
