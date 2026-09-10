#!/usr/bin/env python3
"""
Unit tests for core DisjointSet (Union-Find) and CTI Graph cluster detection.
"""

from core.structures.disjoint_set import DisjointSet
from graph.engine import PropertyGraphEngine
from graph.traversal import find_connected_threat_clusters


def test_disjoint_set_basic_operations() -> None:
    dsu: DisjointSet[str] = DisjointSet()
    assert len(dsu) == 0
    assert dsu.component_count == 0

    assert dsu.add("T1059") is True
    assert dsu.add("T1059") is False
    assert len(dsu) == 1
    assert dsu.component_count == 1
    assert "T1059" in dsu
    assert "CVE-2024-1234" not in dsu

    dsu.add("CVE-2024-1234")
    assert dsu.component_count == 2
    assert dsu.connected("T1059", "CVE-2024-1234") is False

    # Union
    assert dsu.union("T1059", "CVE-2024-1234") is True
    assert dsu.component_count == 1
    assert dsu.connected("T1059", "CVE-2024-1234") is True
    assert dsu.component_size("T1059") == 2
    assert dsu.component_size("CVE-2024-1234") == 2

    # Redundant union
    assert dsu.union("T1059", "CVE-2024-1234") is False
    assert dsu.component_count == 1


def test_disjoint_set_transitive_clustering() -> None:
    # 3 clusters: {1, 2, 3}, {4, 5}, {6}
    dsu: DisjointSet[int] = DisjointSet([1, 2, 3, 4, 5, 6])
    assert len(dsu) == 6
    assert dsu.component_count == 6

    dsu.union(1, 2)
    dsu.union(2, 3)
    dsu.union(4, 5)

    assert dsu.component_count == 3
    assert dsu.connected(1, 3) is True
    assert dsu.connected(1, 4) is False
    assert dsu.connected(5, 6) is False

    comps = dsu.get_components()
    comp_sizes = sorted(len(s) for s in comps.values())
    assert comp_sizes == [1, 2, 3]


def test_disjoint_set_auto_registration_on_find() -> None:
    dsu: DisjointSet[str] = DisjointSet()
    # finding unknown element should auto-register it
    root = dsu.find("unknown_node")
    assert root == "unknown_node"
    assert "unknown_node" in dsu
    assert len(dsu) == 1
    assert dsu.component_count == 1


def test_disjoint_set_large_scale_stress() -> None:
    dsu: DisjointSet[int] = DisjointSet(range(1000))
    assert len(dsu) == 1000
    assert dsu.component_count == 1000

    # Chain merge 0..99
    for i in range(99):
        dsu.union(i, i + 1)

    assert dsu.component_size(0) == 100
    assert dsu.connected(0, 99) is True
    assert dsu.connected(0, 100) is False
    assert dsu.component_count == 901


def test_disjoint_set_clear() -> None:
    dsu: DisjointSet[int] = DisjointSet([1, 2, 3])
    dsu.clear()
    assert len(dsu) == 0
    assert dsu.component_count == 0


def test_cti_graph_connected_threat_clusters() -> None:
    engine = PropertyGraphEngine(memory_only=True)

    # Cluster A: APT29 -> T1059 -> CVE-2023-1111
    engine.add_vertex("APT29", label="ThreatActor")
    engine.add_vertex("T1059", label="AttackTechnique")
    engine.add_vertex("CVE-2023-1111", label="Vulnerability")

    # Cluster B: Lazarus -> T1071
    engine.add_vertex("Lazarus", label="ThreatActor")
    engine.add_vertex("T1071", label="AttackTechnique")

    # Cluster C: Isolated technique
    engine.add_vertex("T1566", label="AttackTechnique")

    # Edges for Cluster A
    engine.add_edge("APT29", "T1059", label="uses")
    engine.add_edge("T1059", "CVE-2023-1111", label="exploits")

    # Edges for Cluster B
    engine.add_edge("Lazarus", "T1071", label="uses")

    clusters = find_connected_threat_clusters(engine)
    assert len(clusters) == 3
    assert len(clusters[0]) == 3  # APT29 cluster
    assert len(clusters[1]) == 2  # Lazarus cluster
    assert len(clusters[2]) == 1  # T1566

    assert clusters[0] == {"APT29", "T1059", "CVE-2023-1111"}
    assert clusters[1] == {"Lazarus", "T1071"}
    assert clusters[2] == {"T1566"}

    # Filter by specific edge label
    uses_clusters = find_connected_threat_clusters(engine, edge_labels=["uses"])
    assert len(uses_clusters) == 4  # CVE-2023-1111 is now isolated without 'exploits'
