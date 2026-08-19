#!/usr/bin/env python3
"""
Comprehensive Unit Tests for Search Subpackages to boost coverage to 80%+.
"""

import tempfile

from search.core.search.collector import TopDocsCollector
from search.core.search.query import (
    BooleanQuery,
    FuzzyQuery,
    PhraseQuery,
    PrefixQuery,
    TermQuery,
)
from search.core.store.directory import FSDirectory, RAMDirectory
from search.core.store.segment import SegmentInfo
from search.ingestion.faceted_index import FacetedIndex
from search.ingestion.fm_index import FMIndex
from search.server.cache.solr_cache import FilterCache, LRUCache, QueryResultCache


def test_directory_and_segment():
    # RAM Directory
    ram_dir = RAMDirectory()
    assert ram_dir.list_all() == []
    ram_dir.write_bytes("test.bin", b"hello world")
    assert ram_dir.file_exists("test.bin")
    assert ram_dir.read_bytes("test.bin") == b"hello world"
    assert "test.bin" in ram_dir.list_all()
    ram_dir.delete_file("test.bin")
    assert not ram_dir.file_exists("test.bin")

    # FS Directory
    with tempfile.TemporaryDirectory() as tmpdir:
        fs_dir = FSDirectory(tmpdir)
        fs_dir.write_bytes("seg1.bin", b"segment data")
        assert fs_dir.file_exists("seg1.bin")
        assert fs_dir.read_bytes("seg1.bin") == b"segment data"
        assert "seg1.bin" in fs_dir.list_all()
        fs_dir.delete_file("seg1.bin")
        assert not fs_dir.file_exists("seg1.bin")

    # Segment Info
    seg = SegmentInfo(segment_id="_0", doc_count=100)
    assert seg.segment_id == "_0"
    assert seg.doc_count == 100
    assert repr(seg).startswith("SegmentInfo")


def test_query_types_and_collectors():
    tq = TermQuery("title", "security")
    assert tq.field == "title"
    assert tq.term == "security"
    assert "TermQuery" in repr(tq)

    pq = PhraseQuery("title", ["zero", "trust"], slop=1)
    assert pq.field == "title"
    assert len(pq.terms) == 2
    assert pq.slop == 1

    pre_q = PrefixQuery("title", "sec")
    assert pre_q.prefix == "sec"

    fq = FuzzyQuery("title", "secrity", max_edits=2)
    assert fq.max_edits == 2

    bq = BooleanQuery()
    bq.add(tq, is_required=True)
    bq.add(pq, is_required=False)
    assert len(bq.clauses) == 2
    assert "BooleanQuery" in repr(bq)
    assert "BooleanClause" in repr(bq.clauses[0])

    # Collector
    collector = TopDocsCollector(top_k=2)
    collector.collect("d1", 5.0)
    collector.collect("d2", 10.0)
    collector.collect("d3", 2.0)
    top_docs = collector.get_top_docs()
    assert top_docs.total_hits == 3
    assert len(top_docs.score_docs) == 2
    assert top_docs.max_score == 10.0
    assert repr(top_docs.score_docs[0]).startswith("ScoreDoc")


def test_fm_index_advanced():
    text = "abracadabra$malware_analysis_and_zero_trust_security"
    fm = FMIndex(text)
    assert fm.count_substring("abra") >= 2
    assert fm.count_substring("zero_trust") == 1
    assert fm.count_substring("nonexistent") == 0
    assert fm.count_substring("") == 0

    # Large text for binary search path (len > 1000)
    large_text = (
        "zero_trust_architecture_quantum_resistant_crypto_" * 30
    ) + "end_token"
    fm_large = FMIndex(large_text)
    assert fm_large.count_substring("quantum") == 30
    assert fm_large.count_substring("end_token") == 1
    assert fm_large.count_substring("missing_string") == 0


def test_faceted_index_advanced():
    fi = FacetedIndex()
    fi.add_document("doc_1", "2026-02-15", ["cs.CR", "cryptography"], ["quantum"])
    fi.add_document("doc_2", "2026-01-10", ["cs.CR"], ["network"])
    fi.add_document("doc_3", "2025-05-20", ["cs.AI"], ["fuzzing"])

    assert fi.filter(category="cs.CR") == {"doc_1", "doc_2"}
    assert fi.filter(year="2026") == {"doc_1", "doc_2"}
    assert fi.filter(tag="cryptography") == {"doc_1"}
    assert fi.filter(domain="quantum") == {"doc_1"}


