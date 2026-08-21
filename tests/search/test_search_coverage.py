#!/usr/bin/env python3
"""
Comprehensive Unit Tests for Search Subpackages to boost coverage to 80%+.
"""

import tempfile

from search.engine.index import Segment
from search.engine.search import (
    BooleanQuery,
    FuzzyQuery,
    Occur,
    PhraseQuery,
    TermQuery,
    TopDocsCollector,
    WildcardQuery,
)
from search.engine.store import FSDirectory, RAMDirectory
from search.platform.cache import LRUCache, SolrCache
from search.vector_engine import FacetedIndex, FMIndex


def test_directory_and_segment():
    # RAM Directory
    ram_dir = RAMDirectory()
    assert ram_dir.list_all() == []
    out = ram_dir.create_output("test.bin")
    out.write_string("hello world")
    ram_dir.save_output("test.bin", out)

    assert ram_dir.file_exists("test.bin")
    inp = ram_dir.open_input("test.bin")
    assert inp.read_string() == "hello world"
    assert "test.bin" in ram_dir.list_all()
    ram_dir.delete_file("test.bin")
    assert not ram_dir.file_exists("test.bin")

    # FS Directory
    with tempfile.TemporaryDirectory() as tmpdir:
        fs_dir = FSDirectory(tmpdir)
        fs_out = fs_dir.create_output("seg1.bin")
        fs_out.write_string("segment data")
        fs_dir.save_output("seg1.bin", fs_out)

        assert fs_dir.file_exists("seg1.bin")
        fs_inp = fs_dir.open_input("seg1.bin")
        assert fs_inp.read_string() == "segment data"
        assert "seg1.bin" in fs_dir.list_all()
        fs_dir.delete_file("seg1.bin")
        assert not fs_dir.file_exists("seg1.bin")

    # Segment
    seg = Segment(segment_id="_0")
    seg.doc_count = 100
    assert seg.segment_id == "_0"
    assert seg.doc_count == 100
    assert repr(seg).startswith("Segment")


def test_query_types_and_collectors():
    tq = TermQuery("title", "security")
    assert tq.field == "title"
    assert tq.term == "security"

    pq = PhraseQuery("title", ["zero", "trust"], slop=1)
    assert pq.field == "title"
    assert len(pq.terms) == 2
    assert pq.slop == 1

    wild_q = WildcardQuery("title", "sec*")
    assert wild_q.pattern == "sec*"

    fq = FuzzyQuery("title", "secrity", max_edits=2)
    assert fq.max_edits == 2

    bq = BooleanQuery()
    bq.add(tq, Occur.MUST)
    bq.add(pq, Occur.SHOULD)
    assert len(bq.clauses) == 2

    # Collector
    seg = Segment("seg_collector")
    seg.stored_fields.put(0, {"id": "d0"})
    seg.stored_fields.put(1, {"id": "d1"})
    seg.stored_fields.put(2, {"id": "d2"})
    collector = TopDocsCollector(top_k=2)
    doc_scores = {0: 5.0, 1: 10.0, 2: 2.0}
    top_docs = collector.collect(seg, doc_scores)
    assert top_docs.total_hits == 3
    assert len(top_docs.score_docs) == 2
    assert top_docs.score_docs[0].score == 10.0


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
    cache = LRUCache[dict](capacity=2)
    cache.put("q1", {"docs": [1]})
    cache.put("q2", {"docs": [2]})
    assert cache.get("q1") == {"docs": [1]}
    cache.put("q3", {"docs": [3]})
    assert cache.get("q2") is None
    assert cache.get("q3") == {"docs": [3]}

    solr_cache = SolrCache()
    solr_cache.filter_cache.put("fq1", {1, 2, 3})
    assert solr_cache.filter_cache.get("fq1") == {1, 2, 3}
