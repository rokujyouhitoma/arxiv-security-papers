#!/usr/bin/env python3
"""
Search Package for arXiv Security Papers.
Modularized search components providing:
- FMIndex (Suffix Array / BWT Substring Search)
- QuerySemanticCache (Semantic Cache & Fast Lookup)
- FacetedIndex (Faceted & Temporal Filter)
- KnowledgeGraphIndex (Entity Relationships & GraphRAG)
- CitationNetworkIndex (Citation Authority & PageRank)
- RAPTORTreeIndex (Hierarchical Clustering & Summaries)
- SynonymExpander (Security Synonyms & IR Recall Boost)
- VectorEngine (4-Stage Hybrid RAG Engine)
"""

from .citation_network import CitationNetworkIndex
from .faceted_index import FacetedIndex
from .fm_index import FMIndex
from .knowledge_graph import KnowledgeGraphIndex
from .query_cache import QuerySemanticCache
from .raptor_tree import RAPTORTreeIndex
from .synonym_expander import SynonymExpander
from .utils import extract_abstract_from_okf
from .vector_engine import VectorEngine

__all__ = [
    "CitationNetworkIndex",
    "FacetedIndex",
    "FMIndex",
    "KnowledgeGraphIndex",
    "QuerySemanticCache",
    "RAPTORTreeIndex",
    "SynonymExpander",
    "VectorEngine",
    "extract_abstract_from_okf",
]
