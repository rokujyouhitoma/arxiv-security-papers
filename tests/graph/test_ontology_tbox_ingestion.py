#!/usr/bin/env python3
"""Tests for Ontology TBox (Schema) Ingestion and Visualization API (Issue #187)."""

import json

from graph.engine import PropertyGraphEngine
from graph.ontology_loader import (
    build_ontology_schema_graph,
    export_schema_graph_json,
    ingest_ontology_tbox,
)
from web.gateway.handlers import GatewayHandlers


def test_build_ontology_schema_graph():
    """Verify build_ontology_schema_graph extracts all 17 OWL classes and edges."""
    vertices, edges = build_ontology_schema_graph()

    class_names = {v.properties["class_name"] for v in vertices}
    assert len(vertices) == 17
    assert "Paper" in class_names
    assert "AttackTechnique" in class_names
    assert "Incident" in class_names
    assert "Impact" in class_names
    assert "Precondition" in class_names
    assert "Claim" in class_names
    assert "EvaluationResult" in class_names

    # Check edges
    edge_types = {e.label for e in edges}
    assert len(edges) > 50
    assert "hasImpact" in edge_types
    assert "neutralizesPrecondition" in edge_types
    assert "assertsClaim" in edge_types
    assert "evaluatesTechnique" in edge_types
    assert "exploitedIn" in edge_types

    # Check causal and reified flags
    causal_edges = [e for e in edges if e.properties.get("is_causal")]
    assert len(causal_edges) >= 4
    reified_edges = [e for e in edges if e.properties.get("is_reified")]
    assert len(reified_edges) >= 5


def test_ingest_ontology_tbox(tmp_path):
    """Verify ingest_ontology_tbox populates PropertyGraphEngine."""
    db_path = tmp_path / "test_tbox_graph.db"
    engine = PropertyGraphEngine(storage_path=str(db_path))

    v_count, e_count = ingest_ontology_tbox(engine)
    assert v_count == 17
    assert e_count > 50

    # Query class vertex
    impact_vertex = engine.get_vertex("Class:Impact")
    assert impact_vertex is not None
    assert impact_vertex.label == "OntologyClass"
    assert impact_vertex.properties["class_name"] == "Impact"
    assert "被害" in impact_vertex.properties["title"]

    claim_vertex = engine.get_vertex("Class:Claim")
    assert claim_vertex is not None
    assert claim_vertex.properties["class_name"] == "Claim"


def test_export_schema_graph_json():
    """Verify export_schema_graph_json returns expected API structure."""
    data = export_schema_graph_json()
    assert data["status"] == "success"
    assert data["total_nodes"] == 17
    assert data["total_edges"] > 50
    assert data["ontology_version"] == "2.0.0"

    # Check node schema
    first_node = data["nodes"][0]
    assert "id" in first_node
    assert "label" in first_node
    assert "type" in first_node
    assert "color" in first_node
    assert first_node["is_schema"] is True

    # Check edge schema
    first_edge = data["edges"][0]
    assert "source" in first_edge
    assert "target" in first_edge
    assert "type" in first_edge
    assert "label" in first_edge
    assert first_edge["is_schema"] is True


def test_handle_graph_schema_api(tmp_path):
    """Verify GatewayHandlers.handle_graph_schema returns 200 OK and valid JSON."""
    handlers = GatewayHandlers(workspace_dir=str(tmp_path))

    status_code = None
    headers_list = []

    def mock_start_response(status, headers):
        nonlocal status_code, headers_list
        status_code = status
        headers_list = headers

    response_bytes = handlers.handle_graph_schema(mock_start_response)
    assert status_code == "200 OK"
    body = json.loads(b"".join(response_bytes).decode("utf-8"))
    assert body["status"] == "success"
    assert body["total_nodes"] == 17
    assert len(body["nodes"]) == 17
