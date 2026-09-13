#!/usr/bin/env python3
"""
Tests for Louvain Community Detection in PropertyGraphEngine and GraphTraversal.
Verifies modular threat clustering across threat actors, malware, and techniques.
"""

from graph.engine import PropertyGraphEngine
from graph.traversal import GraphTraversal, detect_threat_communities


def _create_cti_test_graph() -> PropertyGraphEngine:
    """
    Builds a synthetic CTI graph with 2 well-defined threat clusters:
    Cluster 1 (APT29 / CozyBear ecosystem):
      - APT29, CozyBear, WellMess, T1059
    Cluster 2 (Lazarus Group ecosystem):
      - Lazarus, AppleJeus, Fallchill, T1071
    Weak bridge:
      - T1059 <-> T1071 (general technique association)
    """
    engine = PropertyGraphEngine(memory_only=True)

    # Cluster 1 Vertices
    engine.add_vertex("APT29", label="ThreatActor", properties={"name": "APT29"})
    engine.add_vertex("CozyBear", label="ThreatActor", properties={"name": "Cozy Bear"})
    engine.add_vertex("WellMess", label="Malware", properties={"name": "WellMess"})
    engine.add_vertex(
        "T1059", label="Technique", properties={"name": "Command and Scripting"}
    )

    # Cluster 1 Edges (strong clique/subgraph)
    engine.add_edge("APT29", "CozyBear", label="SYNONYM_OF", weight=5.0)
    engine.add_edge("APT29", "WellMess", label="USES", weight=4.0)
    engine.add_edge("CozyBear", "WellMess", label="USES", weight=4.0)
    engine.add_edge("WellMess", "T1059", label="EMPLOYS", weight=3.0)

    # Cluster 2 Vertices
    engine.add_vertex(
        "Lazarus", label="ThreatActor", properties={"name": "Lazarus Group"}
    )
    engine.add_vertex("AppleJeus", label="Malware", properties={"name": "AppleJeus"})
    engine.add_vertex("Fallchill", label="Malware", properties={"name": "Fallchill"})
    engine.add_vertex(
        "T1071", label="Technique", properties={"name": "Application Layer Protocol"}
    )

    # Cluster 2 Edges (strong clique/subgraph)
    engine.add_edge("Lazarus", "AppleJeus", label="USES", weight=4.0)
    engine.add_edge("Lazarus", "Fallchill", label="USES", weight=4.0)
    engine.add_edge("AppleJeus", "Fallchill", label="RELATED_TO", weight=3.0)
    engine.add_edge("Fallchill", "T1071", label="EMPLOYS", weight=3.0)

    # Weak bridge between T1059 and T1071
    engine.add_edge("T1059", "T1071", label="CO_OCCURS", weight=0.2)

    return engine


def test_engine_detect_communities_basic() -> None:
    engine = _create_cti_test_graph()
    partition = engine.detect_communities(seed=42)

    assert len(partition) == 8
    # Vertices in Cluster 1 should share the same community ID
    c1 = partition["APT29"]
    assert partition["CozyBear"] == c1
    assert partition["WellMess"] == c1

    # Vertices in Cluster 2 should share the same community ID
    c2 = partition["Lazarus"]
    assert partition["AppleJeus"] == c2
    assert partition["Fallchill"] == c2

    # Both clusters should be distinct
    assert c1 != c2


def test_traversal_detect_communities() -> None:
    engine = _create_cti_test_graph()
    traversal = GraphTraversal(engine)
    comms = traversal.detect_communities(resolution=1.0, seed=42)

    assert isinstance(comms, dict)
    assert len(comms) == 8
    assert comms["APT29"] == comms["CozyBear"]
    assert comms["Lazarus"] == comms["AppleJeus"]
    assert comms["APT29"] != comms["Lazarus"]


def test_edge_label_filtering_and_weights() -> None:
    engine = _create_cti_test_graph()
    # Filter only USES edges
    partition = detect_threat_communities(engine, edge_labels=["USES"], seed=42)
    assert len(partition) == 8
    # APT29 and WellMess should be clustered together via USES
    assert partition["APT29"] == partition["WellMess"]
    # AppleJeus and Lazarus should be clustered together via USES
    assert partition["Lazarus"] == partition["AppleJeus"]

    # Test with custom weight property
    weighted_part = detect_threat_communities(
        engine, weight_property="custom_w", seed=42
    )
    assert weighted_part["APT29"] == weighted_part["WellMess"]
    assert weighted_part["Lazarus"] == weighted_part["Fallchill"]
    assert weighted_part["APT29"] != weighted_part["Lazarus"]


def test_empty_and_disconnected_graphs() -> None:
    empty_engine = PropertyGraphEngine(memory_only=True)
    assert empty_engine.detect_communities() == {}

    # Disconnected graph (isolated nodes)
    empty_engine.add_vertex("V1", label="ThreatActor")
    empty_engine.add_vertex("V2", label="Malware")
    disconnected_comms = empty_engine.detect_communities()
    assert len(disconnected_comms) == 2
    assert disconnected_comms["V1"] != disconnected_comms["V2"]


def test_execute_graph_query_community_dispatch() -> None:
    engine = _create_cti_test_graph()

    # Query top community
    res0 = engine.execute_graph_query("community:0", limit=10)
    assert res0["query"] == "community:0"
    assert res0["match_count"] > 0
    assert len(res0["nodes"]) > 0

    # Check node structure formatted for Canvas
    first_node = res0["nodes"][0]
    assert "id" in first_node
    assert "name" in first_node
    assert "label" in first_node

    # Query community without explicit id (defaults to 0)
    res_default = engine.execute_graph_query("community:", limit=10)
    assert res_default["match_count"] == res0["match_count"]

    # Query non-existent community ID
    res_none = engine.execute_graph_query("community:999", limit=10)
    assert res_none["match_count"] == 0
    assert len(res_none["nodes"]) == 0
    assert len(res_none["edges"]) == 0
