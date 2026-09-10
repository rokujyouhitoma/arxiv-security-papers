#!/usr/bin/env python3
"""
Zero-dependency Adaptive Replacement Cache (ARC).
Self-tuning cache balancing Recency (T1, B1) and Frequency (T2, B2) with scan resistance.
Megiddo & Modha (FAST '03) compliant.
"""

from __future__ import annotations

from collections import OrderedDict
from typing import Any, Generic, List, Optional, Tuple, TypeVar

K = TypeVar("K")
V = TypeVar("V")


def _pop_lru(d: OrderedDict[K, Any]) -> Tuple[K, Any]:
    """Pops and returns the least recently used item."""
    return d.popitem(last=False)


def _should_evict_t1(t1_len: int, p: float, in_b2: bool) -> bool:
    if t1_len == 0:
        return False
    if t1_len > p:
        return True
    return in_b2 and t1_len == int(p)


def _step_replace(
    t1: OrderedDict[K, V],
    t2: OrderedDict[K, V],
    b1: OrderedDict[K, None],
    b2: OrderedDict[K, None],
    p: float,
    capacity: int,
    in_b2: bool,
) -> None:
    """Evicts from T1 to B1 or from T2 to B2 based on parameter p when full."""
    if len(t1) + len(t2) < capacity:
        return
    if _should_evict_t1(len(t1), p, in_b2):
        evicted_key, _ = _pop_lru(t1)
        b1[evicted_key] = None
    elif len(t2) > 0:
        evicted_key, _ = _pop_lru(t2)
        b2[evicted_key] = None


def _prune_b1_if_full(t1_len: int, b1: OrderedDict[K, None], capacity: int) -> None:
    if t1_len < capacity and b1:
        _pop_lru(b1)


def _prune_b2_if_full(total: int, b2: OrderedDict[K, None], capacity: int) -> None:
    if total >= 2 * capacity and b2:
        _pop_lru(b2)


def _prune_ghost_for_miss(
    t1: OrderedDict[K, V],
    t2: OrderedDict[K, V],
    b1: OrderedDict[K, None],
    b2: OrderedDict[K, None],
    capacity: int,
) -> None:
    """Discards an old ghost entry when history capacity bounds are reached."""
    if len(t1) + len(b1) == capacity:
        _prune_b1_if_full(len(t1), b1, capacity)
    else:
        total = len(t1) + len(t2) + len(b1) + len(b2)
        _prune_b2_if_full(total, b2, capacity)


class ARCCache(Generic[K, V]):
    """
    Adaptive Replacement Cache (ARC).
    Maintains self-tuning balance between recency and frequency caches.
    """

    def __init__(self, capacity: int = 128) -> None:
        self.capacity = max(1, min(1000000, capacity))
        self.p: float = 0.0
        self.t1: OrderedDict[K, V] = OrderedDict()
        self.t2: OrderedDict[K, V] = OrderedDict()
        self.b1: OrderedDict[K, None] = OrderedDict()
        self.b2: OrderedDict[K, None] = OrderedDict()
        self._hits: int = 0
        self._misses: int = 0

    def __len__(self) -> int:
        return len(self.t1) + len(self.t2)

    def __contains__(self, key: K) -> bool:
        return key in self.t1 or key in self.t2

    @property
    def hit_count(self) -> int:
        return self._hits

    @property
    def miss_count(self) -> int:
        return self._misses

    @property
    def hit_ratio(self) -> float:
        total = self._hits + self._misses
        return self._hits / total if total > 0 else 0.0

    def get(self, key: K, default: Optional[V] = None) -> Optional[V]:
        """Looks up key. On hit, promotes entry to T2."""
        if key in self.t1:
            val = self.t1.pop(key)
            self.t2[key] = val
            self._hits += 1
            return val
        if key in self.t2:
            self.t2.move_to_end(key)
            self._hits += 1
            return self.t2[key]

        self._misses += 1
        return default

    def _replace(self, in_b2: bool) -> None:
        _step_replace(self.t1, self.t2, self.b1, self.b2, self.p, self.capacity, in_b2)

    def _adapt_b1(self, key: K, value: V) -> None:
        """Adapts parameter p and moves key from B1 to T2."""
        delta = max(1.0, len(self.b2) / max(1, len(self.b1)))
        self.p = min(float(self.capacity), self.p + delta)
        self._replace(in_b2=False)
        self.b1.pop(key, None)
        self.t2[key] = value

    def _adapt_b2(self, key: K, value: V) -> None:
        """Adapts parameter p and moves key from B2 to T2."""
        delta = max(1.0, len(self.b1) / max(1, len(self.b2)))
        self.p = max(0.0, self.p - delta)
        self._replace(in_b2=True)
        self.b2.pop(key, None)
        self.t2[key] = value

    def _insert_miss(self, key: K, value: V) -> None:
        """Inserts a new item missing from all lists into T1."""
        _prune_ghost_for_miss(self.t1, self.t2, self.b1, self.b2, self.capacity)
        self._replace(in_b2=False)
        self.t1[key] = value

    def put(self, key: K, value: V) -> None:
        """Inserts or updates key-value pair with self-tuning eviction."""
        if key in self.t1:
            self.t1.pop(key)
            self.t2[key] = value
        elif key in self.t2:
            self.t2[key] = value
            self.t2.move_to_end(key)
        elif key in self.b1:
            self._adapt_b1(key, value)
        elif key in self.b2:
            self._adapt_b2(key, value)
        else:
            self._insert_miss(key, value)

    def delete(self, key: K) -> bool:
        """Deletes key from active and ghost caches. Returns True if deleted."""
        deleted = False
        if key in self.t1:
            del self.t1[key]
            deleted = True
        if key in self.t2:
            del self.t2[key]
            deleted = True
        self.b1.pop(key, None)
        self.b2.pop(key, None)
        return deleted

    def clear(self) -> None:
        """Clears all active and ghost entries."""
        self.t1.clear()
        self.t2.clear()
        self.b1.clear()
        self.b2.clear()
        self.p = 0.0
        self._hits = 0
        self._misses = 0

    def keys(self) -> List[K]:
        """Returns keys of all active entries in T1 and T2."""
        return list(self.t1.keys()) + list(self.t2.keys())
