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
from typing import TYPE_CHECKING, Any, Dict, Iterable, List, Optional, Set, Tuple

from database.sql.executor import SQLExecutor, TableCatalog
from database.storage.storage import VectorStorage

from .structures import Edge, Vertex

if TYPE_CHECKING:
    from .traversal import GraphTraversal

logger = logging.getLogger(__name__)


def _determine_graph_storage_path(
    workspace_dir: str, explicit_path: Optional[str]
) -> str:
    if explicit_path:
        return explicit_path
    return os.path.join(workspace_dir, "outputs", "database")


def _is_file_like_path(path_str: str) -> bool:
    return any(path_str.endswith(ext) for ext in (".vdb", ".db", ".sqlite"))


def _resolve_vdb_paths(
    workspace_dir: str, explicit_path: Optional[str]
) -> Tuple[str, str]:
    if explicit_path in (":memory:", ""):
        return ":memory:", ":memory:"
    if explicit_path:
        if _is_file_like_path(explicit_path):
            base = os.path.splitext(explicit_path)[0]
            return f"{base}_vertices.vdb", f"{base}_edges.vdb"
        return (
            os.path.join(explicit_path, "vertices.vdb"),
            os.path.join(explicit_path, "edges.vdb"),
        )
    db_dir = os.path.join(workspace_dir, "outputs", "database")
    return (
        os.path.join(db_dir, "vertices.vdb"),
        os.path.join(db_dir, "edges.vdb"),
    )


TIER_SEVERITY: Dict[str, int] = {
    "LOW": 1,
    "MEDIUM": 2,
    "HIGH": 3,
}


def _matches_confidence(
    edge: Edge,
    min_conf: Optional[float],
    min_tier: Optional[str],
) -> bool:
    """Evaluates edge confidence score and tier constraints."""
    if min_conf is not None and edge.get_confidence() < min_conf:
        return False
    if min_tier is not None:
        req = TIER_SEVERITY.get(min_tier.upper(), 1)
        actual = TIER_SEVERITY.get(edge.get_confidence_tier().upper(), 1)
        if actual < req:
            return False
    return True


def _matches_allowed_rules(edge: Edge, allowed_rules: Optional[List[str]]) -> bool:
    """Evaluates rule ID constraints."""
    if allowed_rules is None:
        return True
    return any(edge.has_rule(r) for r in allowed_rules)


def _matches_allowed_mechanisms(
    edge: Edge, allowed_mechanisms: Optional[List[str]]
) -> bool:
    """Evaluates mechanism constraints."""
    if allowed_mechanisms is None:
        return True
    mech = str(edge.properties.get("inference_mechanism", ""))
    return mech in allowed_mechanisms


def _matches_target_label(edge: Edge, target_labels: Optional[Set[str]]) -> bool:
    """Checks if edge label matches target labels."""
    if not target_labels:
        return True
    return edge.label in target_labels


def _matches_rules_and_mechanisms(
    edge: Edge,
    allowed_rules: Optional[List[str]],
    allowed_mechanisms: Optional[List[str]],
) -> bool:
    """Combines rule ID and mechanism checks."""
    if not _matches_allowed_rules(edge, allowed_rules):
        return False
    return _matches_allowed_mechanisms(edge, allowed_mechanisms)


def _filter_edge(
    edge: Edge,
    target_labels: Optional[Set[str]],
    min_conf: Optional[float],
    min_tier: Optional[str],
    allowed_rules: Optional[List[str]],
    allowed_mechanisms: Optional[List[str]],
) -> bool:
    """Checks all edge criteria including labels, confidence, and rule metadata."""
    if not _matches_target_label(edge, target_labels):
        return False
    if not _matches_confidence(edge, min_conf, min_tier):
        return False
    return _matches_rules_and_mechanisms(edge, allowed_rules, allowed_mechanisms)


def _serialize_vertices(vertices: Dict[str, Vertex]) -> List[Dict[str, Any]]:
    """Serializes in-memory vertices into VectorStorage metadata dictionaries."""
    res: List[Dict[str, Any]] = []
    for v in vertices.values():
        rec = {
            "id": v.id,
            "label": v.label,
            "name": str(v.properties.get("name") or v.id),
            "properties": json.dumps(v.properties, ensure_ascii=False),
        }
        res.append(rec)
    return res


def _serialize_edges(edges: Dict[str, Edge]) -> List[Dict[str, Any]]:
    """Serializes in-memory edges into VectorStorage metadata dictionaries."""
    res: List[Dict[str, Any]] = []
    for e in edges.values():
        rec = {
            "id": e.id,
            "src_id": e.src_id,
            "dst_id": e.dst_id,
            "label": e.label,
            "confidence": e.get_confidence(),
            "weight": float(e.weight),
            "properties": json.dumps(e.properties, ensure_ascii=False),
        }
        res.append(rec)
    return res


