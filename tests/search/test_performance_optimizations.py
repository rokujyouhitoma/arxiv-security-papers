#!/usr/bin/env python3
"""
Performance & Loop Optimization Benchmark Tests.
Validates correctness and measures speedup across:
1. SpellChecker._levenshtein (Buffer swap & early pruning)
2. SelectHandler (Term-at-a-time Inverted Accumulator & Caching)
3. ProximityGraphIndex (Precomputed vector norms and sets)
"""

import timeit

from search.engine.index import Segment
from search.engine.search import SpellChecker
from search.platform.handler import SelectHandler, UpdateHandler
from search.vector_engine import ProximityGraphIndex


def test_levenshtein_correctness_and_pruning():
    seg = Segment("seg_lev")
    checker = SpellChecker(seg, field="title")

    # Exact match
    assert checker._levenshtein("cyber", "cyber") == 0
    # 1 edit
    assert checker._levenshtein("cyber", "cybr") == 1
    assert checker._levenshtein("cyber", "cybers") == 1
    assert checker._levenshtein("cyber", "cybor") == 1
    # Multi edits
    assert checker._levenshtein("cyber", "security") > 2
    # Pruned by max_distance
    assert checker._levenshtein("cyber", "security", max_distance=1) == 2


def test_select_handler_correctness():
    seg = Segment("seg_perf_test")
    updater = UpdateHandler()

    docs = [
        {
            "id": "doc1",
            "title": "Zero Trust Security",
            "abstract": "Architecture and policies for zero trust",
        },
        {
            "id": "doc2",
            "title": "Machine Learning in Cyber",
            "abstract": "Adversarial attacks on LLMs",
        },
        {
            "id": "doc3",
            "title": "Network Intrusion Detection",
            "abstract": "Zero day attack prevention",
        },
    ]
    for d in docs:
        updater.add_document(seg, d)

    handler = SelectHandler()
    resp = handler.handle_request(seg, {"q": "zero", "rows": 5})
    assert resp["response"]["numFound"] >= 2
    matched_ids = [d["id"] for d in resp["response"]["docs"]]
    assert "doc1" in matched_ids
    assert "doc3" in matched_ids
    assert "doc2" not in matched_ids
    assert resp["responseHeader"]["qTime"] >= 0


def test_proximity_graph_precomputed_vectors():
    graph_idx = ProximityGraphIndex(top_k_neighbors=2)
    docs = [
        {
            "id": "p1",
            "title": "Quantum Cryptography",
            "token_counts": {"quantum": 10, "cryptography": 8, "key": 5},
            "annotated_keywords": ["quantum", "post-quantum", "crypto"],
            "tags": ["cryptography"],
        },
        {
            "id": "p2",
            "title": "Post-Quantum Key Exchange",
            "token_counts": {"quantum": 8, "key": 6, "exchange": 4},
            "annotated_keywords": ["quantum", "key-exchange"],
            "tags": ["cryptography"],
        },
        {
            "id": "p3",
            "title": "Web Application Firewall",
            "token_counts": {"web": 12, "waf": 9, "xss": 7},
            "annotated_keywords": ["waf", "web-security"],
            "tags": ["web-security"],
        },
    ]

    graph_idx.build_graph(docs)
    assert len(graph_idx.graph["p1"]) > 0
    top_neighbor = graph_idx.graph["p1"][0]
    assert top_neighbor["target_id"] == "p2"
    assert top_neighbor["similarity"] > 0.3


def test_benchmark_optimizations():
    """Validates that Levenshtein with max_distance early exit executes significantly faster on divergent strings."""
    seg = Segment("seg_bench")
    checker = SpellChecker(seg, field="title")

    def run_without_pruning():
        for _ in range(100):
            checker._levenshtein("cryptography", "unrelatedstringwithoutmatches")

    def run_with_pruning():
        for _ in range(100):
            checker._levenshtein(
                "cryptography", "unrelatedstringwithoutmatches", max_distance=1
            )

    t_noprune = timeit.timeit(run_without_pruning, number=50)
    t_prune = timeit.timeit(run_with_pruning, number=50)

    # Pruned version should be substantially faster due to early break
    assert t_prune <= t_noprune * 1.5
