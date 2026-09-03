#!/usr/bin/env python3
"""
Unit tests for Paper-ATT&CK-CWE CTI Knowledge Graph.
Tests ontology seeding, OKF ingestion, multi-hop impact traversal, and research gap detection.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import os
from typing import Any

from graph.engine import PropertyGraphEngine
from ontology.extractor import OntologyExtractor
from ontology.seeder import seed_ontology_graph


def test_seed_ontologies_and_stats(tmp_path: Any) -> None:
    db_file = os.path.join(str(tmp_path), "test_seed.db")
    engine = PropertyGraphEngine(storage_path=db_file, memory_only=True)

    v_count, e_count = seed_ontology_graph(engine)
    assert v_count >= 30
    assert e_count >= 20
    assert engine.vertex_count == v_count
    assert engine.edge_count == e_count

    # Check key ATT&CK and CWE nodes
    aml_node = engine.get_vertex("AttackTechnique:AML.T0054")
    assert aml_node is not None
    assert aml_node.label == "AttackTechnique"
    assert aml_node.properties.get("name") == "LLM Prompt Injection"

    cwe_node = engine.get_vertex("Vulnerability:CWE-20")
    assert cwe_node is not None
    assert cwe_node.label == "Vulnerability"


def test_research_gaps_detection(tmp_path: Any) -> None:
    engine = PropertyGraphEngine(memory_only=True)
    seed_ontology_graph(engine)

    # Initially, all seeded ontology nodes have zero connected papers
    gaps = engine.get_research_gaps()
    assert len(gaps) > 0
    gap_ids = {g["id"] for g in gaps}
    assert "AttackTechnique:AML.T0054" in gap_ids

    # Connect a paper to AML.T0054
    engine.add_vertex(
        "Paper:2501.99999",
        label="Paper",
        properties={"title": "Defense against Prompt Injection"},
    )
    engine.add_edge("Paper:2501.99999", "AttackTechnique:AML.T0054", label="ANALYZES")

    # Now AML.T0054 should no longer be a gap
    updated_gaps = engine.get_research_gaps()
    updated_gap_ids = {g["id"] for g in updated_gaps}
    assert "AttackTechnique:AML.T0054" not in updated_gap_ids
    assert len(updated_gaps) == len(gaps) - 1


def test_cwe_impact_traversal(tmp_path: Any) -> None:
    engine = PropertyGraphEngine(memory_only=True)
    seed_ontology_graph(engine)

    # In standard edges: AttackTechnique:T1190 -[EXPLOITS]-> Vulnerability:CWE-89
    # Add a Paper analyzing T1190
    engine.add_vertex(
        "Paper:2501.00001",
        label="Paper",
        properties={"title": "Web Exploits in the Wild"},
    )
    engine.add_edge("Paper:2501.00001", "AttackTechnique:T1190", label="EXPLOITS")

    impact = engine.get_cwe_impact("CWE-89")
    assert impact["cwe"] is not None
    assert impact["cwe"]["id"] == "Vulnerability:CWE-89"
    tech_ids = {t["id"] for t in impact["techniques"]}
    assert "AttackTechnique:T1190" in tech_ids
    paper_ids = {p["id"] for p in impact["papers"]}
    assert "Paper:2501.00001" in paper_ids
    assert len(impact["paths"]) >= 2


def test_neighborhood_and_subgraph_export(tmp_path: Any) -> None:
    engine = PropertyGraphEngine(memory_only=True)
    seed_ontology_graph(engine)

    # Test export_cti_subgraph
    subgraph = engine.export_cti_subgraph(limit=15)
    assert len(subgraph["nodes"]) <= 15
    assert "stats" in subgraph
    assert subgraph["stats"]["total_techniques"] >= 10
    assert subgraph["stats"]["total_cwes"] >= 15
    assert subgraph["stats"]["research_gap_count"] > 0

    # Test neighborhood retrieval
    sub_ego = engine.get_neighborhood("AttackTechnique:AML.T0054", max_hops=1)
    assert len(sub_ego["nodes"]) >= 2
    ego_ids = {n["id"] for n in sub_ego["nodes"]}
    assert "AttackTechnique:AML.T0054" in ego_ids
    assert "Vulnerability:CWE-20" in ego_ids


def test_okf_ingest_paper_to_graph(tmp_path: Any) -> None:
    engine = PropertyGraphEngine(memory_only=True)

    fake_okf = """---
title: "Adversarial Prompt Injection in Autonomous Agents"
description: "LLMプロンプトインジェクション攻撃とメモリ汚染脆弱性CWE-20の実証"
tags:
  - prompt injection
  - cwe-20
---

# Abstract
We demonstrate how prompt injection exploits CWE-20 input validation flaws.
"""

    ent_count, trip_count = OntologyExtractor.ingest_paper_to_graph(
        clean_id="2501.12345",
        markdown_content=fake_okf,
        engine=engine,
        confidence=0.95,
        tier="gold",
    )

    assert ent_count >= 1
    assert engine.vertex_count >= 1
    paper_v = engine.get_vertex("Paper:2501.12345")
    assert paper_v is not None
    assert paper_v.label == "Paper"
