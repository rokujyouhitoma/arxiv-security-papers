"""
Unit tests for SynonymExpander, FMIndex, and 5-Method Multi-Engine VectorEngine
"""

import os
import sys

from synonym_expander import SynonymExpander
from vector_engine import FMIndex, VectorEngine, extract_abstract_from_okf

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )


def test_synonym_expander():
    expander = SynonymExpander()

    # Test Japanese to English penetration testing expansion
    expanded_pentest = expander.expand_query("ペンテスト")
    assert "penetration testing" in expanded_pentest or "pentest" in expanded_pentest
    assert "exploit" in expanded_pentest

    # Test autonomous vehicle expansion
    expanded_av = expander.expand_query("自動運転")
    assert "autonomous vehicle" in expanded_av or "autonomous vehicles" in expanded_av


def test_fm_index_substring_search():
    fm = FMIndex("マルウェア解析と自動運転セキュリティの脆弱性")
    count1 = fm.count_substring("マルウェア")
    count2 = fm.count_substring("自動運転")
    assert count1 == 1
    assert count2 == 1


def test_extract_abstract_from_okf():
    sample_okf = """---
title: "Test Paper"
---
# Test Paper
### Abstract (原文)
> AI agents are rapidly gaining capabilities in exploitation.
> Specifically, Claude Mythos Preview achieved state of the art results.
"""
    abstract = extract_abstract_from_okf(sample_okf)
    assert "AI agents are rapidly gaining" in abstract
    assert "Claude Mythos Preview" in abstract


def test_vector_engine_multi_engine_search():
    engine = VectorEngine()
    results = engine.search("マルウェア解析", top_k=3)
    assert isinstance(results, list)
    if results:
        assert "score" in results[0]
        assert "path" in results[0]
        assert "annotated_keywords" in results[0]


def test_vector_engine_abstract_indexing_mock(tmp_path):
    # Test that a document with a keyword only in its abstract is correctly indexed and retrieved
    engine = VectorEngine(workspace_dir=str(tmp_path))
    engine.documents = [
        {
            "id": "2026.0001",
            "title": "Dual-Use Benchmark for AI Agents",
            "description": "AIエージェントの能力評価",
            "tags": ["cs.CR"],
            "annotated_keywords": ["ベンチマーク"],
            "title_tokens": engine.tokenize("Dual-Use Benchmark for AI Agents"),
            "desc_tokens": engine.tokenize("AIエージェントの能力評価"),
            "tags_tokens": engine.tokenize("cs.CR"),
            "keywords_tokens": engine.tokenize("ベンチマーク"),
            "abstract_tokens": engine.tokenize(
                "We evaluate Claude Mythos Preview on complex memory safety bugs."
            ),
            "tokens": engine.tokenize(
                "Dual-Use Benchmark AI Agents Claude Mythos Preview"
            ),
            "token_counts": {"claude": 1, "mythos": 1, "preview": 1, "benchmark": 1},
            "path": "outputs/okf_papers/2026-05-11/2026.0001.md",
        }
    ]
    engine.documents_by_id = {d["id"]: d for d in engine.documents}
    engine.inverted_index["mythos"] = ["2026.0001"]
    engine.idf["mythos"] = 2.5

    results = engine.search("Mythos", top_k=5)
    assert len(results) >= 1
    assert results[0]["id"] == "2026.0001"
    assert results[0]["score"] > 0
