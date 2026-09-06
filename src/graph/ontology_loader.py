#!/usr/bin/env python3
"""Ontology TBox (Schema) Loader for Property Graph Engine.

Ingests W3C Turtle / OWL ontology class definitions and object properties (TBox)
into PropertyGraphEngine vertices and edges, enabling interactive schema exploration,
causality chain visualization, and GraphRAG semantic path navigation.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Tuple

from graph.engine import PropertyGraphEngine
from graph.structures import Edge, Vertex
from ontology.turtle_engine import (
    TurtleDocumentBuilder,
    build_full_spectrum_security_ontology,
)

logger = logging.getLogger(__name__)

# Distinct color palette for ontology schema classes
ONTOLOGY_CLASS_COLORS: Dict[str, str] = {
    "Paper": "#4f46e5",  # Indigo
    "ThreatActor": "#dc2626",  # Red
    "AttackTechnique": "#ea580c",  # Orange
    "Vulnerability": "#d97706",  # Amber
    "TargetAsset": "#0284c7",  # Light Blue
    "DefenseMechanism": "#16a34a",  # Emerald Green
    "DetectionRule": "#059669",  # Teal
    "BenchmarkMetric": "#7c3aed",  # Purple
    "Incident": "#be123c",  # Rose
    "PoCArtifact": "#0891b2",  # Cyan
    "Precondition": "#eab308",  # Gold / Yellow
    "ResearchGap": "#64748b",  # Slate Gray
    "ResidualRisk": "#b91c1c",  # Dark Red
    "PublicationVenue": "#2563eb",  # Royal Blue
    "Impact": "#db2777",  # Pink / Magenta
    "Claim": "#8b5cf6",  # Violet
    "EvaluationResult": "#10b981",  # Mint Green
}


def _strip_prefix(uri: str) -> str:
    """Strips namespace prefix like 'sec:' or full URL."""
    if ":" in uri:
        return uri.split(":")[-1]
    if "#" in uri:
        return uri.split("#")[-1]
    if "/" in uri:
        return uri.split("/")[-1]
    return uri


def build_ontology_schema_graph(
    builder: Optional[TurtleDocumentBuilder] = None,
) -> Tuple[List[Vertex], List[Edge]]:
    """Constructs vertices and edges representing the TBox ontology schema."""
    if builder is None:
        builder = build_full_spectrum_security_ontology()

    vertices: List[Vertex] = []
    edges: List[Edge] = []

    # 1. Classes -> Vertices
    for cls in builder.classes:
        clean_name = _strip_prefix(cls.uri)
        v_id = f"Class:{clean_name}"
        color = ONTOLOGY_CLASS_COLORS.get(clean_name, "#6366f1")

        props: Dict[str, Any] = {
            "entity_type": "OntologyClass",
            "class_name": clean_name,
            "uri": cls.uri,
            "title": cls.label or clean_name,
            "comment": cls.comment or "",
            "sub_class_of": cls.sub_class_of,
            "section": cls.section_comment or "",
            "color": color,
            "radius": 18,
            "is_schema": True,
        }
        vertices.append(Vertex(id=v_id, label="OntologyClass", properties=props))

    # 2. Object Properties -> Edges
    edge_idx = 0
    for op in builder.object_properties:
        if not op.domain or not op.range_:
            continue

        src_name = _strip_prefix(op.domain)
        dst_name = _strip_prefix(op.range_)
        src_id = f"Class:{src_name}"
        dst_id = f"Class:{dst_name}"

        clean_prop = _strip_prefix(op.uri)
        is_causal = clean_prop in (
            "hasImpact",
            "impactCausedBy",
            "neutralizesPrecondition",
            "preconditionNeutralizedBy",
        )
        is_reified = clean_prop in (
            "assertsClaim",
            "claimAssertedBy",
            "evaluatesClaim",
            "claimEvaluatedIn",
            "evaluatesTechnique",
        )

        edge_props: Dict[str, Any] = {
            "relation_name": clean_prop,
            "uri": op.uri,
            "label": op.label or clean_prop,
            "inverse_of": op.inverse_of,
            "is_transitive": op.is_transitive,
            "is_symmetric": op.is_symmetric,
            "is_causal": is_causal,
            "is_reified": is_reified,
            "is_schema": True,
            "confidence": 1.0,
            "tier": "HIGH",
        }

        edges.append(
            Edge(
                src_id=src_id,
                dst_id=dst_id,
                label=clean_prop,
                properties=edge_props,
            )
        )
        edge_idx += 1

    return vertices, edges


def ingest_ontology_tbox(
    engine: PropertyGraphEngine,
    builder: Optional[TurtleDocumentBuilder] = None,
) -> Tuple[int, int]:
    """Ingests the TBox ontology schema vertices and edges into the PropertyGraphEngine."""
    vertices, edges = build_ontology_schema_graph(builder)
    for v in vertices:
        engine.add_vertex(v.id, label=v.label, properties=v.properties)
    for e in edges:
        engine.add_edge(
            e.src_id,
            e.dst_id,
            label=e.label,
            weight=e.weight,
            properties=e.properties,
        )
    return len(vertices), len(edges)


def export_schema_graph_json(
    builder: Optional[TurtleDocumentBuilder] = None,
) -> Dict[str, Any]:
    """Exports the schema graph directly to a JSON-ready dict for Web UI."""
    vertices, edges = build_ontology_schema_graph(builder)
    nodes_data = []
    for v in vertices:
        nodes_data.append(
            {
                "id": v.id,
                "label": v.properties.get("title", v.id),
                "type": v.properties.get("class_name", "OntologyClass"),
                "clean_id": v.properties.get("class_name", ""),
                "uri": v.properties.get("uri", ""),
                "comment": v.properties.get("comment", ""),
                "color": v.properties.get("color", "#6366f1"),
                "radius": v.properties.get("radius", 18),
                "is_schema": True,
            }
        )

    edges_data = []
    for e in edges:
        edges_data.append(
            {
                "id": e.id,
                "source": e.src_id,
                "target": e.dst_id,
                "type": e.label,
                "label": e.properties.get("label", e.label),
                "inverse_of": e.properties.get("inverse_of", ""),
                "is_causal": e.properties.get("is_causal", False),
                "is_reified": e.properties.get("is_reified", False),
                "is_schema": True,
            }
        )

    return {
        "status": "success",
        "total_nodes": len(nodes_data),
        "total_edges": len(edges_data),
        "nodes": nodes_data,
        "edges": edges_data,
        "ontology_version": "2.0.0",
    }
