#!/usr/bin/env python3
"""
Unit tests for Pure-Python Louvain Modularity Optimization Community Detection (Issue 250).
Validates mathematical modularity Q, two-phase convergence, resolution parameter,
Zachary's Karate Club topology, and weighted graph partitioning.
"""

import os
import sys
from typing import Dict, List, Tuple

import pytest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src")),
    )

from core.structures import LouvainCommunityDetector, detect_louvain_communities


def test_empty_and_isolated_nodes() -> None:
    detector = LouvainCommunityDetector()

    # Empty graph
    assert detector.detect({}) == {}
    assert detector.modularity({}, {}) == 0.0

    # Isolated nodes (no edges)
    adj_isolated = {"n1": {}, "n2": {}, "n3": {}}
    res = detector.detect(adj_isolated)
    assert len(set(res.values())) == 3
    assert detector.modularity(adj_isolated, res) == 0.0


def test_single_edge() -> None:
    detector = LouvainCommunityDetector()
    adj = {
        "A": {"B": 1.0},
        "B": {"A": 1.0},
    }
    res = detector.detect(adj)
    # A and B should be in the same community
    assert res["A"] == res["B"]
    q = detector.modularity(adj, res)
    assert pytest.approx(q, abs=1e-5) == 0.0


def test_two_disjoint_cliques() -> None:
    """Two K5 complete graphs with no edges between them."""
    detector = LouvainCommunityDetector()
    nodes_a = [f"A{i}" for i in range(5)]
    nodes_b = [f"B{i}" for i in range(5)]
    all_nodes = nodes_a + nodes_b

    adj: Dict[str, Dict[str, float]] = {n: {} for n in all_nodes}
    for i, u in enumerate(nodes_a):
        for v in nodes_a[i + 1 :]:
            adj[u][v] = 1.0
            adj[v][u] = 1.0

    for i, u in enumerate(nodes_b):
        for v in nodes_b[i + 1 :]:
            adj[u][v] = 1.0
            adj[v][u] = 1.0

    partition = detector.detect(adj)
    assert len(set(partition.values())) == 2
    # All A nodes share one community, all B nodes share another
    a_comm = partition[nodes_a[0]]
    b_comm = partition[nodes_b[0]]
    assert a_comm != b_comm
    for u in nodes_a:
        assert partition[u] == a_comm
    for u in nodes_b:
        assert partition[u] == b_comm

    q = detector.modularity(adj, partition)
    # Disjoint symmetric cliques have Q = 1 - 1/2 = 0.5
    assert pytest.approx(q, abs=1e-2) == 0.5


def test_two_cliques_with_weak_bridge() -> None:
    """Two K5 cliques connected by a single weak bridge edge."""
    nodes_a = [f"A{i}" for i in range(5)]
    nodes_b = [f"B{i}" for i in range(5)]
    edges: List[Tuple[str, str, float]] = []

    for i, u in enumerate(nodes_a):
        for v in nodes_a[i + 1 :]:
            edges.append((u, v, 2.0))

    for i, u in enumerate(nodes_b):
        for v in nodes_b[i + 1 :]:
            edges.append((u, v, 2.0))

    # Weak bridge
    edges.append(("A0", "B0", 0.1))

    partition = detect_louvain_communities(nodes_a + nodes_b, edges)
    assert len(set(partition.values())) == 2
    assert partition["A1"] == partition["A2"]
    assert partition["B1"] == partition["B2"]
    assert partition["A1"] != partition["B1"]


def test_weighted_graph_clustering() -> None:
    """Tests that strong weights govern community boundaries."""
    # Graph: A-B (w=10), B-C (w=10), C-A (w=10), C-D (w=0.1), D-E (w=10), E-F (w=10), F-D (w=10)
    edges = [
        ("A", "B", 10.0),
        ("B", "C", 10.0),
        ("C", "A", 10.0),
        ("C", "D", 0.1),
        ("D", "E", 10.0),
        ("E", "F", 10.0),
        ("F", "D", 10.0),
    ]
    nodes = ["A", "B", "C", "D", "E", "F"]
    partition = detect_louvain_communities(nodes, edges)

    assert partition["A"] == partition["B"] == partition["C"]
    assert partition["D"] == partition["E"] == partition["F"]
    assert partition["A"] != partition["D"]


