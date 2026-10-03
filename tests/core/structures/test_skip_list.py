#!/usr/bin/env python3
"""
Unit tests for core SkipList data structure and LSM MemTable integration.
"""

import random

from core.structures.skip_list import SkipList
from database.lsm.memtable import MemTable


def test_skiplist_basic_crud() -> None:
    sl: SkipList[str, int] = SkipList()
    assert len(sl) == 0
    assert "apple" not in sl
    assert sl.get("apple") is None
    assert sl.get("apple", 999) == 999

    sl.put("banana", 2)
    sl.put("apple", 1)
    sl.put("cherry", 3)

    assert len(sl) == 3
    assert "apple" in sl
    assert "banana" in sl
    assert "cherry" in sl
    assert "date" not in sl

    assert sl.get("apple") == 1
    assert sl.get("banana") == 2
    assert sl.get("cherry") == 3

    # Update existing key
    sl.put("banana", 20)
    assert len(sl) == 3
    assert sl.get("banana") == 20

    # Delete key
    assert sl.delete("banana") is True
    assert len(sl) == 2
    assert "banana" not in sl
    assert sl.get("banana") is None
    assert sl.delete("banana") is False

    # Clear
    sl.clear()
    assert len(sl) == 0
    assert "apple" not in sl


def test_skiplist_ordering_and_traversal() -> None:
    sl: SkipList[int, str] = SkipList()
    keys = [50, 20, 80, 10, 30, 70, 90, 40, 60]
    for k in keys:
        sl.put(k, f"val-{k}")

    assert sl.keys() == sorted(keys)
    assert sl.values() == [f"val-{k}" for k in sorted(keys)]
    assert sl.items() == [(k, f"val-{k}") for k in sorted(keys)]

    iter_items = list(iter(sl))
    assert iter_items == sl.items()


def test_skiplist_range_scan() -> None:
    sl: SkipList[int, str] = SkipList()
    for i in range(10, 100, 10):  # 10, 20, ..., 90
        sl.put(i, f"v{i}")

    # Full range
    assert len(sl.range()) == 9

    # [30, 70) -> 30, 40, 50, 60
    r1 = sl.range(30, 70)
    assert [k for k, _ in r1] == [30, 40, 50, 60]

    # [25, 65) -> 30, 40, 50, 60 (start/end not exactly in list)
    r2 = sl.range(25, 65)
    assert [k for k, _ in r2] == [30, 40, 50, 60]

    # [70, None) -> 70, 80, 90
    r3 = sl.range(start_key=70)
    assert [k for k, _ in r3] == [70, 80, 90]

    # [None, 40) -> 10, 20, 30
    r4 = sl.range(end_key=40)
    assert [k for k, _ in r4] == [10, 20, 30]

    # Out of range
    assert sl.range(100, 200) == []
    assert sl.range(0, 10) == []


def test_skiplist_large_random_operations() -> None:
    sl: SkipList[int, int] = SkipList(max_level=12, p=0.5)
    oracle = {}

    rng = random.Random(42)
    keys = [rng.randint(0, 10000) for _ in range(500)]

    for k in keys:
        v = k * 10
        sl.put(k, v)
        oracle[k] = v

    assert len(sl) == len(oracle)
    assert sl.keys() == sorted(oracle.keys())

    for k in keys[:200]:
        del_res = sl.delete(k)
        if k in oracle:
            del oracle[k]
            assert del_res is True

    assert len(sl) == len(oracle)
    assert sl.keys() == sorted(oracle.keys())


def test_skiplist_boundary_levels() -> None:
    sl_min: SkipList[str, str] = SkipList(max_level=1)
    sl_min.put("a", "1")
    sl_min.put("b", "2")
    assert len(sl_min) == 2
    assert sl_min.get("b") == "2"

    sl_max: SkipList[str, str] = SkipList(max_level=100)  # clamped to 32
    assert sl_max.max_level == 32


def test_memtable_skiplist_integration() -> None:
    mem = MemTable(max_bytes=1024)
    mem.put("user:103", {"name": "Charlie"})
    mem.put("user:101", {"name": "Alice"})
    mem.put("user:102", {"name": "Bob"})

    assert len(mem) == 3

    # get
    ok, data = mem.get("user:101")
    assert ok is True
    assert data == {"name": "Alice"}

    # items are sorted
    items = mem.items()
    assert [k for k, _ in items] == ["user:101", "user:102", "user:103"]

    # scan range
    scanned = mem.scan("user:101", "user:103")
    assert [k for k, _ in scanned] == ["user:101", "user:102"]

    # tombstone delete
    mem.delete("user:102")
    ok, deleted_data = mem.get("user:102")
    assert ok is True
    assert deleted_data is None

    # non-existent key
    ok, no_data = mem.get("user:999")
    assert ok is False
    assert no_data is None

    mem.clear()
    assert len(mem) == 0
