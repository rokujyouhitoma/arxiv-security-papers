#!/usr/bin/env python3
"""
Unit Tests for Packrat PEG CTI Graph Query DSL.
Validates path queries, labeled multi-hop edge traversal, composite filters,
and integration with PropertyGraphEngine.
Conforms to DSN-25 Phase 1 / DSN-18 specifications.
"""

from typing import Any, Dict

import pytest

from graph.engine import PropertyGraphEngine
from graph.query_dsl import GraphQueryDSLParser, execute_dsl_query


@pytest.fixture
def populated_engine() -> PropertyGraphEngine:
    engine = PropertyGraphEngine()
    # Vertices
    engine.add_vertex("apt29", "ThreatActor", {"name": "APT29", "country": "RU"})
    engine.add_vertex("cobalt", "Malware", {"name": "Cobalt Strike"})
    engine.add_vertex("cve1", "Vulnerability", {"name": "CVE-2021-44228"})
    engine.add_vertex(
        "lazarus", "ThreatActor", {"name": "Lazarus Group", "country": "KP"}
    )

    # Edges (src_id, dst_id, label)
    engine.add_edge("apt29", "cobalt", "USES")
    engine.add_edge("cobalt", "cve1", "EXPLOITS")
    engine.add_edge("lazarus", "cobalt", "USES")
    return engine


def test_dsl_parser_path_syntax() -> None:
    parser = GraphQueryDSLParser()

    # 1. Simple path
    res1 = parser.parse("APT29 -> Cobalt")
    assert res1.kind == "path"
    assert res1.path is not None
    assert len(res1.path.nodes) == 2
    assert res1.path.nodes[0].name_or_id == "APT29"
    assert res1.path.nodes[1].name_or_id == "Cobalt"
    assert res1.path.edges[0].direction == "out"

    # 2. Labeled multi-hop path
    res2 = parser.parse("APT29 -> [USES] -> Malware -> [EXPLOITS] -> CWE-79")
    assert res2.kind == "path"
    assert res2.path is not None
    assert len(res2.path.nodes) == 3
    assert len(res2.path.edges) == 2
    assert res2.path.edges[0].label == "USES"
    assert res2.path.edges[1].label == "EXPLOITS"

    # 3. Parenthesized with labels
    res3 = parser.parse("(:ThreatActor) -> [:USES] -> (:Malware)")
    assert res3.kind == "path"
    assert res3.path is not None
    assert res3.path.nodes[0].label == "ThreatActor"
    assert res3.path.nodes[1].label == "Malware"
    assert res3.path.edges[0].label == "USES"


def test_dsl_parser_filter_syntax() -> None:
    parser = GraphQueryDSLParser()
    res = parser.parse("community:0 AND label:ThreatActor")
    assert res.kind == "filter"
    assert res.filter is not None
    assert len(res.filter.conditions) == 2
    assert res.filter.conditions[0].key == "community"
    assert res.filter.conditions[0].value == "0"
    assert res.filter.conditions[1].key == "label"
    assert res.filter.conditions[1].value == "ThreatActor"


def test_dsl_execution_path(populated_engine: PropertyGraphEngine) -> None:
    # Query: apt29 -> [USES] -> cobalt -> [EXPLOITS] -> cve1
    query = "apt29 -> [USES] -> cobalt -> [EXPLOITS] -> cve1"
    res = execute_dsl_query(populated_engine, query, limit=10)
    assert res is not None
    nodes, edges, count = res
    assert count == 3
    node_ids = {v.id for v in nodes}
    assert node_ids == {"apt29", "cobalt", "cve1"}
    edge_labels = {e.label for e in edges}
    assert "USES" in edge_labels
    assert "EXPLOITS" in edge_labels


def test_dsl_execution_filter(populated_engine: PropertyGraphEngine) -> None:
    # Query: label:ThreatActor
    query = "label:ThreatActor"
    res = execute_dsl_query(populated_engine, query, limit=10)
    assert res is not None
    nodes, edges, count = res
    assert count == 2
    node_ids = {v.id for v in nodes}
    assert node_ids == {"apt29", "lazarus"}


def test_engine_execute_graph_query_dispatch(
    populated_engine: PropertyGraphEngine,
) -> None:
    # Full round-trip through execute_graph_query
    out: Dict[str, Any] = populated_engine.execute_graph_query(
        "apt29 -> [USES] -> cobalt", limit=10
    )
    assert out["match_count"] >= 2
    assert len(out["nodes"]) >= 2
    assert len(out["edges"]) >= 1
    labels = {n["label"] for n in out["nodes"]}
    assert "ThreatActor" in labels
    assert "Malware" in labels