def _decode_json_properties(raw_p: Any) -> Dict[str, Any]:
    if not raw_p:
        return {}
    try:
        loaded = json.loads(str(raw_p)) if isinstance(raw_p, str) else raw_p
        return loaded if isinstance(loaded, dict) else {}
    except (ValueError, TypeError):
        return {}


def _populate_vertices(
    v_meta: List[Dict[str, Any]],
    vertices: Dict[str, Vertex],
    out_edges: Dict[str, List[Edge]],
    in_edges: Dict[str, List[Edge]],
) -> None:
    for rec in v_meta:
        props = _decode_json_properties(rec.get("properties"))
        name = rec.get("name")
        if name and "name" not in props:
            props["name"] = name
        v = Vertex(
            id=str(rec.get("id", "")),
            label=str(rec.get("label", "Vertex")),
            properties=props,
        )
        vertices[v.id] = v
        out_edges.setdefault(v.id, [])
        in_edges.setdefault(v.id, [])


def _populate_edges(
    e_meta: List[Dict[str, Any]],
    edges: Dict[str, Edge],
    out_edges: Dict[str, List[Edge]],
    in_edges: Dict[str, List[Edge]],
) -> None:
    for rec in e_meta:
        props = _decode_json_properties(rec.get("properties"))
        conf = float(rec.get("confidence", 1.0))
        if "confidence" not in props:
            props["confidence"] = conf
        e = Edge(
            src_id=str(rec.get("src_id", "")),
            dst_id=str(rec.get("dst_id", "")),
            label=str(rec.get("label", "RELATED")),
            weight=float(rec.get("weight", 1.0)),
            properties=props,
        )
        edges[e.id] = e
        out_edges.setdefault(e.src_id, []).append(e)
        in_edges.setdefault(e.dst_id, []).append(e)


def _populate_from_metadata(
    v_meta: List[Dict[str, Any]],
    e_meta: List[Dict[str, Any]],
    vertices: Dict[str, Vertex],
    edges: Dict[str, Edge],
    out_edges: Dict[str, List[Edge]],
    in_edges: Dict[str, List[Edge]],
) -> None:
    """Populates graph data structures from VectorStorage metadata."""
    _populate_vertices(v_meta, vertices, out_edges, in_edges)
    _populate_edges(e_meta, edges, out_edges, in_edges)


def _save_to_custom_vdb(
    workspace_dir: str,
    filepath: str,
    v_meta: List[Dict[str, Any]],
    e_meta: List[Dict[str, Any]],
) -> None:
    v_p, e_p = _resolve_vdb_paths(workspace_dir, filepath)
    os.makedirs(os.path.dirname(os.path.abspath(v_p)), exist_ok=True)
    st_v = VectorStorage(file_path=v_p, dim=16)
    st_e = VectorStorage(file_path=e_p, dim=16)
    v_dummy = tuple(0.0 for _ in range(st_v.dim))
    e_dummy = tuple(0.0 for _ in range(st_e.dim))
    st_v.write_all([v_dummy] * len(v_meta), v_meta)
    st_e.write_all([e_dummy] * len(e_meta), e_meta)


def _load_from_custom_vdb(
    workspace_dir: str,
    filepath: str,
    vertices: Dict[str, Vertex],
    edges: Dict[str, Edge],
    out_edges: Dict[str, List[Edge]],
    in_edges: Dict[str, List[Edge]],
) -> None:
    v_p, e_p = _resolve_vdb_paths(workspace_dir, filepath)
    if not os.path.exists(v_p) and not os.path.exists(e_p):
        return
    st_v = VectorStorage(file_path=v_p, dim=128)
    st_e = VectorStorage(file_path=e_p, dim=128)
    _populate_from_metadata(
        st_v.metadata, st_e.metadata, vertices, edges, out_edges, in_edges
    )


def _resolve_workspace_dir(workspace_dir: Optional[str]) -> str:
    if workspace_dir:
        return workspace_dir
    return os.path.abspath(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    )


def _is_memory_mode(memory_only: bool, storage_path: str) -> bool:
    if memory_only:
        return True
    return storage_path in (":memory:", "")


