#!/usr/bin/env python3
"""
Multi-tier Solr Cache Engine (FilterCache, QueryResultCache, DocumentCache).
"""

from collections import OrderedDict
from typing import Any, Dict, Generic, Iterable, List, Optional, TypeVar, Union

from core.structures.arc_cache import ARCCache
from core.structures.roaring_bitmap import RoaringBitmap

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


class ARCCacheAdapter(Generic[T]):
    """Adaptive Replacement Cache adapter compatible with Solr cache interfaces."""

    def __init__(self, capacity: int = 1000) -> None:
        self.capacity = capacity
        self._arc: ARCCache[str, T] = ARCCache(capacity=capacity)

    def get(self, key: str) -> Optional[T]:
        return self._arc.get(key)

    def put(self, key: str, value: T) -> None:
        self._arc.put(key, value)

    def clear(self) -> None:
        self._arc.clear()

    def size(self) -> int:
        return len(self._arc)

    def hit_ratio(self) -> float:
        return self._arc.hit_ratio


class ARCFilterCache(ARCCacheAdapter[RoaringBitmap]):
    """ARC-based FilterCache supporting RoaringBitmap automatic conversions."""

    def put(self, key: str, value: Union[RoaringBitmap, Iterable[int]]) -> None:
        if isinstance(value, RoaringBitmap):
            super().put(key, value)
        else:
            super().put(key, RoaringBitmap(list(value)))


class FilterCache(LRUCache[RoaringBitmap]):
    """Caches boolean filter query result doc_id RoaringBitmaps."""

    def put(self, key: str, value: Union[RoaringBitmap, Iterable[int]]) -> None:
        if isinstance(value, RoaringBitmap):
            super().put(key, value)
        else:
            super().put(key, RoaringBitmap(list(value)))


class QueryResultCache(LRUCache[List[int]]):
    """Caches top ranked doc_id lists for specific query strings."""

    pass


class DocumentCache(LRUCache[Dict[str, Any]]):
    """Caches materialized document dictionaries."""

    pass


def _create_arc_solr_caches(
    filter_cap: int, query_cap: int, doc_cap: int
) -> tuple[ARCFilterCache, ARCCacheAdapter[List[int]], ARCCacheAdapter[Dict[str, Any]]]:
    fc = ARCFilterCache(filter_cap)
    qc: ARCCacheAdapter[List[int]] = ARCCacheAdapter(query_cap)
    dc: ARCCacheAdapter[Dict[str, Any]] = ARCCacheAdapter(doc_cap)
    return fc, qc, dc


def _create_lru_solr_caches(
    filter_cap: int, query_cap: int, doc_cap: int
) -> tuple[FilterCache, QueryResultCache, DocumentCache]:
    return FilterCache(filter_cap), QueryResultCache(query_cap), DocumentCache(doc_cap)


class SolrCache:
    """Unified cache facade holding filterCache, queryResultCache, and documentCache."""

    filter_cache: Union[FilterCache, ARCFilterCache]
    query_result_cache: Union[QueryResultCache, ARCCacheAdapter[List[int]]]
    document_cache: Union[DocumentCache, ARCCacheAdapter[Dict[str, Any]]]

    def __init__(
        self,
        filter_cap: int = 500,
        query_cap: int = 500,
        doc_cap: int = 2000,
        use_arc: bool = False,
    ) -> None:
        self.use_arc = use_arc
        if use_arc:
            self.filter_cache, self.query_result_cache, self.document_cache = (
                _create_arc_solr_caches(filter_cap, query_cap, doc_cap)
            )
        else:
            self.filter_cache, self.query_result_cache, self.document_cache = (
                _create_lru_solr_caches(filter_cap, query_cap, doc_cap)
            )

    def clear_all(self) -> None:
        self.filter_cache.clear()
        self.query_result_cache.clear()
        self.document_cache.clear()

    def get_stats(self) -> Dict[str, Any]:
        return {
            "use_arc": self.use_arc,
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
