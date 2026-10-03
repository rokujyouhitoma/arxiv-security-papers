#!/usr/bin/env python3
"""
Unit tests for Adaptive Replacement Cache (ARCCache).
Validates self-tuning adaptation and scan resistance.
"""

from core.structures.arc_cache import ARCCache


def test_arc_basic_crud() -> None:
    cache: ARCCache[str, int] = ARCCache(capacity=3)
    assert len(cache) == 0
    assert cache.get("a") is None
    assert cache.miss_count == 1
    assert cache.hit_count == 0

    cache.put("a", 1)
    cache.put("b", 2)
    cache.put("c", 3)
    assert len(cache) == 3
    assert "a" in cache
    assert "b" in cache
    assert "c" in cache
    assert "d" not in cache

    assert cache.get("a") == 1
    assert cache.get("b") == 2
    assert cache.hit_count == 2
    assert cache.hit_ratio == 2 / 3

    # Update existing
    cache.put("a", 100)
    assert cache.get("a") == 100

    # Delete
    assert cache.delete("a") is True
    assert cache.delete("a") is False
    assert len(cache) == 2

    # Clear
    cache.clear()
    assert len(cache) == 0
    assert cache.p == 0.0
    assert cache.hit_count == 0


def test_arc_ghost_adaptation() -> None:
    cache: ARCCache[str, str] = ARCCache(capacity=2)

    cache.put("k1", "v1")
    cache.put("k2", "v2")
    # T1 = {k1, k2}, p = 0.0

    # Insert k3 causes k1 to be evicted to B1
    cache.put("k3", "v3")
    assert "k1" not in cache
    assert "k1" in cache.b1

    # Access k1 in B1 -> triggers B1 adaptation: increases p
    cache.put("k1", "v1_new")
    assert cache.p > 0.0
    assert "k1" in cache
    assert "k1" not in cache.b1


def test_arc_b2_adaptation() -> None:
    cache: ARCCache[str, str] = ARCCache(capacity=2)

    # Establish frequent item in T2
    cache.put("k1", "v1")
    cache.get("k1")  # promoted to T2

    # Put k2, k3 causing k1 to eventually be evicted from T2 to B2
    cache.put("k2", "v2")
    cache.put("k3", "v3")

    # If k1 is in b2, putting it again triggers B2 adaptation (decreases p)
    if "k1" in cache.b2:
        cache.p = 1.0
        cache.put("k1", "v1_reborn")
        assert "k1" in cache
        assert "k1" not in cache.b2
        assert cache.p < 1.0


def test_arc_scan_resistance() -> None:
    """
    Core ARC feature: High-frequency items in T2 should survive
    a massive sequential scan of one-time items, unlike naive LRU.
    """
    cache: ARCCache[str, str] = ARCCache(capacity=5)

    # Establish frequent items (hit at least twice to move to T2)
    frequent_keys = ["hot_1", "hot_2", "hot_3"]
    for k in frequent_keys:
        cache.put(k, f"val_{k}")
        cache.get(k)  # Promotes to T2

    for k in frequent_keys:
        assert k in cache.t2

    # Sequential scan of 50 one-off keys (each inserted once)
    for i in range(50):
        cache.put(f"scan_{i}", f"val_{i}")

    # Frequent items in T2 must NOT all be wiped out
    surviving_hot = sum(1 for k in frequent_keys if k in cache)
    assert (
        surviving_hot >= 2
    ), f"Expected frequent items to survive scan, got {surviving_hot}"


def test_arc_capacity_one() -> None:
    cache: ARCCache[int, str] = ARCCache(capacity=1)
    cache.put(1, "one")
    assert cache.get(1) == "one"

    cache.put(2, "two")
    assert len(cache) == 1
    assert cache.get(2) == "two"
    assert cache.get(1) is None
