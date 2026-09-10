#!/usr/bin/env python3
"""
Tests for RoaringBitmapIndex, TableBitmapIndexes, and VisibilityMap in src/database/.
"""

import pytest

from database.index.bitmap_index import RoaringBitmapIndex, TableBitmapIndexes
from database.storage.visibility_map import VisibilityMap


def test_roaring_bitmap_index_basic_operations():
    idx = RoaringBitmapIndex("severity", cardinality_threshold=5)

    # Insert rows
    idx.insert("CRITICAL", 1)
    idx.insert("CRITICAL", 2)
    idx.insert("HIGH", 3)
    idx.insert("MEDIUM", 4)
    idx.insert("CRITICAL", 100000)

    # Lookup equality
    crit_rows = idx.lookup("CRITICAL")
    assert len(crit_rows) == 3
    assert 1 in crit_rows
    assert 2 in crit_rows
    assert 100000 in crit_rows
    assert 3 not in crit_rows

    # Lookup non-existent
    low_rows = idx.lookup("LOW")
    assert len(low_rows) == 0

    # Lookup IN
    crit_high = idx.lookup_in(["CRITICAL", "HIGH"])
    assert len(crit_high) == 4
    assert 1 in crit_high
    assert 3 in crit_high
    assert 4 not in crit_high

    # All rows & cardinality
    assert idx.cardinality() == 3
    all_rows = idx.all_rows()
    assert len(all_rows) == 5

    # Delete row
    idx.delete("CRITICAL", 2)
    assert 2 not in idx.lookup("CRITICAL")
    assert len(idx.lookup("CRITICAL")) == 2

    # Delete all rows of a key cleans up the key
    idx.delete("MEDIUM", 4)
    assert idx.cardinality() == 2


def test_roaring_bitmap_index_cardinality_threshold():
    idx = RoaringBitmapIndex("tag", cardinality_threshold=2)
    idx.insert("v1", 1)
    idx.insert("v2", 2)
    # v1 and v2 are 2 distinct keys; adding v3 should raise ValueError
    with pytest.raises(ValueError, match="exceeded cardinality threshold"):
        idx.insert("v3", 3)


def test_roaring_bitmap_index_serialization_roundtrip():
    idx = RoaringBitmapIndex("category", cardinality_threshold=100)
    for r in range(100):
        idx.insert("cs.CR" if r % 2 == 0 else "quant-ph", r)

    serialized = idx.to_bytes()
    assert isinstance(serialized, bytes)
    assert len(serialized) > 12

    restored = RoaringBitmapIndex.from_bytes(serialized)
    assert restored.column_name == "category"
    assert restored.cardinality_threshold == 100
    assert restored.cardinality() == 2
    assert len(restored.lookup("cs.CR")) == 50
    assert len(restored.lookup("quant-ph")) == 50

    # Tampering / corruption check
    with pytest.raises(ValueError, match="Invalid magic bytes"):
        RoaringBitmapIndex.from_bytes(b"INVALIDMAGIC" + serialized[12:])
    with pytest.raises(ValueError, match="insufficient header length"):
        RoaringBitmapIndex.from_bytes(b"SHORT")


def test_table_bitmap_indexes_composite_queries():
    table_idx = TableBitmapIndexes()
    table_idx.add_index("severity")
    table_idx.add_index("status")
    table_idx.add_index("category")

    rows = [
        {"id": 1, "severity": "CRITICAL", "status": "OPEN", "category": "cs.CR"},
        {"id": 2, "severity": "CRITICAL", "status": "RESOLVED", "category": "cs.CR"},
        {"id": 3, "severity": "HIGH", "status": "OPEN", "category": "cs.CR"},
        {"id": 4, "severity": "CRITICAL", "status": "OPEN", "category": "quant-ph"},
        {"id": 5, "severity": "LOW", "status": "OPEN", "category": "cs.CR"},
    ]
    for r in rows:
        table_idx.insert_row(r["id"], r)

    # 1. Composite AND: CRITICAL and OPEN
    res_and = table_idx.eval_and({"severity": "CRITICAL", "status": "OPEN"})
    assert set(res_and) == {1, 4}

    # 2. Triple AND: CRITICAL and OPEN and cs.CR
    res_triple = table_idx.eval_and(
        {"severity": "CRITICAL", "status": "OPEN", "category": "cs.CR"}
    )
    assert set(res_triple) == {1}

    # 3. Composite OR across columns: status=RESOLVED or severity=LOW
    res_or = table_idx.eval_or({"status": "RESOLVED", "severity": "LOW"})
    assert set(res_or) == {2, 5}

    # 4. NOT: NOT RESOLVED
    res_not = table_idx.eval_not("status", "RESOLVED")
    assert 2 not in res_not
    assert set(res_not) == {1, 3, 4, 5}

    # 5. Delete row
    table_idx.delete_row(
        1, {"severity": "CRITICAL", "status": "OPEN", "category": "cs.CR"}
    )
    assert set(table_idx.eval_and({"severity": "CRITICAL", "status": "OPEN"})) == {4}


def test_visibility_map_operations_and_serialization():
    vmap = VisibilityMap()

    # Insert rows 1..10
    for r in range(1, 11):
        vmap.mark_inserted(r)
    assert vmap.live_count() == 10
    assert vmap.tombstone_count() == 0

    # Delete rows 3 and 7
    vmap.mark_deleted(3)
    vmap.mark_deleted(7)
    assert vmap.live_count() == 8
    assert vmap.tombstone_count() == 2
    assert vmap.is_visible(1)
    assert not vmap.is_visible(3)
    assert not vmap.is_visible(7)
    assert not vmap.is_visible(999)

    # Re-insert row 3
    vmap.mark_inserted(3)
    assert vmap.is_visible(3)
    assert vmap.tombstone_count() == 1

    # Serialization roundtrip
    data = vmap.to_bytes()
    restored = VisibilityMap.from_bytes(data)
    assert restored.live_count() == vmap.live_count()
    assert restored.tombstone_count() == vmap.tombstone_count()
    assert restored.is_visible(3)
    assert not restored.is_visible(7)

    # VACUUM compact
    retained = restored.get_live_rows()
    restored.vacuum_compact(retained)
    assert restored.tombstone_count() == 0
    assert restored.live_count() == len(retained)


def test_bitmap_index_visibility_map_integration():
    idx = RoaringBitmapIndex("priority")
    vmap = VisibilityMap()

    for r in range(1, 101):
        prio = "P0" if r % 2 == 0 else "P1"
        idx.insert(prio, r)
        vmap.mark_inserted(r)

    # Query all P0
    p0_candidates = idx.lookup("P0")
    assert len(p0_candidates) == 50

    # Delete rows 2, 4, 6
    vmap.mark_deleted(2)
    vmap.mark_deleted(4)
    vmap.mark_deleted(6)

    # Filter with VisibilityMap
    live_p0 = vmap.filter_visible(p0_candidates)
    assert len(live_p0) == 47
    assert 2 not in live_p0
    assert 4 not in live_p0
    assert 6 not in live_p0
    assert 8 in live_p0
