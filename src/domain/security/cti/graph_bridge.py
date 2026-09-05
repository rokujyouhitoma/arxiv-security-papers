#!/usr/bin/env python3
"""
Property Graph Persistence Bridge for CTI Inferences.
Links Papers, AttackTechniques, DefenseMitigations, and Vulnerabilities as
Vertices and directed Edges within PropertyGraphEngine.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from graph.engine import PropertyGraphEngine
from graph.structures import Edge, Vertex

from .inference import InferredTechnique


def _clean_paper_id(paper_id: str) -> str:
    """Normalizes paper ID (e.g. arXiv ID: 2401.12345v1 -> 2401.12345)."""
    pid = paper_id.strip()
    pid = re.sub(r"^arxiv:", "", pid, flags=re.IGNORECASE)
    pid = re.sub(r"v\d+$", "", pid)
    return pid


def _determine_edge_label(research_focus: str) -> str:
    """Maps research focus to directed edge label."""
    if research_focus == "offensive":
        return "TARGETS"
    if research_focus == "defensive":
        return "PROPOSES_DEFENSE"
    return "DISCUSSES"


def _add_paper_vertex(
    paper_id: str,
    title: str,
    graph_engine: PropertyGraphEngine,
    additional_props: Optional[Dict[str, Any]] = None,
) -> Vertex:
    """Ensures paper vertex exists with metadata."""
    clean_id = _clean_paper_id(paper_id)
    v_id = f"paper:{clean_id}"
    props: Dict[str, Any] = {
        "title": title,
        "arxiv_id": clean_id,
        "entity_type": "Paper",
    }
    if additional_props:
        props.update(additional_props)
    return graph_engine.add_vertex(vertex_id=v_id, label="Paper", properties=props)


def _add_technique_vertex_and_edge(
    paper_v_id: str,
    tech: InferredTechnique,
    graph_engine: PropertyGraphEngine,
) -> Edge:
    """Creates AttackTechnique vertex and connecting edge from Paper."""
    tech_v_id = f"technique:{tech.technique_id}"
    tech_props = {
        "name": tech.technique_name,
        "tactic": tech.tactic,
        "mitre_id": tech.technique_id,
        "entity_type": "AttackTechnique",
    }
    graph_engine.add_vertex(
        vertex_id=tech_v_id,
        label="AttackTechnique",
        properties=tech_props,
    )

    edge_label = _determine_edge_label(tech.research_focus)
    edge_props = {
        "confidence": tech.confidence,
        "keywords": tech.matched_keywords,
        "research_focus": tech.research_focus,
    }
    return graph_engine.add_edge(
        src_id=paper_v_id,
        dst_id=tech_v_id,
        label=edge_label,
        weight=float(tech.confidence),
        properties=edge_props,
    )


def sync_cti_inferences_to_graph(
    paper_id: str,
    title: str,
    inferences: List[InferredTechnique],
    graph_engine: PropertyGraphEngine,
    save: bool = False,
    additional_props: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Persists paper and inferred techniques into the property graph.
    Connects Paper with AttackTechnique vertices via typed edges.
    """
    clean_id = _clean_paper_id(paper_id)
    paper_vertex = _add_paper_vertex(
        clean_id,
        title,
        graph_engine,
        additional_props,
    )

    created_edges: List[str] = []
    for tech in inferences:
        edge = _add_technique_vertex_and_edge(paper_vertex.id, tech, graph_engine)
        created_edges.append(edge.id)

    if save and not graph_engine.memory_only:
        graph_engine.save()

    return {
        "paper_vertex_id": paper_vertex.id,
        "techniques_synced": len(inferences),
        "edges_created": created_edges,
    }


def _sync_single_batch_item(
    item: Dict[str, Any],
    graph_engine: PropertyGraphEngine,
) -> int:
    """Syncs one paper item and returns count of created edges."""
    pid = str(item.get("paper_id", ""))
    title = str(item.get("title", ""))
    inferences = item.get("inferences", [])
    if not pid or not inferences:
        return 0
    res = sync_cti_inferences_to_graph(
        paper_id=pid,
        title=title,
        inferences=inferences,
        graph_engine=graph_engine,
        save=False,
    )
    return len(res.get("edges_created", []))


def _save_graph_if_needed(graph_engine: PropertyGraphEngine, save: bool) -> None:
    """Saves graph engine state if requested and not in memory-only mode."""
    if save and not graph_engine.memory_only:
        graph_engine.save()


def batch_sync_papers_to_graph(
    papers_data: List[Dict[str, Any]],
    graph_engine: PropertyGraphEngine,
    save: bool = True,
) -> Dict[str, int]:
    """
    Batch synchronizes multiple papers and their inferences to the graph.
    papers_data item format:
        {'paper_id': str, 'title': str, 'inferences': List[InferredTechnique]}
    """
    total_papers = 0
    total_edges = 0

    for item in papers_data:
        edges_count = _sync_single_batch_item(item, graph_engine)
        if edges_count > 0:
            total_papers += 1
            total_edges += edges_count

    _save_graph_if_needed(graph_engine, save)

    return {
        "synced_papers": total_papers,
        "synced_edges": total_edges,
    }


def find_papers_for_technique(
    technique_id: str,
    graph_engine: PropertyGraphEngine,
) -> List[Vertex]:
    """
    Retrieves all Paper vertices that reference a specific ATT&CK technique.
    Traverses incoming edges to the technique node.
    """
    tech_v_id = f"technique:{technique_id.upper()}"
    incoming_edges = graph_engine.get_in_edges(tech_v_id)
    papers: List[Vertex] = []

    for edge in incoming_edges:
        if edge.src_id.startswith("paper:"):
            vertex = graph_engine.get_vertex(edge.src_id)
            if vertex:
                papers.append(vertex)
    return papers


def find_techniques_for_paper(
    paper_id: str,
    graph_engine: PropertyGraphEngine,
) -> List[Vertex]:
    """
    Retrieves all AttackTechnique vertices associated with a specific paper.
    Traverses outgoing edges from the paper node.
    """
    clean_id = _clean_paper_id(paper_id)
    paper_v_id = f"paper:{clean_id}"
    outgoing_edges = graph_engine.get_out_edges(paper_v_id)
    techniques: List[Vertex] = []

    for edge in outgoing_edges:
        if edge.dst_id.startswith("technique:"):
            vertex = graph_engine.get_vertex(edge.dst_id)
            if vertex:
                techniques.append(vertex)
    return techniques
