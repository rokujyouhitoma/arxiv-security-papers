#!/usr/bin/env python3
"""
Unit tests for GraphRAG multi-hop expansion and grounding context formatting.
"""

from graph.engine import PropertyGraphEngine
from graph.graphrag import GraphRAGPipeline


def test_graphrag_context_expansion() -> None:
    engine = PropertyGraphEngine(memory_only=True)
    engine.add_vertex(
        "AttackTechnique:Prompt_Injection",
        label="AttackTechnique",
        properties={"name": "Prompt Injection"},
    )
    engine.add_vertex(
        "Vulnerability:CWE-79",
        label="Vulnerability",
        properties={"name": "CWE-79"},
    )
    engine.add_vertex(
        "DefenseMechanism:ZKP_Shield",
        label="DefenseMechanism",
        properties={"name": "ZKP Shield"},
    )

    engine.add_edge("Paper:2608.10001", "AttackTechnique:Prompt_Injection", label="ANALYZES")
    engine.add_edge("AttackTechnique:Prompt_Injection", "Vulnerability:CWE-79", label="EXPLOITS")
    engine.add_edge("DefenseMechanism:ZKP_Shield", "AttackTechnique:Prompt_Injection", label="MITIGATES")

    rag = GraphRAGPipeline(graph_engine=engine)
    res = rag.expand_context(seed_paper_ids=["2608.10001"], max_hops=2)

    assert res["seed_count"] == 1
    assert res["expanded_vertex_count"] >= 3
    assert res["expanded_triple_count"] >= 2

    # Verify markdown formatting contains facts
    md = res["grounding_context_markdown"]
    assert "Verified Security Knowledge Graph Grounding Context" in md
    assert "AttackTechnique:Prompt_Injection" in md
    assert "ANALYZES" in md