def test_resolution_parameter() -> None:
    """High resolution yields more granular communities; low resolution merges."""
    # Ring of four triangles
    # (A1, A2, A3) - (B1, B2, B3) - (C1, C2, C3) - (D1, D2, D3)
    edges = [
        # Triangle A
        ("A1", "A2", 2.0),
        ("A2", "A3", 2.0),
        ("A3", "A1", 2.0),
        # Triangle B
        ("B1", "B2", 2.0),
        ("B2", "B3", 2.0),
        ("B3", "B1", 2.0),
        # Triangle C
        ("C1", "C2", 2.0),
        ("C2", "C3", 2.0),
        ("C3", "C1", 2.0),
        # Bridges
        ("A3", "B1", 0.5),
        ("B3", "C1", 0.5),
    ]
    nodes = [f"{prefix}{i}" for prefix in ("A", "B", "C") for i in (1, 2, 3)]

    detector = LouvainCommunityDetector()
    adj: Dict[str, Dict[str, float]] = {n: {} for n in nodes}
    for u, v, w in edges:
        adj[u][v] = w
        adj[v][u] = w

    # Default resolution (1.0)
    p_default = detector.detect(adj, resolution=1.0)
    # High resolution (3.0): promotes smaller communities
    p_high = detector.detect(adj, resolution=3.0)
    # Low resolution (0.1): promotes larger communities
    p_low = detector.detect(adj, resolution=0.1)

    num_default = len(set(p_default.values()))
    num_high = len(set(p_high.values()))
    num_low = len(set(p_low.values()))

    assert num_high >= num_default
    assert num_default >= num_low


def test_zachary_karate_club() -> None:
    """
    Standard network benchmark: Zachary's Karate Club (34 vertices, 78 edges).
    Validates that Louvain partitions it into 2 to 5 communities with Q > 0.35.
    """
    karate_edges = [
        (1, 2),
        (1, 3),
        (1, 4),
        (1, 5),
        (1, 6),
        (1, 7),
        (1, 8),
        (1, 9),
        (1, 11),
        (1, 12),
        (1, 13),
        (1, 14),
        (1, 18),
        (1, 20),
        (1, 22),
        (1, 32),
        (2, 3),
        (2, 4),
        (2, 8),
        (2, 14),
        (2, 18),
        (2, 20),
        (2, 22),
        (2, 31),
        (3, 4),
        (3, 8),
        (3, 9),
        (3, 10),
        (3, 14),
        (3, 28),
        (3, 29),
        (3, 33),
        (4, 8),
        (4, 13),
        (4, 14),
        (5, 7),
        (5, 11),
        (6, 7),
        (6, 11),
        (6, 17),
        (7, 17),
        (9, 31),
        (9, 33),
        (9, 34),
        (10, 34),
        (14, 34),
        (15, 33),
        (15, 34),
        (16, 33),
        (16, 34),
        (19, 33),
        (19, 34),
        (20, 34),
        (21, 33),
        (21, 34),
        (23, 33),
        (23, 34),
        (24, 26),
        (24, 28),
        (24, 30),
        (24, 33),
        (24, 34),
        (25, 26),
        (25, 28),
        (25, 32),
        (26, 32),
        (27, 30),
        (27, 34),
        (28, 34),
        (29, 32),
        (29, 34),
        (30, 33),
        (30, 34),
        (31, 33),
        (31, 34),
        (32, 33),
        (32, 34),
        (33, 34),
    ]
    nodes = [str(i) for i in range(1, 35)]
    edges = [(str(u), str(v), 1.0) for u, v in karate_edges]

    detector = LouvainCommunityDetector()
    adj: Dict[str, Dict[str, float]] = {n: {} for n in nodes}
    for u, v, w in edges:
        adj[u][v] = w
        adj[v][u] = w

    partition = detector.detect(adj, seed=42)
    num_comms = len(set(partition.values()))
    assert 2 <= num_comms <= 5

    q = detector.modularity(adj, partition)
    # Typical modularity for Zachary Karate Club with Louvain is ~0.38 - 0.42
    assert q > 0.35


def test_deterministic_seed() -> None:
    """Ensures deterministic outputs when seed is provided."""
    nodes = [f"N{i}" for i in range(20)]
    edges = [(f"N{i}", f"N{(i + 1) % 20}", 1.0) for i in range(20)] + [
        (f"N{i}", f"N{(i + 3) % 20}", 0.5) for i in range(20)
    ]

    p1 = detect_louvain_communities(nodes, edges, seed=123)
    p2 = detect_louvain_communities(nodes, edges, seed=123)
    assert p1 == p2