def test_solr_lru_and_filter_cache():
    cache = LRUCache(max_size=2)
    cache.put("q1", {"docs": [1]})
    cache.put("q2", {"docs": [2]})
    assert cache.get("q1") == {"docs": [1]}
    cache.put("q3", {"docs": [3]})
    assert cache.get("q2") is None  # Evicted
    assert cache.stats()["size"] == 2

    fq_cache = FilterCache(max_size=2)
    fq_cache.put_filter_docs("cat:cs.CR", {"doc_1", "doc_2"})
    assert fq_cache.get_filter_docs("cat:cs.CR") == {"doc_1", "doc_2"}
    assert fq_cache.get_filter_docs("unknown") is None

    res_cache = QueryResultCache(max_size=2)
    res_cache.put_results("q_zero", [{"id": "d1"}])
    assert res_cache.get_results("q_zero") == [{"id": "d1"}]


def test_dynamic_highlighter_coverage():
    from search.presentation.highlighter import DynamicHighlighter

    hl = DynamicHighlighter(snippet_length=50)

    # Empty cases
    assert hl.highlight("", ["sec"]) == ""
    assert hl.highlight("some text", []) == "some text"
    assert hl.highlight("some text", ["a"]) == "some text"

    # Match case
    text = "Zero Trust Architecture enforces continuous verification on all network endpoints."
    res = hl.highlight(text, ["Zero", "Trust"])
    assert '<mark class="highlight">Zero</mark>' in res

    # Document highlight
    doc = {
        "title": "Quantum Resistance in Zero Trust",
        "description": "Zero Trust network mechanisms with post-quantum cryptography.",
        "other": 123,
    }
    hl_doc = hl.highlight_document(doc, ["Zero", "Trust"])
    assert "title" in hl_doc
    assert "description" in hl_doc


def test_vector_engine_methods_coverage():
    from search.vector_engine import VectorEngine

    ve = VectorEngine()
    ve.avg_doc_len = 10.0
    ve.idf = {"zero": 1.5, "trust": 2.0}

    # BM25 score test
    mock_doc = {
        "id": "doc1",
        "tokens": ["zero", "trust", "network", "security"],
        "token_counts": {"zero": 1, "trust": 1, "network": 1, "security": 1},
    }
    score = ve.calculate_bm25_score(["zero", "trust"], mock_doc)
    assert score > 0.0

    # FM Index score test
    mock_doc2 = {
        "id": "doc2",
        "title": "Zero Trust Network",
        "description": "Comprehensive Security Architecture",
        "authors": ["Alice"],
        "annotated_keywords": ["zero-trust"],
    }
    fm_score = ve.calculate_fm_index_score(["zero", "trust"], mock_doc2)
    assert fm_score > 0.0

    # Recency boost test
    assert ve.calculate_recency_boost("2026-02-15") >= 1.0
    assert ve.calculate_recency_boost("") == 1.0
    assert ve.calculate_recency_boost("invalid-date") == 1.0

    # Extract field value staticmethod
    raw_okf = "title: 'Quantum Key Distribution'\ndescription: Advanced QKD system"
    t_val = VectorEngine._extract_field_value(r"^title:\s*[\"']?(.*?)[\"']?$", raw_okf)
    assert t_val == "Quantum Key Distribution"


def test_tokenizer_and_analysis_coverage():
    from search.core.analysis.tokenizer import StandardTokenizer, Token

    tok = StandardTokenizer()
    # Empty
    assert tok.tokenize("") == []

    # English & Japanese with CJK bigrams
    tokens = tok.tokenize("Zero-Trust ゼロトラスト技術 security_2026")
    assert len(tokens) > 0
    assert any(t.text == "Zero-Trust" for t in tokens)
    assert any(t.text == "ゼロトラスト技術" for t in tokens)
    # Bigram check
    assert any(t.text == "ゼロ" for t in tokens)

    # Token repr
    t_obj = Token("test", 0, 4, 1)
    assert repr(t_obj).startswith("Token")


def test_stored_fields_and_translator_edge_cases():
    from fetcher.transformer.translator import clean_text, translate_title_ja
    from search.core.index.stored_fields import StoredFields

    sf = StoredFields()
    assert sf.count() == 0
    assert sf.all_documents() == []

    sf.put_document("doc1", {"title": "Paper 1"})
    assert sf.count() == 1
    assert sf.get_document("doc1") == {"title": "Paper 1"}
    assert len(sf.all_documents()) == 1

    # Translator edge cases
    assert clean_text(None) == ""
    assert clean_text("") == ""
    assert translate_title_ja("") == ""

    from search.utils import extract_abstract_from_okf

    # Abstract extract quotes fallback
    doc_with_quote = "> This is an executive paper quote.\n> Second line of quote."
    assert (
        extract_abstract_from_okf(doc_with_quote)
        == "This is an executive paper quote. Second line of quote."
    )
    assert extract_abstract_from_okf("No abstract or quotes here.") == ""
