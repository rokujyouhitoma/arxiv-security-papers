#!/usr/bin/env python3
"""
Solr-style Caching Architecture:
- FilterCache: Caches Bitsets of DocIDs for filter queries (fq=category:cs.CR)
- QueryResultCache: Caches ordered lists of TopDocs for queries
"""

from collections import OrderedDict
from typing import Any, Dict, List, Optional, Set


class LRUCache:
    """Generic LRU Cache container."""

    def __init__(self, max_size: int = 500) -> None:
        self.max_size = max_size
        self.cache: OrderedDict[str, Any] = OrderedDict()
        self.hits = 0
        self.misses = 0

    def get(self, key: str) -> Optional[Any]:
        if key in self.cache:
            self.hits += 1
            self.cache.move_to_end(key)
            return self.cache[key]
        self.misses += 1
        return None

    def put(self, key: str, value: Any) -> None:
        if key in self.cache:
            self.cache.move_to_end(key)
        self.cache[key] = value
        if len(self.cache) > self.max_size:
            self.cache.popitem(last=False)

    def stats(self) -> Dict[str, Any]:
        total = self.hits + self.misses
        hit_ratio = round(self.hits / total, 3) if total > 0 else 0.0
        return {
            "size": len(self.cache),
            "max_size": self.max_size,
            "hits": self.hits,
            "misses": self.misses,
            "hit_ratio": hit_ratio,
        }


class FilterCache(LRUCache):
    """Caches DocID Sets for structured filter expressions."""

    def get_filter_docs(self, filter_key: str) -> Optional[Set[str]]:
        return self.get(filter_key)

    def put_filter_docs(self, filter_key: str, doc_ids: Set[str]) -> None:
        self.put(filter_key, doc_ids)


class QueryResultCache(LRUCache):
    """Caches search responses and ranking results."""

    def get_results(self, query_key: str) -> Optional[List[Dict[str, Any]]]:
        return self.get(query_key)

    def put_results(self, query_key: str, results: List[Dict[str, Any]]) -> None:
        self.put(query_key, results)
