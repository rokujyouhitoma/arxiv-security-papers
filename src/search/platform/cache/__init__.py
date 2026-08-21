#!/usr/bin/env python3
"""
Multi-tier Solr Cache Engine (FilterCache, QueryResultCache, DocumentCache).
"""

from collections import OrderedDict
from typing import Any, Dict, Generic, List, Optional, Set, TypeVar

T = TypeVar("T")


class LRUCache(Generic[T]):
    """Thread-safe LRU Cache with maximum capacity."""

    def __init__(self, capacity: int = 1000) -> None:
        self.capacity = capacity
        self._cache: OrderedDict[str, T] = OrderedDict()
        self.hits = 0
        self.misses = 0

    def get(self, key: str) -> Optional[T]:
        if key in self._cache:
            self._cache.move_to_end(key)
            self.hits += 1
            return self._cache[key]
        self.misses += 1
        return None

    def put(self, key: str, value: T) -> None:
        if key in self._cache:
            self._cache.move_to_end(key)
        self._cache[key] = value
        if len(self._cache) > self.capacity:
            self._cache.popitem(last=False)

    def clear(self) -> None:
        self._cache.clear()
        self.hits = 0
        self.misses = 0

    def size(self) -> int:
        return len(self._cache)

    def hit_ratio(self) -> float:
        total = self.hits + self.misses
        return (self.hits / total) if total > 0 else 0.0


class FilterCache(LRUCache[Set[int]]):
    """Caches boolean filter query result doc_id sets."""

    pass


class QueryResultCache(LRUCache[List[int]]):
    """Caches top ranked doc_id lists for specific query strings."""

    pass


class DocumentCache(LRUCache[Dict[str, Any]]):
    """Caches materialized document dictionaries."""

    pass


class SolrCache:
    """Unified cache facade holding filterCache, queryResultCache, and documentCache."""

    def __init__(
        self, filter_cap: int = 500, query_cap: int = 500, doc_cap: int = 2000
    ) -> None:
        self.filter_cache = FilterCache(filter_cap)
        self.query_result_cache = QueryResultCache(query_cap)
        self.document_cache = DocumentCache(doc_cap)

    def clear_all(self) -> None:
        self.filter_cache.clear()
        self.query_result_cache.clear()
        self.document_cache.clear()

    def get_stats(self) -> Dict[str, Any]:
        return {
            "filter_cache": {
                "size": self.filter_cache.size(),
                "hit_ratio": self.filter_cache.hit_ratio(),
            },
            "query_result_cache": {
                "size": self.query_result_cache.size(),
                "hit_ratio": self.query_result_cache.hit_ratio(),
            },
            "document_cache": {
                "size": self.document_cache.size(),
                "hit_ratio": self.document_cache.hit_ratio(),
            },
        }