class PropertyGraphEngine:
    """
    High-performance pure Python Property Graph Database Engine.
    Powered directly by src/database/ (VectorStorage & SQLExecutor).
    Maintains forward and reverse adjacency indices for O(1) multi-hop neighborhood lookups.
    """

    def __init__(
        self,
        storage_path: Optional[str] = None,
        workspace_dir: Optional[str] = None,
        memory_only: bool = False,
    ) -> None:
        self.workspace_dir = _resolve_workspace_dir(workspace_dir)
        self.storage_path = _determine_graph_storage_path(
            self.workspace_dir, storage_path
        )
        self.memory_only = _is_memory_mode(memory_only, self.storage_path)
        self.v_path, self.e_path = _resolve_vdb_paths(
            self.workspace_dir, ":memory:" if self.memory_only else storage_path
        )

        # Primary Storage: Vertices by ID
        self._vertices: Dict[str, Vertex] = {}
        # Forward Adjacency: src_id -> List[Edge]
        self._out_edges: Dict[str, List[Edge]] = {}
        # Reverse Adjacency: dst_id -> List[Edge]
        self._in_edges: Dict[str, List[Edge]] = {}
        # Edge Index: edge_id -> Edge
        self._edges: Dict[str, Edge] = {}

        self._init_storage()
        self._maybe_load_existing_data()

    def _maybe_load_existing_data(self) -> None:
        if self.memory_only:
            return
        if os.path.exists(self.v_path) or os.path.exists(self.e_path):
            self.load()

    def _init_storage(self) -> None:
        """Initializes pure VectorStorage engines and SQLExecutor catalogs."""
        dim = 16
        if not self.memory_only:
            os.makedirs(os.path.dirname(os.path.abspath(self.v_path)), exist_ok=True)
            os.makedirs(os.path.dirname(os.path.abspath(self.e_path)), exist_ok=True)
        self.v_storage = VectorStorage(file_path=self.v_path, dim=dim)
        self.e_storage = VectorStorage(file_path=self.e_path, dim=dim)
        self.executor = SQLExecutor()
        self.executor.tables["vertices"] = TableCatalog(
            name="vertices", storage=self.v_storage
        )
        self.executor.tables["edges"] = TableCatalog(
            name="edges", storage=self.e_storage
        )

    def execute_sql(self, sql: str, role: Optional[str] = None) -> Dict[str, Any]:
        """Executes a SQL query using pure-Python SQLExecutor."""
        return self.executor.execute(sql, role=role)

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

    def get_out_edges(
        self,
        vertex_id: str,
        *labels: str,
        min_confidence: Optional[float] = None,
        min_tier: Optional[str] = None,
        allowed_rules: Optional[List[str]] = None,
        allowed_mechanisms: Optional[List[str]] = None,
    ) -> List[Edge]:
        """Retrieves outgoing edges from vertex_id with optional label, confidence, and rule filtering."""
        edges = self._out_edges.get(vertex_id, [])
        target_labels = set(labels) if labels else None
        return [
            e
            for e in edges
            if _filter_edge(
                e,
                target_labels,
                min_confidence,
                min_tier,
                allowed_rules,
                allowed_mechanisms,
            )
        ]

    def get_outgoing_edges(
        self,
        vertex_id: str,
        *labels: str,
        min_confidence: Optional[float] = None,
        min_tier: Optional[str] = None,
        allowed_rules: Optional[List[str]] = None,
        allowed_mechanisms: Optional[List[str]] = None,
    ) -> List[Edge]:
        """Alias for get_out_edges."""
        return self.get_out_edges(
            vertex_id,
            *labels,
            min_confidence=min_confidence,
            min_tier=min_tier,
            allowed_rules=allowed_rules,
            allowed_mechanisms=allowed_mechanisms,
        )

    def get_in_edges(
        self,
        vertex_id: str,
        *labels: str,
        min_confidence: Optional[float] = None,
        min_tier: Optional[str] = None,
        allowed_rules: Optional[List[str]] = None,
        allowed_mechanisms: Optional[List[str]] = None,
    ) -> List[Edge]:
        """Retrieves incoming edges to vertex_id with optional label, confidence, and rule filtering."""
        edges = self._in_edges.get(vertex_id, [])
        target_labels = set(labels) if labels else None
        return [
            e
            for e in edges
            if _filter_edge(
                e,
                target_labels,
                min_confidence,
                min_tier,
                allowed_rules,
                allowed_mechanisms,
            )
        ]

    def get_incoming_edges(
        self,
        vertex_id: str,
        *labels: str,
        min_confidence: Optional[float] = None,
        min_tier: Optional[str] = None,
        allowed_rules: Optional[List[str]] = None,
        allowed_mechanisms: Optional[List[str]] = None,
    ) -> List[Edge]:
        """Alias for get_in_edges."""
        return self.get_in_edges(
            vertex_id,
            *labels,
            min_confidence=min_confidence,
            min_tier=min_tier,
            allowed_rules=allowed_rules,
            allowed_mechanisms=allowed_mechanisms,
        )

    def get_both_edges(
        self,
        vertex_id: str,
        *labels: str,
        min_confidence: Optional[float] = None,
        min_tier: Optional[str] = None,
        allowed_rules: Optional[List[str]] = None,
        allowed_mechanisms: Optional[List[str]] = None,
    ) -> List[Edge]:
        """Retrieves all edges (in + out) connected to vertex_id with optional filtering."""
        out_e = self.get_out_edges(
            vertex_id,
            *labels,
            min_confidence=min_confidence,
            min_tier=min_tier,
            allowed_rules=allowed_rules,
            allowed_mechanisms=allowed_mechanisms,
        )
        in_e = self.get_in_edges(
            vertex_id,
            *labels,
            min_confidence=min_confidence,
            min_tier=min_tier,
            allowed_rules=allowed_rules,
            allowed_mechanisms=allowed_mechanisms,
        )
        return out_e + in_e

    def get_all_vertices(self) -> List[Vertex]:
        """Returns all vertices currently registered in the graph engine."""
        return list(self._vertices.values())

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

    def _write_default_storage(
        self, v_meta: List[Dict[str, Any]], e_meta: List[Dict[str, Any]]
    ) -> None:
        v_dummy = tuple(0.0 for _ in range(self.v_storage.dim))
        e_dummy = tuple(0.0 for _ in range(self.e_storage.dim))
        self.v_storage.write_all([v_dummy] * len(v_meta), v_meta)
        self.e_storage.write_all([e_dummy] * len(e_meta), e_meta)
        self.executor.tables["vertices"].recompute_stats()
        self.executor.tables["edges"].recompute_stats()

    def save(self, filepath: Optional[str] = None) -> None:
        """Persists vertices and edges into VectorStorage."""
        v_meta = _serialize_vertices(self._vertices)
        e_meta = _serialize_edges(self._edges)
        if filepath and filepath != self.storage_path:
            _save_to_custom_vdb(self.workspace_dir, filepath, v_meta, e_meta)
        else:
            self._write_default_storage(v_meta, e_meta)

        logger.info(
            "Saved PropertyGraphEngine (%d vertices, %d edges)",
            len(self._vertices),
            len(self._edges),
        )

    def load(self, filepath: Optional[str] = None) -> None:
        """Loads graph from VectorStorage."""
        target_path = filepath or self.storage_path
        self.clear()
        if filepath and filepath != self.storage_path:
            _load_from_custom_vdb(
                self.workspace_dir,
                filepath,
                self._vertices,
                self._edges,
                self._out_edges,
                self._in_edges,
            )
        else:
            _populate_from_metadata(
                self.v_storage.metadata,
                self.e_storage.metadata,
                self._vertices,
                self._edges,
                self._out_edges,
                self._in_edges,
            )

        logger.info(
            "Loaded PropertyGraphEngine (%d vertices, %d edges) from %s",
            len(self._vertices),
            len(self._edges),
            target_path,
        )

    def close(self) -> None:
        """Closes underlying VectorStorage resources."""
        pass

    def __enter__(self) -> PropertyGraphEngine:
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.close()

    def __del__(self) -> None:
        self.close()

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
            "DetectionRule": "#10B981",
            "Precondition": "#EAB308",
            "ResearchGap": "#8B5CF6",
            "ResidualRisk": "#EC4899",
            "PoCArtifact": "#06B6D4",
            "PublicationVenue": "#64748B",
            "ThreatActor": "#7F1D1D",
            "Incident": "#B91C1C",
            "Impact": "#DB2777",
            "Claim": "#8B5CF6",
            "EvaluationResult": "#10B981",
        }
        radius_map = {
            "Paper": 7,
            "Entity:Paper": 7,
            "AttackTechnique": 9,
            "Vulnerability": 8,
            "CWE": 8,
            "DefenseMechanism": 8,
            "DetectionRule": 7,
            "Precondition": 6,
            "ResearchGap": 8,
            "ResidualRisk": 8,
            "PoCArtifact": 7,
            "PublicationVenue": 9,
            "ThreatActor": 9,
            "Incident": 8,
            "Impact": 8,
            "Claim": 8,
            "EvaluationResult": 8,
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

    @staticmethod
    def _format_cti_edge(e: Edge) -> Dict[str, Any]:
        """Formats edge into a standard CTI edge dictionary with inference and confidence metadata."""
        return {
            "source": e.src_id,
            "target": e.dst_id,
            "label": e.label,
            "weight": e.weight,
            "confidence": e.get_confidence(default=1.0),
            "confidence_tier": e.get_confidence_tier(),
            "primary_rule_id": e.get_primary_rule() or "",
            "applied_rules": list(e.properties.get("applied_rules", [])),
            "inference_mechanism": str(
                e.properties.get("inference_mechanism", "lexical")
            ),
            "evidences": e.get_evidences(),
            "evidence_quote": str(e.properties.get("evidence_quote", "")),
            "tier": e.properties.get("tier", "gold"),
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
        impact_cnt = len(self.get_vertices_by_label("Impact"))
        claim_cnt = len(self.get_vertices_by_label("Claim"))
        eval_cnt = len(self.get_vertices_by_label("EvaluationResult"))
        incident_cnt = len(self.get_vertices_by_label("Incident"))
        return {
            "total_papers": paper_cnt,
            "total_techniques": tech_cnt,
            "total_cwes": cwe_cnt,
            "total_impacts": impact_cnt,
            "total_claims": claim_cnt,
            "total_evaluations": eval_cnt,
            "total_incidents": incident_cnt,
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
        edges = [self._format_cti_edge(e) for e in edges_raw]

        return {
            "nodes": nodes,
            "edges": edges,
            "stats": self._compute_cti_counts(len(gap_id_set)),
            "research_gaps": gaps,
        }

    def _collect_vertices(self, node_ids: Iterable[str]) -> List[Vertex]:
        """Collects existing vertices for given IDs."""
        nodes: List[Vertex] = []
        for nid in node_ids:
            v = self.get_vertex(nid)
            if v is not None:
                nodes.append(v)
        return nodes

    def _collect_induced_edges(
        self, node_ids: set[str], limit: int = 100
    ) -> List[Edge]:
        """Collects edges with both endpoints within the node set."""
        edges: List[Edge] = []
        for e in self._edges.values():
            if e.src_id in node_ids and e.dst_id in node_ids:
                edges.append(e)
                if len(edges) >= limit:
                    break
        return edges

    def _collect_incident_edges(
        self, node_ids: set[str], limit: int = 100
    ) -> List[Edge]:
        """Collects edges touching at least one node in the node set."""
        edges: List[Edge] = []
        for e in self._edges.values():
            if e.src_id in node_ids or e.dst_id in node_ids:
                edges.append(e)
                if len(edges) >= limit:
                    break
        return edges

    def _record_incident_edge(
        self,
        edge: Edge,
        seed_id: str,
        seen_keys: set[Tuple[str, str, str]],
        collected_edges: List[Edge],
        neighbor_ids: set[str],
    ) -> bool:
        key = (edge.src_id, edge.dst_id, edge.label)
        if key in seen_keys:
            return False
        seen_keys.add(key)
        collected_edges.append(edge)
        neighbor_id = edge.dst_id if edge.src_id == seed_id else edge.src_id
        neighbor_ids.add(neighbor_id)
        return True

    def _collect_seed_incident_edges(
        self,
        seed_id: str,
        seen_keys: set[Tuple[str, str, str]],
        collected_edges: List[Edge],
        neighbor_ids: set[str],
        max_neighbors: int,
        max_edges: int,
    ) -> bool:
        """Collects bounded incident edges for a single seed vertex. Returns True if max_edges reached."""
        count = 0
        for edge in self.get_both_edges(seed_id):
            if len(collected_edges) >= max_edges:
                return True
            if count >= max_neighbors:
                break
            if self._record_incident_edge(
                edge, seed_id, seen_keys, collected_edges, neighbor_ids
            ):
                count += 1
        return False

    @staticmethod
    def _filter_edges_by_nodes(edges: List[Edge], node_ids: set[str]) -> List[Edge]:
        return [e for e in edges if e.src_id in node_ids and e.dst_id in node_ids]

    def _expand_1hop_incident_subgraph(
        self,
        seed_ids: set[str],
        max_edges: int = 150,
        max_neighbors_per_seed: int = 20,
    ) -> Tuple[List[Vertex], List[Edge]]:
        """Expands 1-hop incident edges and neighbor vertices from seed vertices."""
        seen_keys: set[Tuple[str, str, str]] = set()
        collected_edges: List[Edge] = []
        neighbor_ids: set[str] = set()

        for sid in seed_ids:
            if self._collect_seed_incident_edges(
                sid,
                seen_keys,
                collected_edges,
                neighbor_ids,
                max_neighbors_per_seed,
                max_edges,
            ):
                break

        nodes = self._collect_vertices(seed_ids | neighbor_ids)
        node_id_set = {v.id for v in nodes}
        valid_edges = self._filter_edges_by_nodes(collected_edges, node_id_set)
        return nodes, valid_edges

    def _query_gaps(self, limit: int) -> Tuple[List[Vertex], List[Edge], int]:
        """Extracts research gap techniques/CWEs with their direct edges."""
        gaps = self.get_research_gaps()
        gap_ids = {g["id"] for g in gaps[:limit]}
        nodes, edges = self._expand_1hop_incident_subgraph(
            gap_ids, max_edges=min(limit * 3, 200), max_neighbors_per_seed=10
        )
        return nodes, edges, len(gap_ids)

    def _collect_cwe_impact_node_ids(self, impact: Dict[str, Any]) -> set[str]:
        cwe_dict = impact.get("cwe")
        if not cwe_dict:
            return set()
        node_ids = {cwe_dict["id"]}
        for t in impact.get("techniques", []):
            node_ids.add(t["id"])
        for p in impact.get("papers", []):
            node_ids.add(p["id"])
        return node_ids

    def _query_cwe(
        self, raw_cwe: str, limit: int
    ) -> Tuple[List[Vertex], List[Edge], int]:
        """Extracts multi-hop impact subgraph for specified CWE."""
        norm_cwe = raw_cwe.strip().upper()
        cwe_id = norm_cwe if norm_cwe.startswith("CWE-") else f"CWE-{norm_cwe}"
        impact = self.get_cwe_impact(cwe_id)
        node_ids = self._collect_cwe_impact_node_ids(impact)
        nodes = self._collect_vertices(node_ids)
        edges = self._collect_induced_edges(node_ids, limit * 2)
        return nodes, edges, len(nodes)

    def _resolve_ego_node_id(self, target: str) -> Optional[str]:
        """Resolves raw target name or ID to canonical vertex ID."""
        if target in self._vertices:
            return target
        t_low = target.lower()
        for vid in self._vertices:
            if t_low in vid.lower():
                return vid
        return None

    def _parse_ego_target_and_hops(self, raw_arg: str) -> Tuple[str, int]:
        parts = raw_arg.strip().split()
        target = parts[0] if parts else ""
        hops = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 2
        return target, min(hops, 3)

    def _query_ego(
        self, raw_arg: str, limit: int
    ) -> Tuple[List[Vertex], List[Edge], int]:
        """Extracts ego-network neighborhood around target vertex."""
        target, hops = self._parse_ego_target_and_hops(raw_arg)
        resolved_id = self._resolve_ego_node_id(target)
        if not resolved_id:
            return [], [], 0
        sub = self.get_neighborhood(resolved_id, max_hops=hops)
        node_ids = {n["id"] for n in sub.get("nodes", [])[:limit]}
        nodes = self._collect_vertices(node_ids)
        edges = self._collect_induced_edges(node_ids, limit * 2)
        return nodes, edges, 1

    def _is_vertex_match(self, v: Vertex, term_low: str) -> bool:
        if term_low in v.id.lower() or term_low in v.label.lower():
            return True
        name = str(v.properties.get("name", "")).lower()
        if term_low in name:
            return True
        title = str(v.properties.get("title", "")).lower()
        return term_low in title

    def _find_matching_vertex_ids(self, term_low: str, seed_limit: int) -> set[str]:
        matched_ids: set[str] = set()
        for v in self._vertices.values():
            if self._is_vertex_match(v, term_low):
                matched_ids.add(v.id)
                if len(matched_ids) >= seed_limit:
                    break
        return matched_ids

    def _query_match(
        self, term: str, limit: int
    ) -> Tuple[List[Vertex], List[Edge], int]:
        """Matches vertices by ID, label, name, or title keyword and expands 1-hop incident edges."""
        term_low = term.strip().lower()
        if not term_low:
            return [], [], 0
        seed_limit = max(1, int(limit * 0.6))
        matched_ids = self._find_matching_vertex_ids(term_low, seed_limit)
        if not matched_ids:
            return [], [], 0
        nodes, edges = self._expand_1hop_incident_subgraph(
            matched_ids, max_edges=min(limit * 3, 200), max_neighbors_per_seed=20
        )
        return nodes, edges, len(matched_ids)

    def _step_bfs_path(
        self,
        curr: str,
        path: List[str],
        dst: str,
        visited: Set[str],
        queue: List[Tuple[str, List[str]]],
    ) -> Optional[List[str]]:
        for edge in self.get_both_edges(curr):
            neighbor = edge.dst_id if edge.src_id == curr else edge.src_id
            if neighbor == dst:
                return path + [neighbor]
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, path + [neighbor]))
        return None

    def _find_bfs_path(self, src: str, dst: str, max_hops: int = 4) -> List[str]:
        """Finds shortest path of node IDs from src to dst via BFS."""
        if src == dst:
            return [src]
        queue: List[Tuple[str, List[str]]] = [(src, [src])]
        visited: Set[str] = {src}
        while queue:
            curr, path = queue.pop(0)
            if len(path) > max_hops:
                break
            found = self._step_bfs_path(curr, path, dst, visited, queue)
            if found is not None:
                return found
        return []

    def _query_path(self, raw_path: str) -> Tuple[List[Vertex], List[Edge], int]:
        """Finds shortest reaching path between two node expressions via BFS."""
        if "->" not in raw_path:
            return [], [], 0
        parts = raw_path.split("->", 1)
        src = self._resolve_ego_node_id(parts[0].strip())
        dst = self._resolve_ego_node_id(parts[1].strip())
        if not src or not dst:
            return [], [], 0
        path = self._find_bfs_path(src, dst)
        path_set = set(path) if path else {src, dst}
        nodes = self._collect_vertices(path_set)
        edges = self._collect_induced_edges(path_set)
        return nodes, edges, len(nodes)

    CAUSAL_PREDICATES = {
        "HAS_IMPACT",
        "IMPACT_CAUSED_BY",
        "NEUTRALIZES_PRECONDITION",
        "PRECONDITION_NEUTRALIZED_BY",
        "REQUIRES_PRECONDITION",
        "PRECONDITION_FOR",
        "ASSERTS_CLAIM",
        "CLAIM_ASSERTED_BY",
        "EVALUATES_CLAIM",
        "CLAIM_EVALUATED_IN",
        "EVALUATES_TECHNIQUE",
        "TECHNIQUE_EVALUATED_IN",
        "YIELDS_EVALUATION",
        "EVALUATION_YIELDED_BY",
        "EXPLOITED_IN",
        "OBSERVED_TECHNIQUE",
        "LEVERAGED_VULNERABILITY",
        "EXPLOITED_IN_INCIDENT",
        "ANALYZES",
        "ANALYZED_IN",
        "PROPOSES",
        "PROPOSED_IN",
        "MITIGATES",
        "MITIGATED_BY",
        "EXPLOITS",
        "EXPLOITED_BY",
    }

    def _record_causal_neighbor(
        self,
        edge: Edge,
        curr_id: str,
        hops: int,
        visited_nodes: Set[str],
        queue: List[Tuple[str, int]],
        collected_edges: List[Edge],
    ) -> None:
        """Records an incident causal edge and queues the unvisited neighbor."""
        neighbor_id = edge.dst_id if edge.src_id == curr_id else edge.src_id
        collected_edges.append(edge)
        if neighbor_id not in visited_nodes:
            visited_nodes.add(neighbor_id)
            queue.append((neighbor_id, hops + 1))

    def _expand_causal_incident_edges(
        self,
        curr_id: str,
        hops: int,
        limit: int,
        visited_nodes: Set[str],
        queue: List[Tuple[str, int]],
        collected_edges: List[Edge],
    ) -> bool:
        """Expands incident causal edges from curr_id into queue and collected_edges."""
        for edge in self.get_both_edges(curr_id):
            if edge.label in self.CAUSAL_PREDICATES:
                self._record_causal_neighbor(
                    edge, curr_id, hops, visited_nodes, queue, collected_edges
                )
                if len(collected_edges) >= limit:
                    return True
        return False

    def _bfs_causal_subgraph(
        self,
        queue: List[Tuple[str, int]],
        limit: int,
        visited_nodes: Set[str],
        collected_edges: List[Edge],
        max_hops: int = 3,
    ) -> None:
        """Runs BFS exploration over causal edges up to max_hops or limit."""
        while queue:
            curr_id, hops = queue.pop(0)
            if hops >= max_hops:
                continue

            should_stop = self._expand_causal_incident_edges(
                curr_id, hops, limit, visited_nodes, queue, collected_edges
            )
            if should_stop:
                break

    def _query_causal(
        self, raw_arg: str, limit: int
    ) -> Tuple[List[Vertex], List[Edge], int]:
        """Extracts multi-hop causal inference subgraph starting from target entity."""
        target_id = self._resolve_ego_node_id(raw_arg.strip())
        if not target_id:
            return [], [], 0

        visited_nodes: Set[str] = {target_id}
        collected_edges: List[Edge] = []
        queue: List[Tuple[str, int]] = [(target_id, 0)]

        self._bfs_causal_subgraph(queue, limit, visited_nodes, collected_edges)

        nodes = self._collect_vertices(visited_nodes)
        node_id_set = {v.id for v in nodes}
        valid_edges = self._filter_edges_by_nodes(collected_edges, node_id_set)
        return nodes, valid_edges, len(nodes)

    def _is_terminal_causal_vertex(
        self, v_obj: Optional[Vertex], dst: Optional[str]
    ) -> bool:
        """Returns True if the vertex represents an open-ended terminal causal consequence."""
        if dst is not None or not v_obj:
            return False
        return v_obj.label in ("Impact", "Incident", "EvaluationResult")

    def _try_expand_causal_edge(
        self,
        edge: Edge,
        path: List[Dict[str, Any]],
        visited: Set[str],
        dst: Optional[str],
        queue: List[Tuple[str, List[Dict[str, Any]], Set[str]]],
        chains: List[List[Dict[str, Any]]],
    ) -> None:
        """Expands a single causal edge along the search path."""
        if edge.label not in self.CAUSAL_PREDICATES:
            return
        if edge.dst_id in visited:
            return

        nxt = edge.dst_id
        v_obj = self.get_vertex(nxt)
        label = v_obj.label if v_obj else "Vertex"
        nxt_node = {"node_id": nxt, "label": label, "via_edge": edge.label}
        new_path = path + [nxt_node]
        if self._is_terminal_causal_vertex(v_obj, dst):
            chains.append(new_path)
        queue.append((nxt, new_path, visited | {nxt}))

    def _step_causal_chains(
        self,
        curr: str,
        path: List[Dict[str, Any]],
        visited: Set[str],
        dst: Optional[str],
        queue: List[Tuple[str, List[Dict[str, Any]], Set[str]]],
        chains: List[List[Dict[str, Any]]],
    ) -> None:
        """Processes outgoing causal edges for the current path search node."""
        if dst and curr == dst:
            chains.append(path)
            return
        for edge in self.get_out_edges(curr):
            self._try_expand_causal_edge(edge, path, visited, dst, queue, chains)

    def find_causal_chains(
        self, start_id: str, end_id: Optional[str] = None, max_hops: int = 4
    ) -> List[List[Dict[str, Any]]]:
        """Discovers causal inference chains from start_id up to max_hops."""
        src = self._resolve_ego_node_id(start_id)
        if not src:
            return []
        dst = self._resolve_ego_node_id(end_id) if end_id else None

        chains: List[List[Dict[str, Any]]] = []
        init_node = {
            "node_id": src,
            "label": getattr(self.get_vertex(src), "label", "Vertex"),
        }
        queue: List[Tuple[str, List[Dict[str, Any]], Set[str]]] = [
            (src, [init_node], {src})
        ]

        while queue:
            curr, path, visited = queue.pop(0)
            if len(path) <= max_hops + 1:
                self._step_causal_chains(curr, path, visited, dst, queue, chains)

        return chains

    def _dispatch_structured_query(
        self, q_clean: str, q_low: str, limit: int
    ) -> Optional[Tuple[List[Vertex], List[Edge], int]]:
        if q_low.startswith("gap"):
            return self._query_gaps(limit)
        if q_low.startswith("cwe:"):
            return self._query_cwe(q_clean[4:], limit)
        if q_low.startswith("ego:"):
            return self._query_ego(q_clean[4:], limit)
        if q_low.startswith("causal:"):
            return self._query_causal(q_clean[7:], limit)
        return None

    def _dispatch_graph_query(
        self, q: str, limit: int
    ) -> Tuple[List[Vertex], List[Edge], int]:
        """Dispatches query string to appropriate search strategy."""
        q_clean = q.strip()
        q_low = q_clean.lower()
        res = self._dispatch_structured_query(q_clean, q_low, limit)
        if res is not None:
            return res
        if "->" in q_clean:
            return self._query_path(q_clean.replace("path:", ""))
        return self._query_match(q_clean.replace("match:", ""), limit)

    def _cap_subgraph_nodes_and_edges(
        self, nodes_raw: List[Vertex], edges_raw: List[Edge], limit: int
    ) -> Tuple[List[Vertex], List[Edge]]:
        nodes_capped = nodes_raw[:limit]
        node_id_set = {v.id for v in nodes_capped}
        edges_capped = self._filter_edges_by_nodes(edges_raw, node_id_set)
        return nodes_capped, edges_capped

    def execute_graph_query(self, query: str, limit: int = 50) -> Dict[str, Any]:
        """Executes domain graph query and exports formatted subgraph for Canvas."""
        nodes_raw, edges_raw, match_count = self._dispatch_graph_query(query, limit)
        nodes_capped, edges_capped = self._cap_subgraph_nodes_and_edges(
            nodes_raw, edges_raw, limit
        )
        gaps = self.get_research_gaps()
        gap_id_set = {g["id"] for g in gaps}

        return {
            "query": query,
            "match_count": match_count,
            "nodes": [self._format_cti_node(v, gap_id_set) for v in nodes_capped],
            "edges": [self._format_cti_edge(e) for e in edges_capped],
            "stats": self._compute_cti_counts(len(gap_id_set)),
        }
