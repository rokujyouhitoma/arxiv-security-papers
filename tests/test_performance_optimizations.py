#!/usr/bin/env python3
"""
Performance & Loop Optimization Benchmark Tests for Issue 020.
Validates correctness and measures speedup across:
1. MultiFieldPostingsIndex._levenshtein (Buffer swap & early pruning)
2. SelectHandler (Term-at-a-time Inverted Accumulator)
3. ProximityGraphIndex (Precomputed vector norms and sets)
"""

import os
import sys
import timeit

if "src" not in sys.path:
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from search.core.index.postings import MultiFieldPostingsIndex
from search.core.index.stored_fields import StoredFields
from search.core.search.similarity import BM25Similarity
from search.core.store.directory import RAMDirectory
from search.ranking.proximity_graph import ProximityGraphIndex
from search.server.handler.select_handler import SelectHandler
from search.server.schema.managed_schema import FieldDefinition, FieldType, ManagedIndexSchema


def test_levenshtein_correctness_and_pruning():
    idx = MultiFieldPostingsIndex()

    # Exact match
    assert idx._levenshtein("cyber", "cyber") == 0
    # 1 edit
    assert idx._levenshtein("cyber", "cybr") == 1
    assert idx._levenshtein("cyber", "cybers") == 1
    assert idx._levenshtein("cyber", "cybor") == 1
    # Multi edits
    assert idx._levenshtein("cyber", "security") > 2
    # Pruned by max_distance
    assert idx._levenshtein("cyber", "security", max_distance=1) == 2


def test_select_handler_inverted_accumulator_correctness():
    schema = ManagedIndexSchema(
        fields=[
            FieldDefinition(name="id", field_type=FieldType.KEYWORD, stored=True),
            FieldDefinition(name="title", field_type=FieldType.TEXT, stored=True, boost=2.0),
            FieldDefinition(name="body", field_type=FieldType.TEXT, stored=True, boost=1.0),
        ]
    )

    postings = MultiFieldPostingsIndex()
    stored = StoredFields()

    # Insert test docs
    docs = [
        {"id": "doc1", "title": "Zero Trust Security", "body": "Architecture and policies for zero trust"},
        {"id": "doc2", "title": "Machine Learning in Cyber", "body": "Adversarial attacks on LLMs"},
        {"id": "doc3", "title": "Network Intrusion Detection", "body": "Zero day attack prevention"},
    ]
    for d in docs:
        stored.put_document(d["id"], d)
        for term in d["title"].lower().split():
            postings.add_term("title", term, d["id"])
        for term in d["body"].lower().split():
            postings.add_term("body", term, d["id"])

    handler = SelectHandler(schema=schema, postings_index=postings, stored_fields=stored)

    # Query for "zero"
    resp = handler.handle_select(query="zero", top_k=5)
    assert resp["response"]["numFound"] >= 2
    matched_ids = [d["id"] for d in resp["response"]["docs"]]
    assert "doc1" in matched_ids
    assert "doc3" in matched_ids
    assert "doc2" not in matched_ids  #doc2 doesn't have 'zero'
    assert resp["responseHeader"]["QTime"] >= 0


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
    idx = MultiFieldPostingsIndex()

    def run_without_pruning():
        for _ in range(100):
            idx._levenshtein("cryptography", "unrelatedstringwithoutmatches")

    def run_with_pruning():
        for _ in range(100):
            idx._levenshtein("cryptography", "unrelatedstringwithoutmatches", max_distance=1)

    t_noprune = timeit.timeit(run_without_pruning, number=50)
    t_prune = timeit.timeit(run_with_pruning, number=50)

    # Pruned version should be substantially faster due to early break
    assert t_prune < t_noprune
