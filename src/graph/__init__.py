#!/usr/bin/env python3
"""
Property Graph Database Engine Package.
Non-invasive graph engine providing Apache TinkerPop Gremlin-compatible Fluent Traversal,
Dual CSR Adjacency Indexing, and GraphRAG Multi-Hop Causal Reasoning.
"""

from core.structures.community import LouvainCommunityDetector

from .engine import PropertyGraphEngine
from .graphrag import GraphRAGPipeline
from .query_dsl import GraphQueryDSLParser, execute_dsl_query
from .structures import Edge, Path, Vertex
from .traversal import (
    GraphTraversal,
    detect_threat_communities,
    find_connected_threat_clusters,
)

__all__ = [
    "Vertex",
    "Edge",
    "Path",
    "PropertyGraphEngine",
    "GraphTraversal",
    "GraphRAGPipeline",
    "find_connected_threat_clusters",
    "detect_threat_communities",
    "LouvainCommunityDetector",
    "GraphQueryDSLParser",
    "execute_dsl_query",
]
