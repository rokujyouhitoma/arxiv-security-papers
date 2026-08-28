#!/usr/bin/env python3
"""
Property Graph Database Engine.
Non-invasive graph database engine built on top of storage foundations.
Provides high-speed Dual CSR (Compressed Sparse Row) adjacency indexing
with zero modifications to existing src/database/ core.
"""

from __future__ import annotations

import json
import logging
import os
from typing import TYPE_CHECKING, Any, Dict, List, Optional

from .structures import Edge, Vertex

if TYPE_CHECKING:
    from .traversal import GraphTraversal

logger = logging.getLogger(__name__)


class PropertyGraphEngine:
    """
    High-performance pure Python Property Graph Database Engine.
    Maintains forward and reverse adjacency indices for O(1) multi-hop neighborhood lookups.
    """

    def __init__(
        self,
        storage_path: Optional[str] = None,
        workspace_dir: Optional[str] = None,
        memory_only: bool = False,
    ) -> None:
        self.workspace_dir = workspace_dir or os.path.abspath(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        )
        self.storage_path = storage_path or os.path.join(
            self.workspace_dir, "outputs", "database", "graph.db"
        )
        self.memory_only = memory_only

        # Primary Storage: Vertices by ID
        self._vertices: Dict[str, Vertex] = {}
        # Forward Adjacency: src_id -> List[Edge]
        self._out_edges: Dict[str, List[Edge]] = {}
        # Reverse Adjacency: dst_id -> List[Edge]
        self._in_edges: Dict[str, List[Edge]] = {}
        # Edge Index: edge_id -> Edge
        self._edges: Dict[str, Edge] = {}

        if not self.memory_only and os.path.exists(self.storage_path):
            self.load()

    def add_vertex(
        self,
        vertex_id: str,
        label: str = "Vertex",
        properties: Optional[Dict[str, Any]] = None,
    ) -> Vertex:
        """Adds or updates a vertex in the graph."""
        if vertex_id in self._vertices:
            v = self._vertices[vertex_id]
            v.label = label
            if properties:
                v.properties.update(properties)
            return v

        v = Vertex(id=vertex_id, label=label, properties=properties or {})
        self._vertices[vertex_id] = v
        self._out_edges.setdefault(vertex_id, [])
        self._in_edges.setdefault(vertex_id, [])
        return v

    def add_edge(
        self,
        src_id: str,
        dst_id: str,
        label: str = "RELATED",
        weight: float = 1.0,
        properties: Optional[Dict[str, Any]] = None,
    ) -> Edge:
        """Adds a directed edge between two vertices (auto-creates vertices if missing)."""
        if src_id not in self._vertices:
            self.add_vertex(src_id)
        if dst_id not in self._vertices:
            self.add_vertex(dst_id)

        edge = Edge(
            src_id=src_id,
            dst_id=dst_id,
            label=label,
            weight=weight,
            properties=properties or {},
        )

        edge_id = edge.id
        self._edges[edge_id] = edge

        # Update Forward Index
        out_list = self._out_edges.setdefault(src_id, [])
        out_list = [e for e in out_list if e.id != edge_id]
        out_list.append(edge)
        self._out_edges[src_id] = out_list

        # Update Reverse Index
        in_list = self._in_edges.setdefault(dst_id, [])
        in_list = [e for e in in_list if e.id != edge_id]
        in_list.append(edge)
        self._in_edges[dst_id] = in_list

        return edge

    def get_vertex(self, vertex_id: str) -> Optional[Vertex]:
        """Retrieves vertex by ID in O(1) time."""
        return self._vertices.get(vertex_id)

    def get_edge(self, edge_id: str) -> Optional[Edge]:
        """Retrieves edge by ID in O(1) time."""
        return self._edges.get(edge_id)

    def get_out_edges(self, vertex_id: str, *labels: str) -> List[Edge]:
        """Retrieves outgoing edges from vertex_id, optionally filtered by edge labels."""
        edges = self._out_edges.get(vertex_id, [])
        if not labels:
            return list(edges)
        target_labels = set(labels)
        return [e for e in edges if e.label in target_labels]

    def get_in_edges(self, vertex_id: str, *labels: str) -> List[Edge]:
        """Retrieves incoming edges to vertex_id, optionally filtered by edge labels."""
        edges = self._in_edges.get(vertex_id, [])
        if not labels:
            return list(edges)
        target_labels = set(labels)
        return [e for e in edges if e.label in target_labels]

    def get_both_edges(self, vertex_id: str, *labels: str) -> List[Edge]:
        """Retrieves all edges (in + out) connected to vertex_id."""
        return self.get_out_edges(vertex_id, *labels) + self.get_in_edges(
            vertex_id, *labels
        )

    def remove_vertex(self, vertex_id: str) -> bool:
        """Removes a vertex and all incident edges."""
        if vertex_id not in self._vertices:
            return False

        # Remove out edges
        for edge in list(self._out_edges.get(vertex_id, [])):
            self._edges.pop(edge.id, None)
            if edge.dst_id in self._in_edges:
                self._in_edges[edge.dst_id] = [
                    e for e in self._in_edges[edge.dst_id] if e.id != edge.id
                ]

        # Remove in edges
        for edge in list(self._in_edges.get(vertex_id, [])):
            self._edges.pop(edge.id, None)
            if edge.src_id in self._out_edges:
                self._out_edges[edge.src_id] = [
                    e for e in self._out_edges[edge.src_id] if e.id != edge.id
                ]

        self._out_edges.pop(vertex_id, None)
        self._in_edges.pop(vertex_id, None)
        self._vertices.pop(vertex_id, None)
        return True

    def V(self, *vertex_ids: str) -> "GraphTraversal":
        """Spawns an Apache TinkerPop Gremlin-compatible GraphTraversal starting at vertices."""
        from .traversal import GraphTraversal

        traversal = GraphTraversal(engine=self)
        return traversal.V(*vertex_ids)

    def E(self, *edge_ids: str) -> "GraphTraversal":
        """Spawns an Apache TinkerPop Gremlin-compatible GraphTraversal starting at edges."""
        from .traversal import GraphTraversal

        traversal = GraphTraversal(engine=self)
        return traversal.E(*edge_ids)

    @property
    def vertex_count(self) -> int:
        return len(self._vertices)

    @property
    def edge_count(self) -> int:
        return len(self._edges)

    def stats(self) -> Dict[str, Any]:
        """Returns topological statistics of the graph."""
        label_counts: Dict[str, int] = {}
        for v in self._vertices.values():
            label_counts[v.label] = label_counts.get(v.label, 0) + 1

        predicate_counts: Dict[str, int] = {}
        for e in self._edges.values():
            predicate_counts[e.label] = predicate_counts.get(e.label, 0) + 1

        return {
            "vertex_count": len(self._vertices),
            "edge_count": len(self._edges),
            "vertex_labels": label_counts,
            "edge_predicates": predicate_counts,
        }

    def save(self, filepath: Optional[str] = None) -> None:
        """Persists the graph to disk in compact JSON format."""
        target_path = filepath or self.storage_path
        os.makedirs(os.path.dirname(target_path), exist_ok=True)

        payload = {
            "version": "1.0",
            "vertices": [v.to_dict() for v in self._vertices.values()],
            "edges": [e.to_dict() for e in self._edges.values()],
        }

        temp_path = f"{target_path}.tmp"
        with open(temp_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        os.replace(temp_path, target_path)
        logger.info(
            "Saved PropertyGraphEngine (%d vertices, %d edges) to %s",
            len(self._vertices),
            len(self._edges),
            target_path,
        )

    def load(self, filepath: Optional[str] = None) -> None:
        """Loads graph from persistent disk storage."""
        target_path = filepath or self.storage_path
        if not os.path.exists(target_path):
            return

        try:
            with open(target_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self._vertices.clear()
            self._edges.clear()
            self._out_edges.clear()
            self._in_edges.clear()

            for vd in data.get("vertices", []):
                v = Vertex(
                    id=vd["id"],
                    label=vd.get("label", "Vertex"),
                    properties=vd.get("properties", {}),
                )
                self._vertices[v.id] = v
                self._out_edges[v.id] = []
                self._in_edges[v.id] = []

            for ed in data.get("edges", []):
                edge = Edge(
                    src_id=ed["src_id"],
                    dst_id=ed["dst_id"],
                    label=ed.get("label", "RELATED"),
                    weight=float(ed.get("weight", 1.0)),
                    properties=ed.get("properties", {}),
                )
                self._edges[edge.id] = edge
                self._out_edges.setdefault(edge.src_id, []).append(edge)
                self._in_edges.setdefault(edge.dst_id, []).append(edge)

            logger.info(
                "Loaded PropertyGraphEngine (%d vertices, %d edges) from %s",
                len(self._vertices),
                len(self._edges),
                target_path,
            )
        except Exception as ex:
            logger.error("Failed to load graph from %s: %s", target_path, ex)

    def clear(self) -> None:
        """Clears all in-memory vertices and edges."""
        self._vertices.clear()
        self._edges.clear()
        self._out_edges.clear()
        self._in_edges.clear()
