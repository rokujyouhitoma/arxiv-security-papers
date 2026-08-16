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
    ProximityGraphIndex,
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


def test_proximity_graph_index():
    prox = ProximityGraphIndex(top_k_neighbors=2)
    doc1 = {
        "id": "doc1",
        "title": "Acoustic Malware Attack",
        "description": "Audio side channel",
        "tags": ["cs.CR"],
        "annotated_keywords": [
            "マルウェア・脅威解析",
            "サイドチャネル・組込みセキュリティ",
        ],
        "token_counts": {"acoustic": 2, "malware": 3, "attack": 1},
    }
    doc2 = {
        "id": "doc2",
        "title": "Acoustic Keylogger Detection",
        "description": "Defense for audio side channel",
        "tags": ["cs.CR"],
        "annotated_keywords": ["サイドチャネル・組込みセキュリティ"],
        "token_counts": {"acoustic": 2, "keylogger": 1, "detection": 1},
    }
    doc3 = {
        "id": "doc3",
        "title": "Quantum Key Distribution",
        "description": "Post quantum crypto",
        "tags": ["quant-ph"],
        "annotated_keywords": ["暗号・プライバシー技術"],
        "token_counts": {"quantum": 3, "crypto": 2},
    }

    prox.build_graph([doc1, doc2, doc3])
    neighbors_1 = prox.get_neighbors("doc1")
    assert len(neighbors_1) >= 1
    assert neighbors_1[0]["target_id"] == "doc2"
    assert neighbors_1[0]["similarity"] > 0

    mermaid_str = prox.generate_mermaid_graph("doc1", "Acoustic Malware Attack")
    assert "flowchart TD" in mermaid_str
    assert "doc2" in mermaid_str


def test_vector_engine_get_related_papers():
    engine = VectorEngine()
    # Test on existing index
    if engine.documents:
        first_id = engine.documents[0]["id"]
        res = engine.get_related_papers(first_id)
        assert res["status"] == "success"
        assert "related_papers" in res
        assert "mermaid_graph" in res


def test_multi_field_schema_postings():
    from search.field_schema import MultiFieldPostingsIndex

    idx = MultiFieldPostingsIndex()
    idx.add_field_tokens("doc1", "title", ["rapidpen", "penetration", "testing"])
    idx.add_field_tokens("doc1", "author", ["tohru", "nakatani"])
    idx.add_field_tokens("doc2", "title", ["malware", "analysis"])
    idx.add_field_tokens("doc2", "author", ["john", "doe"])
    idx.compute_field_statistics(2)

    # Postings check
    postings = idx.get_postings("author", "nakatani")
    assert len(postings) == 1
    assert postings[0][0] == "doc1"
    assert postings[0][1] == [1]

    # Prefix search
    pref_matches = idx.search_prefix("author", "nakat")
    assert "doc1" in pref_matches

    # Fuzzy search
    fuzz_matches = idx.search_fuzzy("author", "nakatany", max_distance=1)
    assert "doc1" in fuzz_matches


def test_search_analyzer():
    from search.analyzer import SearchAnalyzer

    analyzer = SearchAnalyzer()
    tokens = analyzer.tokenize("RapidPen ペネトレーションテスト 脆弱性")
    assert "rapidpen" in tokens
    assert "ペネトレーションテスト" in tokens

    offsets = analyzer.tokenize_with_offsets("RapidPen malware test")
    assert len(offsets) >= 3
    assert offsets[0].text == "rapidpen"
    assert offsets[0].start == 0


def test_query_parser():
    from search.query_parser import EnterpriseQueryParser

    parser = EnterpriseQueryParser()
    clauses = parser.parse('author:Nakatani +title:malware "deep learning"~2 pen* sound~1')
    assert len(clauses) >= 5

    c_author = next(c for c in clauses if c.field == "author")
    assert c_author.term == "Nakatani"

    c_title = next(c for c in clauses if c.field == "title")
    assert c_title.term == "malware"
    assert c_title.is_required is True

    c_phrase = next(c for c in clauses if c.is_phrase)
    assert c_phrase.term == "deep learning"
    assert c_phrase.phrase_slop == 2

    c_pref = next(c for c in clauses if c.is_prefix)
    assert c_pref.term == "pen"

    c_fuzz = next(c for c in clauses if c.is_fuzzy)
    assert c_fuzz.term == "sound"


def test_dynamic_highlighter():
    from search.highlighter import DynamicHighlighter

    hl = DynamicHighlighter()
    text = "This paper presents RapidPen, an automated penetration testing tool."
    res = hl.highlight(text, ["RapidPen", "penetration"])
    assert '<mark class="highlight">' in res
    assert "</mark>" in res
    assert "RapidPen" in res


def test_enterprise_author_and_field_search():
    engine = VectorEngine()
    # Test query parsing and search
    results, profile = engine.search_with_profile("author:Nakatani", top_k=5)
    assert isinstance(results, list)
    assert profile["total_ms"] >= 0
