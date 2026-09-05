#!/usr/bin/env python3
"""
Unit tests for PropertyGraphEngine.execute_graph_query.
Tests CTI graph query routing, gaps extraction, CWE impact, ego-network,
keyword matching, and path traversal.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

from graph.engine import PropertyGraphEngine
from ontology.seeder import seed_ontology_graph


def _build_test_graph() -> PropertyGraphEngine:
    engine = PropertyGraphEngine(memory_only=True)
    seed_ontology_graph(engine)
    engine.add_vertex(
        "Paper:2501.00001",
        label="Paper",
        properties={"title": "Adversarial Prompt Injection Defense in LLMs"},
    )
    engine.add_edge("Paper:2501.00001", "AttackTechnique:AML.T0054", label="ANALYZES")
    return engine


def test_query_gaps() -> None:
    engine = _build_test_graph()
    res = engine.execute_graph_query("gaps", limit=20)
    assert res["query"] == "gaps"
    assert "nodes" in res
    assert "edges" in res
    assert len(res["nodes"]) > 0
    # Seeded graph has multiple gaps with 0 defensive papers
    gap_nodes = [n for n in res["nodes"] if n.get("is_research_gap")]
    assert len(gap_nodes) > 0


def test_query_cwe() -> None:
    engine = _build_test_graph()
    res = engine.execute_graph_query("cwe: CWE-20", limit=20)
    assert res["query"] == "cwe: CWE-20"
    node_ids = {n["id"] for n in res["nodes"]}
    assert "Vulnerability:CWE-20" in node_ids


def test_query_ego() -> None:
    engine = _build_test_graph()
    res = engine.execute_graph_query("ego: AML.T0054 2", limit=20)
    node_ids = {n["id"] for n in res["nodes"]}
    assert "AttackTechnique:AML.T0054" in node_ids
    # Connected paper should be included in 1-2 hop ego network
    assert "Paper:2501.00001" in node_ids


def test_query_match_keyword() -> None:
    engine = _build_test_graph()
    res = engine.execute_graph_query("match: injection", limit=20)
    assert len(res["nodes"]) > 0
    node_ids = {n["id"] for n in res["nodes"]}
    assert "AttackTechnique:AML.T0054" in node_ids or "Paper:2501.00001" in node_ids


def test_query_path_traversal() -> None:
    engine = _build_test_graph()
    res = engine.execute_graph_query("AML.T0054 -> CWE-20", limit=20)
    assert len(res["nodes"]) >= 2
    node_ids = {n["id"] for n in res["nodes"]}
    assert "AttackTechnique:AML.T0054" in node_ids
    assert "Vulnerability:CWE-20" in node_ids


def test_query_empty_or_non_matching() -> None:
    engine = _build_test_graph()
    res = engine.execute_graph_query("match: nonexistent_xyz_keyword", limit=20)
    assert res["match_count"] == 0
    assert len(res["nodes"]) == 0
    assert len(res["edges"]) == 0


def test_query_match_paper_expands_1hop_edges() -> None:
    engine = _build_test_graph()
    res = engine.execute_graph_query("match: Paper:", limit=20)
    assert res["match_count"] == 1
    node_ids = {n["id"] for n in res["nodes"]}
    assert "Paper:2501.00001" in node_ids
    assert "AttackTechnique:AML.T0054" in node_ids
    assert len(res["edges"]) >= 1
    edge = res["edges"][0]
    assert edge["source"] == "Paper:2501.00001"
    assert edge["target"] == "AttackTechnique:AML.T0054"
    assert edge["label"] == "ANALYZES"
    for e in res["edges"]:
        assert e["source"] in node_ids
        assert e["target"] in node_ids


def test_query_match_by_label() -> None:
    engine = _build_test_graph()
    res = engine.execute_graph_query("match: Paper", limit=20)
    assert res["match_count"] >= 1
    node_ids = {n["id"] for n in res["nodes"]}
    assert "Paper:2501.00001" in node_ids

    res_tech = engine.execute_graph_query("match: AttackTechnique", limit=20)
    assert res_tech["match_count"] >= 1
    tech_ids = {n["id"] for n in res_tech["nodes"]}
    assert any(tid.startswith("AttackTechnique:") for tid in tech_ids)


def test_query_gaps_zero_dangling_edges() -> None:
    engine = _build_test_graph()
    res = engine.execute_graph_query("gaps", limit=20)
    node_ids = {n["id"] for n in res["nodes"]}
    for e in res["edges"]:
        assert e["source"] in node_ids, f"Dangling edge source: {e['source']}"
        assert e["target"] in node_ids, f"Dangling edge target: {e['target']}"


def test_query_1hop_expansion_bounds() -> None:
    engine = PropertyGraphEngine(memory_only=True)
    engine.add_vertex(
        "Paper:Hub", label="Paper", properties={"title": "Super Hub Paper"}
    )
    for i in range(35):
        t_id = f"AttackTechnique:T{i:04d}"
        engine.add_vertex(
            t_id, label="AttackTechnique", properties={"name": f"Tech {i}"}
        )
        engine.add_edge("Paper:Hub", t_id, label="STUDIES")

    res = engine.execute_graph_query("match: Hub", limit=10)
    assert res["match_count"] == 1
    assert len(res["edges"]) <= 20
    assert len(res["nodes"]) <= 21
    node_ids = {n["id"] for n in res["nodes"]}
    for e in res["edges"]:
        assert e["source"] in node_ids
        assert e["target"] in node_ids
