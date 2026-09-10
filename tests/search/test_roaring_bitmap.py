#!/usr/bin/env python3
"""
Unit tests for 32-bit Pure-Python Roaring Bitmap.
Verifies container promotion/demotion, set operations parity with Python set,
serialization roundtrip, and DeletedDocsBitset integration.
"""

from typing import List

import pytest

from search.core.index.roaring_bitmap import (
    ARRAY_MAX_CAPACITY,
    TYPE_ARRAY,
    TYPE_BITMAP,
    RoaringBitmap,
)
from search.core.store.segment import DeletedDocsBitset as CoreDeletedDocsBitset
from search.engine.index import DeletedDocsBitset as EngineDeletedDocsBitset


def test_roaring_bitmap_empty_state() -> None:
    """Verifies empty bitmap state."""
    rb = RoaringBitmap()
    assert (len(rb), bool(rb), 10 in rb) == (0, False, False)


def test_roaring_bitmap_add_and_contains() -> None:
    """Verifies basic add and contains operations with duplicates."""
    rb = RoaringBitmap()
    rb.add(10)
    rb.add(20)
    rb.add(10)
    assert (len(rb), bool(rb)) == (2, True)
    assert (10 in rb, 20 in rb, 30 in rb) == (True, True, False)


def test_roaring_bitmap_remove_and_discard() -> None:
    """Verifies remove raises KeyError and discard silently ignores missing values."""
    rb = RoaringBitmap([1, 2, 3])
    rb.remove(2)
    assert (2 in rb, len(rb)) == (False, 2)

    with pytest.raises(KeyError):
        rb.remove(99)

    rb.discard(99)
    assert len(rb) == 2


def test_roaring_bitmap_out_of_range_handling() -> None:
    """Verifies boundary check on 32-bit unsigned integers."""
    rb = RoaringBitmap()
    with pytest.raises(ValueError):
        rb.add(-1)
    with pytest.raises(ValueError):
        rb.add(0x100000000)
    assert (-1 in rb, 0x100000000 in rb) == (False, False)


def test_array_to_bitmap_container_promotion() -> None:
    """Verifies ArrayContainer promotes to BitmapContainer when exceeding 4096 elements."""
    rb = RoaringBitmap()
    for i in range(ARRAY_MAX_CAPACITY):
        rb.add(i)

    c0 = rb._chunks[0]
    assert (c0.container_type(), c0.get_cardinality()) == (
        TYPE_ARRAY,
        ARRAY_MAX_CAPACITY,
    )

    rb.add(ARRAY_MAX_CAPACITY)
    c1 = rb._chunks[0]
    assert (
        c1.container_type(),
        c1.get_cardinality(),
        c1.contains(ARRAY_MAX_CAPACITY),
    ) == (
        TYPE_BITMAP,
        ARRAY_MAX_CAPACITY + 1,
        True,
    )


def test_bitmap_to_array_container_demotion() -> None:
    """Verifies BitmapContainer demotes back to ArrayContainer when dropping below 4096."""
    rb = RoaringBitmap(list(range(ARRAY_MAX_CAPACITY + 1)))
    assert rb._chunks[0].container_type() == TYPE_BITMAP

    rb.remove(0)
    rb.remove(1)
    c = rb._chunks[0]
    assert (c.container_type(), c.get_cardinality()) == (
        TYPE_ARRAY,
        ARRAY_MAX_CAPACITY - 1,
    )
    assert (0 in rb, 2 in rb) == (False, True)


def test_multi_chunk_partitioning() -> None:
    """Verifies elements across multiple 64K chunks are properly separated."""
    rb = RoaringBitmap()
    val1 = 100
    val2 = 65536 + 200
    val3 = 65536 * 3 + 500

    for v in (val1, val2, val3):
        rb.add(v)

    assert len(rb) == 3
    assert set(rb._chunks.keys()) == {0, 1, 3}
    assert rb.to_list() == [val1, val2, val3]


def _compare_set_ops(list_a: List[int], list_b: List[int]) -> None:
    rb_a, rb_b = RoaringBitmap(list_a), RoaringBitmap(list_b)
    s_a, s_b = set(list_a), set(list_b)

    assert (rb_a & rb_b).to_set() == (s_a & s_b)
    assert (rb_a | rb_b).to_set() == (s_a | s_b)
    assert (rb_a - rb_b).to_set() == (s_a - s_b)
    assert (rb_a ^ rb_b).to_set() == (s_a ^ s_b)


def test_set_operations_parity_sparse() -> None:
    """Verifies set operations match Python native set for sparse values."""
    list_a = [1, 5, 10, 65536 + 2, 65536 + 8]
    list_b = [5, 10, 15, 65536 + 8, 65536 + 20]
    _compare_set_ops(list_a, list_b)


def test_set_operations_parity_dense() -> None:
    """Verifies set operations match Python native set for dense values (BitmapContainers)."""
    list_a = list(range(1000, 6000))
    list_b = list(range(4000, 9000))
    _compare_set_ops(list_a, list_b)


def test_serialization_roundtrip_array() -> None:
    """Verifies serialization and deserialization of ArrayContainers."""
    rb = RoaringBitmap([5, 12, 100, 65536 + 1, 65536 * 2 + 99])
    raw = rb.to_bytes()
    restored = RoaringBitmap.from_bytes(raw)
    assert (len(restored), restored.to_list()) == (len(rb), rb.to_list())


def test_serialization_roundtrip_bitmap() -> None:
    """Verifies serialization and deserialization of BitmapContainers."""
    dense_vals = list(range(0, 5000)) + [65536 + 10]
    rb = RoaringBitmap(dense_vals)
    raw = rb.to_bytes()
    restored = RoaringBitmap.from_bytes(raw)
    assert (len(restored), restored.to_list()) == (len(rb), rb.to_list())


def test_serialization_corrupt_data_errors() -> None:
    """Verifies invalid byte data raises ValueError."""
    with pytest.raises(ValueError, match="insufficient length"):
        RoaringBitmap.from_bytes(b"short")

    with pytest.raises(ValueError, match="Invalid magic cookie"):
        RoaringBitmap.from_bytes(b"\x00" * 16)


def test_memory_reduction_benchmark() -> None:
    """Verifies that RoaringBitmap uses significantly less memory than set for dense integers."""
    dense_count = 6000
    rb = RoaringBitmap(list(range(dense_count)))
    rb_bytes = rb.get_size_in_bytes()

    assert rb_bytes < 10000
    assert rb._chunks[0].container_type() == TYPE_BITMAP


def test_engine_deleted_docs_bitset_integration() -> None:
    """Verifies search.engine.index.DeletedDocsBitset backed by RoaringBitmap."""
    bitset = EngineDeletedDocsBitset()
    assert bitset.count() == 0

    bitset.delete(10)
    bitset.delete(20)
    assert (bitset.count(), bitset.to_set()) == (2, {10, 20})
    assert (bitset.is_deleted(10), bitset.is_deleted(15)) == (True, False)


def test_core_deleted_docs_bitset_integration() -> None:
    """Verifies search.core.store.segment.DeletedDocsBitset backed by RoaringBitmap."""
    bitset = CoreDeletedDocsBitset()
    assert bitset.count() == 0

    bitset.mark_deleted("101")
    bitset.mark_deleted("doc_alpha")
    assert bitset.count() == 2
    assert (
        bitset.is_deleted("101"),
        bitset.is_deleted("doc_alpha"),
        bitset.is_deleted("doc_beta"),
    ) == (True, True, False)
