#!/usr/bin/env python3
"""
Unit tests for Search Engine Evaluation Framework (IR Metrics & Benchmarking).
Tests Precision@K, Recall@K, F1-Score, MAP, MRR, NDCG@K, SearchEvaluator, and MCP Tool integration.
"""

import json
import os
import sys

if "src" not in sys.path:
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from observability_mcp_server import dispatch_rpc_request
from search.eval.dataset import DEFAULT_SECURITY_GOLD_STANDARD, EvaluationQuery
from search.eval.evaluator import SearchEvaluator
from search.eval.metrics import (
    compute_average_precision,
    compute_f1_score,
    compute_ndcg_at_k,
    compute_precision_at_k,
    compute_recall_at_k,
    compute_reciprocal_rank,
)


def test_precision_at_k():
    retrieved = ["doc1", "doc2", "doc3", "doc4", "doc5"]
    relevant = {"doc1", "doc3", "doc99"}

    # Top-5: doc1, doc3 are hits -> 2/5 = 0.4
    assert compute_precision_at_k(retrieved, relevant, k=5) == 0.4
    # Top-2: doc1 is hit -> 1/2 = 0.5
    assert compute_precision_at_k(retrieved, relevant, k=2) == 0.5
    # Top-1: doc1 is hit -> 1/1 = 1.0
    assert compute_precision_at_k(retrieved, relevant, k=1) == 1.0
    # Zero or empty
    assert compute_precision_at_k([], relevant, k=5) == 0.0
    assert compute_precision_at_k(retrieved, relevant, k=0) == 0.0


def test_recall_at_k():
    retrieved = ["doc1", "doc2", "doc3", "doc4", "doc5"]
    relevant = {"doc1", "doc3", "doc99"}  # Total 3 relevant

    # Top-5: 2 hits out of 3 total -> 2/3 ≈ 0.6667
    assert round(compute_recall_at_k(retrieved, relevant, k=5), 4) == 0.6667
    # Top-2: 1 hit out of 3 total -> 1/3 ≈ 0.3333
    assert round(compute_recall_at_k(retrieved, relevant, k=2), 4) == 0.3333
    # No relevant
    assert compute_recall_at_k(retrieved, set(), k=5) == 0.0


def test_f1_score():
    assert compute_f1_score(1.0, 1.0) == 1.0
    assert compute_f1_score(0.0, 0.5) == 0.0
    # P=0.5, R=0.5 -> F1=0.5
    assert compute_f1_score(0.5, 0.5) == 0.5
    # P=0.4, R=0.8 -> F1 = 2*(0.32)/(1.2) = 0.64/1.2 ≈ 0.5333
    assert round(compute_f1_score(0.4, 0.8), 4) == 0.5333


def test_average_precision():
    # Rank 1 (hit), Rank 2 (miss), Rank 3 (hit)
    # P@1 = 1/1 = 1.0, P@3 = 2/3 ≈ 0.6667 -> AP = (1.0 + 0.6667) / 2 = 0.8333
    retrieved = ["doc1", "doc2", "doc3"]
    relevant = {"doc1", "doc3"}
    ap = compute_average_precision(retrieved, relevant)
    assert round(ap, 4) == 0.8333


def test_reciprocal_rank():
    relevant = {"docA", "docB"}
    # Hit at rank 1 -> RR = 1.0
    assert compute_reciprocal_rank(["docA", "docX"], relevant) == 1.0
    # Hit at rank 2 -> RR = 0.5
    assert compute_reciprocal_rank(["docX", "docA"], relevant) == 0.5
    # Hit at rank 4 -> RR = 0.25
    assert compute_reciprocal_rank(["x1", "x2", "x3", "docB"], relevant) == 0.25
    # No hit -> 0.0
    assert compute_reciprocal_rank(["x1", "x2"], relevant) == 0.0


def test_ndcg_at_k():
    graded_rel = {"doc1": 3.0, "doc2": 2.0, "doc3": 1.0}

    # Perfect ranking: [doc1, doc2, doc3] -> NDCG = 1.0
    assert compute_ndcg_at_k(["doc1", "doc2", "doc3"], graded_rel, k=3) == 1.0

    # Suboptimal ranking: [doc3, doc2, doc1] -> NDCG < 1.0
    sub_ndcg = compute_ndcg_at_k(["doc3", "doc2", "doc1"], graded_rel, k=3)
    assert 0.0 < sub_ndcg < 1.0

    # Empty / disjoint
    assert compute_ndcg_at_k(["unrelated"], graded_rel, k=3) == 0.0


def test_search_evaluator_harness():
    queries = [
        EvaluationQuery("TQ1", "zero trust", "zero-trust", ["d1", "d2"], {"d1": 3.0, "d2": 2.0}),
        EvaluationQuery("TQ2", "quantum crypto", "crypto", ["d3"], {"d3": 3.0}),
    ]
    evaluator = SearchEvaluator(queries=queries, top_k=3)

    def mock_engine(q: str, k: int):
        if "zero" in q:
            return ["d1", "d2", "d99"][:k]
        return ["d3", "d98"][:k]

    result = evaluator.evaluate(mock_engine)
    summary = result["summary"]
    assert summary["num_queries"] == 2
    assert summary["MAP"] == 1.0
    assert summary["MRR"] == 1.0
    assert summary["mean_NDCG_at_k"] == 1.0
    assert summary["mean_precision_at_k"] >= 0.5
    assert summary["mean_recall_at_k"] == 1.0

    report = evaluator.generate_markdown_report(result)
    assert "# 検索エンジン評価レポート" in report
    assert "TQ1" in report
    assert "TQ2" in report


def test_mcp_evaluate_search_quality_tool():
    req = {
        "jsonrpc": "2.0",
        "id": 101,
        "method": "tools/call",
        "params": {
            "name": "evaluate_search_quality",
            "arguments": {"top_k": 5},
        },
    }
    resp = dispatch_rpc_request(req)
    assert resp is not None
    assert resp["id"] == 101
    content_text = resp["result"]["content"][0]["text"]
    data = json.loads(content_text)
    assert "summary" in data
    assert "MAP" in data["summary"]
    assert "MRR" in data["summary"]
    assert "markdown_report" in data
