#!/usr/bin/env python3
"""
Unit tests for Gremlin-compatible GraphTraversal DSL (rokujyouhitoma/gremlin compliance).
"""

from graph.engine import PropertyGraphEngine


def _build_test_security_graph() -> PropertyGraphEngine:
    engine = PropertyGraphEngine(memory_only=True)
    # Vertices
    engine.add_vertex(
        "Paper:101", label="Paper", properties={"year": 2026, "title": "Paper A"}
    )
    engine.add_vertex(
        "Paper:102", label="Paper", properties={"year": 2026, "title": "Paper B"}
    )
    engine.add_vertex(
        "Attack:PI",
        label="AttackTechnique",
        properties={"name": "Prompt Injection", "risk": 9.5},
    )
    engine.add_vertex(
        "Vuln:CWE-79", label="Vulnerability", properties={"severity": "High"}
    )
    engine.add_vertex(
        "Defense:ZKP",
        label="DefenseMechanism",
        properties={"category": "ZKP", "overhead": 12.0},
    )
    engine.add_vertex("Asset:LLM", label="TargetAsset", properties={"type": "LLM"})

    # Edges
    engine.add_edge("Paper:101", "Attack:PI", label="ANALYZES")
    engine.add_edge("Attack:PI", "Vuln:CWE-79", label="EXPLOITS")
    engine.add_edge("Attack:PI", "Asset:LLM", label="TARGETS")
    engine.add_edge("Defense:ZKP", "Attack:PI", label="MITIGATES")
    engine.add_edge("Defense:ZKP", "Vuln:CWE-79", label="PATCHES")
    engine.add_edge("Paper:102", "Defense:ZKP", label="PROPOSES")
    return engine


def test_gremlin_navigation_steps() -> None:
    g = _build_test_security_graph()

    # g.V().out()
    attacks = g.V("Paper:101").out("ANALYZES").toList()
    assert len(attacks) == 1
    assert attacks[0].id == "Attack:PI"

    # 2-hop navigation: Paper:101 -> Attack:PI -> Vuln:CWE-79
    vulns = g.V("Paper:101").out("ANALYZES").out("EXPLOITS").toList()
    assert len(vulns) == 1
    assert vulns[0].id == "Vuln:CWE-79"

    # in_ navigation: Attack:PI <- Defense:ZKP
    defenses = g.V("Attack:PI").in_("MITIGATES").toList()
    assert len(defenses) == 1
    assert defenses[0].id == "Defense:ZKP"

    # both navigation
    neighbors = g.V("Attack:PI").both().toList()
    neighbor_ids = {v.id for v in neighbors}
    assert "Paper:101" in neighbor_ids
    assert "Vuln:CWE-79" in neighbor_ids
    assert "Asset:LLM" in neighbor_ids
    assert "Defense:ZKP" in neighbor_ids


def test_gremlin_filter_and_projection_steps() -> None:
    g = _build_test_security_graph()

    # has, values, dedup
    titles = g.V().hasLabel("Paper").has("year", 2026).values("title").toList()
    assert set(titles) == {"Paper A", "Paper B"}

    # valueMap
    vm = g.V("Defense:ZKP").valueMap("category").toList()
    assert vm == [{"category": "ZKP"}]

    # count, sum, mean
    cnt = g.V().hasLabel("Paper").count().next()
    assert cnt == 2

    # limit and skip
    first_v = g.V().limit(1).toList()
    assert len(first_v) == 1

    # repeat times
    two_hops = g.V("Paper:101").repeat(lambda trav: trav.out()).times(2).toList()
    two_hop_ids = {v.id for v in two_hops}
    assert "Vuln:CWE-79" in two_hop_ids
    assert "Asset:LLM" in two_hop_ids


def test_graph_algorithms_shortest_path_and_pagerank() -> None:
    g = _build_test_security_graph()

    # Shortest Path from Paper:101 to Asset:LLM
    path = g.V("Paper:101").shortestPath("Asset:LLM")
    assert len(path) == 3
    assert [v.id for v in path] == ["Paper:101", "Attack:PI", "Asset:LLM"]

    # PageRank
    ranks = g.V().pageRank(iterations=10)
    assert len(ranks) == 6
    # Attack:PI and Vuln:CWE-79 should have high centrality
    assert ranks["Attack:PI"] > 0.0
    assert ranks["Vuln:CWE-79"] > 0.0
