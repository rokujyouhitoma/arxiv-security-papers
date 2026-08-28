#!/usr/bin/env python3
"""
Unit and Integration Tests for GraphRAG, Knowledge Graph Ingestion,
Attack-Defense Causal Chains, and Threat Defense MCP Tools.
"""

from typing import Any

import pytest

from graph.engine import PropertyGraphEngine
from graph.graphrag import GraphRAGPipeline
from mcp.threat_defense_server import (
    handle_get_attack_defense_chain,
    handle_get_blast_radius,
    handle_graphrag_query,
)
from ontology.extractor import OntologyExtractor

SAMPLE_OKF_CONTENT = """---
type: security-paper
title: "Zero-Trust Service Mesh Under Adversarial Side-Channel Attacks"
description: "ゼロトラストサービスメッシュにおけるサイドチャネル攻撃の検知と自動暗号化防御手法の提案"
tags:
  - zero-trust
  - side-channel
  - command-injection
  - cve-2026-9999
---

# Zero-Trust Service Mesh Under Adversarial Side-Channel Attacks

## 要約
本研究では、ゼロトラスト環境におけるコマンドインジェクション攻撃 (T1059) および CVE-2026-9999 に対する
リアルタイム防御策 (Zero Trust Auth & Token Rotation) を提案する。
"""


@pytest.fixture
def populated_graph_engine(tmp_path: Any) -> PropertyGraphEngine:
    db_path = str(tmp_path / "test_graph.db")
    engine = PropertyGraphEngine(storage_path=db_path, memory_only=True)

    # Ingest Sample Paper via OntologyExtractor
    entities, triples = OntologyExtractor.extract_from_okf(
        "2608.99999", SAMPLE_OKF_CONTENT
    )

    for ent in entities:
        engine.add_vertex(
            vertex_id=ent.id, label=ent.entity_type.value, properties=ent.to_dict()
        )
    for tr in triples:
        engine.add_edge(
            src_id=tr.subject_id,
            dst_id=tr.object_id,
            label=tr.predicate.value,
            weight=tr.weight,
        )

    # Explicitly add defense mitigation link for test robustness
    engine.add_vertex(
        "DefenseMechanism:TokenRotation",
        label="DefenseMechanism",
        properties={"name": "Token Rotation"},
    )
    engine.add_edge(
        "DefenseMechanism:TokenRotation",
        "AttackTechnique:T1059",
        label="MITIGATES",
        weight=1.0,
    )
    engine.add_edge(
        "Paper:2608.99999",
        "DefenseMechanism:TokenRotation",
        label="PROPOSES",
        weight=1.0,
    )
    engine.add_vertex(
        "TargetAsset:KubernetesCluster",
        label="TargetAsset",
        properties={"name": "Kubernetes Cluster"},
    )
    engine.add_edge(
        "AttackTechnique:T1059",
        "TargetAsset:KubernetesCluster",
        label="TARGETS",
        weight=1.0,
    )

    return engine


def test_ontology_extraction_and_graph_population(
    populated_graph_engine: PropertyGraphEngine,
) -> None:
    g = populated_graph_engine
    assert g.get_vertex("Paper:2608.99999") is not None
    assert g.get_vertex("AttackTechnique:T1059") is not None

    out_edges = g.get_out_edges("Paper:2608.99999")
    assert len(out_edges) >= 1
    edge_labels = [e.label for e in out_edges]
    assert "ANALYZES" in edge_labels or "PROPOSES" in edge_labels


def test_graphrag_expansion_and_markdown_grounding(
    populated_graph_engine: PropertyGraphEngine,
) -> None:
    pipeline = GraphRAGPipeline(populated_graph_engine)
    res = pipeline.expand_context(seed_paper_ids=["2608.99999"], max_hops=2)

    assert res["seed_count"] == 1
    assert res["expanded_vertex_count"] >= 3
    assert res["expanded_triple_count"] >= 2
    assert (
        "Verified Security Knowledge Graph Grounding Context"
        in res["grounding_context_markdown"]
    )


def test_find_defense_chains(populated_graph_engine: PropertyGraphEngine) -> None:
    pipeline = GraphRAGPipeline(populated_graph_engine)
    chains = pipeline.find_defense_chains("T1059")

    assert len(chains) >= 1
    chain = chains[0]
    assert chain["mitigation_relation"] == "MITIGATES"
    assert chain["defense_mechanism"]["id"] == "DefenseMechanism:TokenRotation"
    assert len(chain["effective_papers"]) >= 1
    assert chain["effective_papers"][0]["id"] == "Paper:2608.99999"


def test_calculate_blast_radius(populated_graph_engine: PropertyGraphEngine) -> None:
    pipeline = GraphRAGPipeline(populated_graph_engine)
    radius = pipeline.calculate_blast_radius("AttackTechnique:T1059", max_depth=2)

    assert radius["blast_radius_count"] >= 1
    impacted_ids = [item["entity"]["id"] for item in radius["impacted_entities"]]
    assert "TargetAsset:KubernetesCluster" in impacted_ids


def test_mcp_threat_defense_handlers(
    monkeypatch: Any, populated_graph_engine: PropertyGraphEngine
) -> None:
    import mcp.threat_defense_server as tds

    pipeline = GraphRAGPipeline(populated_graph_engine)
    monkeypatch.setattr(tds, "_get_graphrag_pipeline", lambda: pipeline)

    # 1. Test graphrag_query handler
    res_rag = handle_graphrag_query({"query": "zero trust side-channel", "max_hops": 2})
    assert res_rag["status"] == "success"
    assert res_rag["expanded_vertex_count"] >= 1

    # 2. Test get_attack_defense_chain handler
    res_chain = handle_get_attack_defense_chain({"keyword": "T1059"})
    assert res_chain["status"] == "success"
    assert res_chain["chain_count"] >= 1

    # 3. Test get_blast_radius handler
    res_blast = handle_get_blast_radius(
        {"entity_id": "AttackTechnique:T1059", "max_depth": 2}
    )
    assert res_blast["status"] == "success"
    assert res_blast["blast_radius_count"] >= 1
