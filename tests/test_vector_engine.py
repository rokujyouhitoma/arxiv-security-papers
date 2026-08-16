"""
Unit tests for SynonymExpander, FMIndex, and Extended Multi-Stage RAG VectorEngine
"""

import os
import sys

from synonym_expander import SynonymExpander
from vector_engine import (
    CitationNetworkIndex,
    FacetedIndex,
    FMIndex,
    KnowledgeGraphIndex,
    QuerySemanticCache,
    RAPTORTreeIndex,
    VectorEngine,
    extract_abstract_from_okf,
)

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


def test_query_semantic_cache():
    cache = QuerySemanticCache(max_entries=10, similarity_threshold=0.6)
    cache.set(
        "malware analysis", ["malware", "analysis"], [{"id": "doc1"}], {"total_ms": 5.0}
    )

    # Exact Hit
    hit_exact = cache.get("malware analysis", ["malware", "analysis"])
    assert hit_exact is not None
    hit, prof = hit_exact
    assert hit[0]["id"] == "doc1"

    # Semantic Hit with similar tokens (Jaccard = 2/3 = 0.666 >= 0.6)
    hit_semantic = cache.get("malware analysis deep", ["malware", "analysis", "deep"])
    assert hit_semantic is not None

    stats = cache.get_stats()
    assert stats["hits"] >= 2
    assert stats["total_entries"] == 1


def test_faceted_index():
    facet = FacetedIndex()
    facet.add_document(
        "doc1", "2026-06-01", ["cs.CR", "malware"], ["マルウェア・脅威解析"]
    )
    facet.add_document("doc2", "2025-05-01", ["cs.AI"], ["LLM・AIセキュリティ"])

    # Filter by Year
    cand2026 = facet.filter(year="2026")
    assert cand2026 == {"doc1"}

    # Filter by Category
    cand_cr = facet.filter(category="cs.CR")
    assert cand_cr == {"doc1"}

    # Filter by Domain
    cand_domain = facet.filter(domain="マルウェア・脅威解析")
    assert cand_domain == {"doc1"}


def test_knowledge_graph_index():
    kg = KnowledgeGraphIndex()
    kg.add_entity("CVE-2026-001", "vulnerability", "CVE-2026-001", "paper1")
    kg.add_entity("SoundMalware", "attack", "SoundMalware", "paper1")
    kg.add_relationship("SoundMalware", "CVE-2026-001", "exploits", "paper1")

    subgraph = kg.get_neighbors("SoundMalware", max_depth=1)
    assert subgraph["root"] == "SoundMalware"
    assert len(subgraph["nodes"]) >= 1
    assert "paper1" in subgraph["related_papers"]


def test_citation_network_pagerank():
    cit = CitationNetworkIndex()
    cit.add_citation("paper1", "paper2")
    cit.add_citation("paper3", "paper2")

    ranks = cit.compute_pagerank(["paper1", "paper2", "paper3"], max_iter=10)
    assert ranks["paper2"] > ranks["paper1"]
    assert cit.get_score("paper2") > 0


def test_raptor_tree_index():
    raptor = RAPTORTreeIndex()
    docs = [
        {"id": "doc1", "annotated_keywords": ["マルウェア・脅威解析"]},
        {"id": "doc2", "annotated_keywords": ["LLM・AIセキュリティ"]},
    ]
    raptor.build_summary_tree(docs)
    summaries = raptor.search_clusters(["マルウェア"], top_k=1)
    assert len(summaries) == 1
    assert "マルウェア" in summaries[0]["domain"]


def test_vector_engine_multi_engine_search():
    engine = VectorEngine()
    results = engine.search("マルウェア解析", top_k=3)
    assert isinstance(results, list)
    if results:
        assert "score" in results[0]
        assert "path" in results[0]
        assert "annotated_keywords" in results[0]


def test_vector_engine_hybrid_pipeline():
    engine = VectorEngine()
    resp = engine.search_hybrid_pipeline("脱獄攻撃", top_k=3)
    assert "papers" in resp
    assert "profile" in resp
    assert "raptor_macro_summaries" in resp
    assert "cache_stats" in resp
    assert isinstance(resp["papers"], list)


def test_vector_engine_abstract_indexing_mock(tmp_path):
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
