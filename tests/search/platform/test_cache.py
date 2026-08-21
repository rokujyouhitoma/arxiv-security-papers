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
