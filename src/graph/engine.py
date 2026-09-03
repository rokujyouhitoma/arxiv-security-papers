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
from typing import TYPE_CHECKING, Any, Dict, List, Optional, Tuple

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

    def _update_edge_indices(self, edge: Edge) -> None:
        """Updates forward and reverse edge index maps."""
        out_list = self._out_edges.setdefault(edge.src_id, [])
        out_list = [e for e in out_list if e.id != edge.id]
        out_list.append(edge)
        self._out_edges[edge.src_id] = out_list

        in_list = self._in_edges.setdefault(edge.dst_id, [])
        in_list = [e for e in in_list if e.id != edge.id]
        in_list.append(edge)
        self._in_edges[edge.dst_id] = in_list

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
        self._edges[edge.id] = edge
        self._update_edge_indices(edge)
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

    def _purge_out_edges(self, vertex_id: str) -> None:
        """Purges outgoing edges connected to vertex_id."""
        for edge in list(self._out_edges.get(vertex_id, [])):
            self._edges.pop(edge.id, None)
            if edge.dst_id in self._in_edges:
                self._in_edges[edge.dst_id] = [
                    e for e in self._in_edges[edge.dst_id] if e.id != edge.id
                ]
        self._out_edges.pop(vertex_id, None)

    def _purge_in_edges(self, vertex_id: str) -> None:
        """Purges incoming edges connected to vertex_id."""
        for edge in list(self._in_edges.get(vertex_id, [])):
            self._edges.pop(edge.id, None)
            if edge.src_id in self._out_edges:
                self._out_edges[edge.src_id] = [
                    e for e in self._out_edges[edge.src_id] if e.id != edge.id
                ]
        self._in_edges.pop(vertex_id, None)

    def remove_vertex(self, vertex_id: str) -> bool:
        """Removes a vertex and all incident edges."""
        if vertex_id not in self._vertices:
            return False

        self._purge_out_edges(vertex_id)
        self._purge_in_edges(vertex_id)
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

    def _load_data(self, data: Dict[str, Any]) -> None:
        """Populates graph from parsed dictionary payload."""
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

    def load(self, filepath: Optional[str] = None) -> None:
        """Loads graph from persistent disk storage."""
        target_path = filepath or self.storage_path
        if not os.path.exists(target_path):
            return

        try:
            with open(target_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.clear()
            self._load_data(data)

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

    def get_vertices_by_label(self, label: str) -> List[Vertex]:
        """Retrieves all vertices matching a specific label."""
        return [v for v in self._vertices.values() if v.label == label]

    def _normalize_entity_id(self, raw_id: str) -> str:
        """Resolves raw entity ID to internal vertex key."""
        if raw_id in self._vertices:
            return raw_id
        for prefix in ("Vulnerability:", "AttackTechnique:", "Paper:"):
            cand = f"{prefix}{raw_id}"
            if cand in self._vertices:
                return cand
        return raw_id

    def _has_paper_link(self, vertex_id: str) -> bool:
        """Checks if a vertex is connected to at least one Paper node."""
        for edge in self.get_both_edges(vertex_id):
            nbr_id = edge.dst_id if edge.src_id == vertex_id else edge.src_id
            nbr = self._vertices.get(nbr_id)
            if nbr and nbr.label in ("Paper", "Entity:Paper"):
                return True
        return False

    def get_research_gaps(self) -> List[Dict[str, Any]]:
        """Identifies ATT&CK techniques and CWEs with zero connected papers."""
        gaps: List[Dict[str, Any]] = []
        target_labels = {"AttackTechnique", "Vulnerability", "CWE"}
        for v in self._vertices.values():
            if v.label in target_labels and not self._has_paper_link(v.id):
                gaps.append(
                    {
                        "id": v.id,
                        "label": v.label,
                        "name": v.properties.get("name", v.id),
                        "tactic": v.properties.get("tactic", ""),
                        "abstraction": v.properties.get("abstraction", ""),
                        "url": v.properties.get("url", ""),
                    }
                )
        return gaps

    def _collect_impact_from_techniques(
        self, root_id: str, max_depth: int
    ) -> Tuple[Dict[str, Vertex], Dict[str, Vertex], List[List[str]]]:
        """Collects attacking techniques and associated analyzing papers."""
        techniques: Dict[str, Vertex] = {}
        papers: Dict[str, Vertex] = {}
        paths: List[List[str]] = []

        for in_edge in self.get_in_edges(root_id, "EXPLOITS", "LEVERAGES"):
            src_node = self._vertices.get(in_edge.src_id)
            if not src_node or src_node.label != "AttackTechnique":
                continue
            techniques[src_node.id] = src_node
            paths.append([src_node.id, in_edge.label, root_id])

            if max_depth >= 2:
                self._collect_technique_papers(src_node.id, papers, paths)

        return techniques, papers, paths

    def _collect_technique_papers(
        self, tech_id: str, papers: Dict[str, Vertex], paths: List[List[str]]
    ) -> None:
        """Finds papers analyzing or exploiting a technique."""
        for p_edge in self.get_in_edges(tech_id, "EXPLOITS", "ANALYZES"):
            p_node = self._vertices.get(p_edge.src_id)
            if p_node and p_node.label in ("Paper", "Entity:Paper"):
                papers[p_node.id] = p_node
                paths.append([p_node.id, p_edge.label, tech_id])

    def _collect_direct_cwe_papers(
        self, root_id: str, papers: Dict[str, Vertex], paths: List[List[str]]
    ) -> None:
        """Finds papers directly disclosing this CWE."""
        for p_edge in self.get_in_edges(root_id, "DISCLOSES"):
            p_node = self._vertices.get(p_edge.src_id)
            if p_node and p_node.label in ("Paper", "Entity:Paper"):
                papers[p_node.id] = p_node
                paths.append([p_node.id, p_edge.label, root_id])

    def get_cwe_impact(self, cwe_id: str, max_depth: int = 2) -> Dict[str, Any]:
        """Performs multi-hop impact analysis starting from a CWE vulnerability."""
        root_id = self._normalize_entity_id(cwe_id)
        root_vertex = self._vertices.get(root_id)
        if not root_vertex:
            return {"cwe": None, "techniques": [], "papers": [], "paths": []}

        techniques, papers, paths = self._collect_impact_from_techniques(
            root_id, max_depth
        )
        self._collect_direct_cwe_papers(root_id, papers, paths)

        return {
            "cwe": root_vertex.to_dict(),
            "techniques": [t.to_dict() for t in techniques.values()],
            "papers": [p.to_dict() for p in papers.values()],
            "paths": paths,
        }

    def _record_neighbor(
        self,
        edge: Edge,
        curr_id: str,
        visited_nodes: Dict[str, Vertex],
        visited_edges: Dict[str, Edge],
        next_frontier: set[str],
        limit: int,
    ) -> bool:
        """Records an edge and neighbor node if not yet visited."""
        visited_edges[edge.id] = edge
        nbr_id = edge.dst_id if edge.src_id == curr_id else edge.src_id
        if nbr_id not in visited_nodes and nbr_id in self._vertices:
            visited_nodes[nbr_id] = self._vertices[nbr_id]
            next_frontier.add(nbr_id)
        return len(visited_nodes) >= limit

    def _expand_neighborhood_step(
        self,
        frontier: set[str],
        visited_nodes: Dict[str, Vertex],
        visited_edges: Dict[str, Edge],
        limit: int,
    ) -> set[str]:
        """Expands graph frontier by 1 hop while respecting limit."""
        next_frontier: set[str] = set()
        for curr_id in frontier:
            for edge in self.get_both_edges(curr_id):
                if self._record_neighbor(
                    edge, curr_id, visited_nodes, visited_edges, next_frontier, limit
                ):
                    return next_frontier
        return next_frontier

    def _run_bfs_expansion(
        self, norm_id: str, max_hops: int, limit: int
    ) -> Tuple[Dict[str, Vertex], Dict[str, Edge]]:
        """Runs breadth-first search for k-hop neighborhood."""
        visited_nodes: Dict[str, Vertex] = {norm_id: self._vertices[norm_id]}
        visited_edges: Dict[str, Edge] = {}
        frontier = {norm_id}

        for _ in range(max_hops):
            frontier = self._expand_neighborhood_step(
                frontier, visited_nodes, visited_edges, limit
            )
            if not frontier or len(visited_nodes) >= limit:
                break
        return visited_nodes, visited_edges

    def get_neighborhood(
        self, vertex_id: str, max_hops: int = 2, limit: int = 150
    ) -> Dict[str, Any]:
        """Retrieves k-hop ego network for interactive expansion."""
        norm_id = self._normalize_entity_id(vertex_id)
        if norm_id not in self._vertices:
            return {"nodes": [], "edges": []}

        visited_nodes, visited_edges = self._run_bfs_expansion(norm_id, max_hops, limit)
        return {
            "nodes": [v.to_dict() for v in visited_nodes.values()],
            "edges": [e.to_dict() for e in visited_edges.values()],
        }

    def _format_cti_node(self, v: Vertex, gap_ids: set[str]) -> Dict[str, Any]:
        """Formats vertex into a standard CTI node dictionary with visual tokens."""
        is_gap = v.id in gap_ids
        color_map = {
            "Paper": "#3B82F6",
            "Entity:Paper": "#3B82F6",
            "AttackTechnique": "#EF4444",
            "Vulnerability": "#F59E0B",
            "CWE": "#F59E0B",
            "DefenseMechanism": "#10B981",
        }
        radius_map = {
            "Paper": 7,
            "Entity:Paper": 7,
            "AttackTechnique": 9,
            "Vulnerability": 8,
            "CWE": 8,
            "DefenseMechanism": 8,
        }
        clean_name = v.properties.get("name") or v.properties.get("title") or v.id
        return {
            "id": v.id,
            "label": v.label,
            "name": clean_name,
            "category": v.properties.get("category", v.properties.get("tactic", "")),
            "description": v.properties.get("description", ""),
            "url": v.properties.get("url", ""),
            "color": color_map.get(v.label, "#9CA3AF"),
            "radius": radius_map.get(v.label, 8),
            "is_research_gap": is_gap,
            "properties": v.properties,
        }

    def _resolve_focused_subgraph(
        self, focus_node: str, limit: int
    ) -> Tuple[List[Vertex], List[Edge]]:
        """Resolves neighborhood vertices and edges for a focused node."""
        sub = self.get_neighborhood(focus_node, max_hops=2, limit=limit)
        nodes = [
            self._vertices[d["id"]] for d in sub["nodes"] if d["id"] in self._vertices
        ]
        edges = [self._edges[d["id"]] for d in sub["edges"] if d["id"] in self._edges]
        return nodes, edges

    def _resolve_global_subgraph(self, limit: int) -> Tuple[List[Vertex], List[Edge]]:
        """Resolves global vertices and incident edges up to limit."""
        nodes = list(self._vertices.values())[:limit]
        node_id_set = {n.id for n in nodes}
        edges = [
            e
            for e in self._edges.values()
            if e.src_id in node_id_set and e.dst_id in node_id_set
        ]
        return nodes, edges

    def _resolve_subgraph_nodes_and_edges(
        self, limit: int, focus_node: Optional[str]
    ) -> Tuple[List[Vertex], List[Edge]]:
        """Resolves raw vertices and edges based on focus node or global limit."""
        if focus_node:
            return self._resolve_focused_subgraph(focus_node, limit)
        return self._resolve_global_subgraph(limit)

    def _compute_cti_counts(self, gap_count: int) -> Dict[str, int]:
        """Computes summary statistics for CTI entity counts."""
        paper_cnt = len(self.get_vertices_by_label("Paper")) + len(
            self.get_vertices_by_label("Entity:Paper")
        )
        tech_cnt = len(self.get_vertices_by_label("AttackTechnique"))
        cwe_cnt = len(self.get_vertices_by_label("Vulnerability")) + len(
            self.get_vertices_by_label("CWE")
        )
        return {
            "total_papers": paper_cnt,
            "total_techniques": tech_cnt,
            "total_cwes": cwe_cnt,
            "research_gap_count": gap_count,
        }

    def export_cti_subgraph(
        self,
        limit: int = 200,
        focus_node: Optional[str] = None,
        include_gaps: bool = True,
    ) -> Dict[str, Any]:
        """Exports CTI knowledge graph formatted for /dashboard Canvas 2D visualization."""
        nodes_raw, edges_raw = self._resolve_subgraph_nodes_and_edges(limit, focus_node)
        gaps = self.get_research_gaps() if include_gaps else []
        gap_id_set = {g["id"] for g in gaps}

        nodes = [self._format_cti_node(v, gap_id_set) for v in nodes_raw]
        edges = [
            {
                "source": e.src_id,
                "target": e.dst_id,
                "label": e.label,
                "weight": e.weight,
                "confidence": e.properties.get("confidence", 1.0),
                "tier": e.properties.get("tier", "gold"),
            }
            for e in edges_raw
        ]

        return {
            "nodes": nodes,
            "edges": edges,
            "stats": self._compute_cti_counts(len(gap_id_set)),
            "research_gaps": gaps,
        }
