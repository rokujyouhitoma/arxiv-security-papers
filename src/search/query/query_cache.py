#!/usr/bin/env python3
"""
Semantic Query Cache with Jaccard/Cosine Similarity Matching & TTL.
Caches query embeddings and results for ultra-fast (< 1ms) responses.
"""

import time
from typing import Any, Dict, List, Optional, Set, Tuple


class QuerySemanticCache:
    """
    Semantic Query Cache with Token Overlap / Cosine Similarity Matching & TTL.
    """

    def __init__(
        self,
        max_entries: int = 500,
        default_ttl: int = 3600,
        similarity_threshold: float = 0.95,
    ):
        self.max_entries = max_entries
        self.default_ttl = default_ttl
        self.similarity_threshold = similarity_threshold
        self.cache: Dict[str, Dict[str, Any]] = {}
        self.hits = 0
        self.misses = 0

    def _compute_jaccard(self, set_a: Set[str], set_b: Set[str]) -> float:
        if not set_a or not set_b:
            return 0.0
        intersection = len(set_a & set_b)
        union = len(set_a | set_b)
        return float(intersection) / float(union) if union > 0 else 0.0

    def _get_exact_match(
        self, q_clean: str, now: float
    ) -> Optional[Tuple[List[Dict[str, Any]], Dict[str, Any]]]:
        if q_clean not in self.cache:
            return None
        entry = self.cache[q_clean]
        if now < entry["expires_at"]:
            self.hits += 1
            entry["hit_count"] += 1
            return entry["results"], entry["profile"]
        del self.cache[q_clean]
        return None

    def _get_semantic_match(
        self, q_tokens_set: Set[str], now: float
    ) -> Optional[Tuple[List[Dict[str, Any]], Dict[str, Any]]]:
        for key, entry in list(self.cache.items()):
            if now >= entry["expires_at"]:
                del self.cache[key]
                continue
            sim = self._compute_jaccard(q_tokens_set, entry["tokens_set"])
            if sim >= self.similarity_threshold:
                self.hits += 1
                entry["hit_count"] += 1
                return entry["results"], entry["profile"]
        return None

    @staticmethod
    def _is_cache_sufficient(
        res: Tuple[List[Dict[str, Any]], Dict[str, Any]], min_results: int
    ) -> bool:
        results, profile = res
        if len(results) >= min_results:
            return True
        return not bool(profile.get("has_more", False))

    def _find_semantic_res(
        self, query_tokens: List[str], now: float, min_results: int
    ) -> Optional[Tuple[List[Dict[str, Any]], Dict[str, Any]]]:
        semantic_res = self._get_semantic_match(set(query_tokens), now)
        if semantic_res is not None and self._is_cache_sufficient(
            semantic_res, min_results
        ):
            return semantic_res
        return None

    def get(
        self,
        query: str,
        query_tokens: List[str],
        exact_only: bool = False,
        min_results: int = 1,
    ) -> Optional[Tuple[List[Dict[str, Any]], Dict[str, Any]]]:
        now = time.time()
        q_clean = query.strip().lower()

        exact_res = self._get_exact_match(q_clean, now)
        if exact_res is not None and self._is_cache_sufficient(exact_res, min_results):
            return exact_res

        if not exact_only:
            sem_res = self._find_semantic_res(query_tokens, now, min_results)
            if sem_res is not None:
                return sem_res

        self.misses += 1
        return None

    def set(
        self,
        query: str,
        query_tokens: List[str],
        results: List[Dict[str, Any]],
        profile: Dict[str, Any],
        ttl: Optional[int] = None,
    ) -> None:
        if len(self.cache) >= self.max_entries:
            oldest_key = min(
                self.cache.keys(), key=lambda k: self.cache[k]["created_at"]
            )
            del self.cache[oldest_key]

        expires_at = time.time() + (ttl or self.default_ttl)
        q_clean = query.strip().lower()
        self.cache[q_clean] = {
            "query": query,
            "tokens_set": set(query_tokens),
            "results": results,
            "profile": profile,
            "created_at": time.time(),
            "expires_at": expires_at,
            "hit_count": 0,
        }

    def get_stats(self) -> Dict[str, Any]:
        total = self.hits + self.misses
        return {
            "total_entries": len(self.cache),
            "hits": self.hits,
            "misses": self.misses,
            "hit_ratio": round(self.hits / total, 4) if total > 0 else 0.0,
        }

    def clear(self) -> None:
        self.cache.clear()
        self.hits = 0
        self.misses = 0
