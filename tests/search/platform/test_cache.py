"""
Tests for Multi-tier Solr Cache (src/search/platform/cache/).
"""

from search.platform.cache import LRUCache, SolrCache


def test_lru_cache_operations():
    cache = LRUCache[int](capacity=2)
    cache.put("k1", 100)
    cache.put("k2", 200)
    assert cache.get("k1") == 100
    cache.put("k3", 300)  # Evicts k2 (since k1 was accessed)
    assert cache.get("k2") is None
    assert cache.get("k3") == 300
    assert cache.size() == 2


def test_solr_cache_facade_and_stats():
    solr_cache = SolrCache(filter_cap=5, query_cap=5, doc_cap=10)
    solr_cache.filter_cache.put("fq_cat", {0, 1, 2})
    solr_cache.query_result_cache.put("q_sec", [0, 1])
    solr_cache.document_cache.put("doc_0", {"title": "Test Paper"})

    assert solr_cache.filter_cache.get("fq_cat") == {0, 1, 2}
    stats = solr_cache.get_stats()
    assert stats["filter_cache"]["size"] == 1
    assert stats["query_result_cache"]["size"] == 1

    solr_cache.clear_all()
    assert solr_cache.filter_cache.size() == 0


def test_filter_cache_roaring_bitmap_integration():
    from core.structures.roaring_bitmap import RoaringBitmap

    solr_cache = SolrCache(filter_cap=5)
    # Direct RoaringBitmap put
    bm1 = RoaringBitmap([10, 20, 30])
    solr_cache.filter_cache.put("fq_tag:crypto", bm1)
    retrieved = solr_cache.filter_cache.get("fq_tag:crypto")
    assert isinstance(retrieved, RoaringBitmap)
    assert retrieved == {10, 20, 30}

    # Iterable put auto-conversion
    solr_cache.filter_cache.put("fq_year:2026", [20, 30, 40])
    retrieved2 = solr_cache.filter_cache.get("fq_year:2026")
    assert isinstance(retrieved2, RoaringBitmap)
    assert retrieved2 == {20, 30, 40}

    # Bitwise intersection
    combined = retrieved & retrieved2
    assert isinstance(combined, RoaringBitmap)
    assert combined == {20, 30}
    assert 20 in combined
    assert 10 not in combined


def test_solr_cache_arc_integration():
    solr_cache = SolrCache(filter_cap=3, query_cap=3, doc_cap=5, use_arc=True)
    stats = solr_cache.get_stats()
    assert stats["use_arc"] is True

    solr_cache.filter_cache.put("fq_cat", {1, 2, 3})
    assert solr_cache.filter_cache.get("fq_cat") == {1, 2, 3}
    assert solr_cache.filter_cache.size() == 1

    solr_cache.query_result_cache.put("q_sec", [10, 20])
    assert solr_cache.query_result_cache.get("q_sec") == [10, 20]

    solr_cache.document_cache.put("doc_1", {"title": "ARC Paper"})
    assert solr_cache.document_cache.get("doc_1") == {"title": "ARC Paper"}

    solr_cache.clear_all()
    assert solr_cache.filter_cache.size() == 0
    assert solr_cache.query_result_cache.size() == 0
    assert solr_cache.document_cache.size() == 0
