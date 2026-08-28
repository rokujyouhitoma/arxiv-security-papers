#!/usr/bin/env python3
"""
Property Graph Database Engine Package.
Non-invasive graph engine providing Apache TinkerPop Gremlin-compatible Fluent Traversal,
Dual CSR Adjacency Indexing, and GraphRAG Multi-Hop Causal Reasoning.
"""

from .engine import PropertyGraphEngine
from .graphrag import GraphRAGPipeline
from .structures import Edge, Path, Vertex
from .traversal import GraphTraversal

__all__ = [
    "Vertex",
    "Edge",
    "Path",
    "PropertyGraphEngine",
    "GraphTraversal",
    "GraphRAGPipeline",
]
