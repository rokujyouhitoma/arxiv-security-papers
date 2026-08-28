#!/usr/bin/env python3
"""
Unit tests for Slotted-Page Binary Storage Engine (DSN-14 Phase 1 / Issue 038).
"""

import pytest

from src.database.pager import Pager
from src.database.slotted_page import (
    DataType,
    OverflowManager,
    PageCorruptionError,
    PageFullError,
    PageType,
    SlottedPage,
    TupleSerializer,
)
from src.database.vfs import MemoryVFS, register_vfs


class MockPageAllocator:
    """Mock page allocator for testing overflow page allocations."""

    def __init__(self, start_id: int = 100) -> None:
        self.next_id = start_id

    def allocate_page_id(self) -> int:
        pid = self.next_id
        self.next_id += 1
        return pid


def test_slotted_page_initialization_and_header() -> None:
    """Tests page header creation, boundaries, and free space calculations."""
    page = SlottedPage(page_id=42, page_type=PageType.DATA)
    assert page.page_id == 42
    assert page.slot_count == 0
    assert page.flags == int(PageType.DATA)
    assert page.free_space == 4096 - 28  # 4068 bytes
    assert page.validate_checksum() is True


def test_slotted_page_checksum_tampering() -> None:
    """Tests that corrupting page bytes triggers PageCorruptionError on deserialization."""
    page = SlottedPage(page_id=1, page_type=PageType.DATA)
    page.insert_tuple(b"test security paper payload")
    serialized = bytearray(page.serialize())

    # Tamper with 1 byte in payload area
    serialized[4090] ^= 0xFF

    with pytest.raises(PageCorruptionError):
        SlottedPage(raw_data=bytes(serialized))


def test_slotted_page_insert_and_get() -> None:
    """Tests inserting multiple records and retrieving them by slot ID."""
    page = SlottedPage(page_id=10)
    data1 = b"First Arxiv Security Paper"
    data2 = b"Second Paper: Differential Privacy"
    data3 = b"Third Paper: Post-Quantum Cryptography"

    slot0 = page.insert_tuple(data1)
    slot1 = page.insert_tuple(data2)
    slot2 = page.insert_tuple(data3)

    assert slot0 == 0
    assert slot1 == 1
    assert slot2 == 2
    assert page.slot_count == 3

    assert page.get_tuple(0) == data1
    assert page.get_tuple(1) == data2
    assert page.get_tuple(2) == data3

    # Out of bounds slot
    with pytest.raises(IndexError):
        page.get_tuple(99)


def test_slotted_page_update() -> None:
    """Tests in-place update and expanding update."""
    page = SlottedPage(page_id=5)
    s0 = page.insert_tuple(b"Initial Paper Title")

    # In-place update (same or smaller size)
    assert page.update_tuple(s0, b"Updated Title") is True
    assert page.get_tuple(s0) == b"Updated Title"

    # Expanding update (larger size)
    long_title = (
        b"Very Long Updated Title for Next Generation Zero-Trust Network Defense"
    )
    assert page.update_tuple(s0, long_title) is True
    assert page.get_tuple(s0) == long_title


def test_slotted_page_delete_and_slot_reuse() -> None:
    """Tests deletion marking (tombstone) and subsequent slot reuse."""
    page = SlottedPage(page_id=7)
    s0 = page.insert_tuple(b"Paper A")
    s1 = page.insert_tuple(b"Paper B")
    s2 = page.insert_tuple(b"Paper C")
    assert s0 == 0
    assert s2 == 2

    # Delete slot 1
    assert page.delete_tuple(s1) is True
    assert page.get_tuple(s1) is None
    # Deleting again returns False
    assert page.delete_tuple(s1) is False

    # Insert new tuple: should recycle slot 1
    s_new = page.insert_tuple(b"Paper B Replaced")
    assert s_new == s1
    assert page.get_tuple(s1) == b"Paper B Replaced"
    assert page.slot_count == 3  # Count didn't increase


def test_slotted_page_compaction() -> None:
    """Tests in-page defragmentation (VACUUM) reclaiming fragmented space."""
    page = SlottedPage(page_id=9)
    # Insert 10 tuples
    slots = [
        page.insert_tuple(f"Payload Record {i}".encode("utf-8")) for i in range(10)
    ]

    free_before_delete = page.free_space

    # Delete alternating slots (0, 2, 4, 6, 8)
    for i in (0, 2, 4, 6, 8):
        page.delete_tuple(slots[i])

    # Compaction should pull all active records to the bottom and restore contiguous free space
    page.compact()
    assert page.free_space > free_before_delete

    # Verify surviving records remain intact
    for i in (1, 3, 5, 7, 9):
        expected = f"Payload Record {i}".encode("utf-8")
        assert page.get_tuple(slots[i]) == expected


def test_slotted_page_full_error() -> None:
    """Tests that inserting records beyond 4KB raises PageFullError."""
    page = SlottedPage(page_id=12)
    chunk = b"X" * 1000

    page.insert_tuple(chunk)
    page.insert_tuple(chunk)
    page.insert_tuple(chunk)
    page.insert_tuple(chunk)

    # 5th chunk (5000B + slots > 4068B) should fail
    with pytest.raises(PageFullError):
        page.insert_tuple(chunk)


def test_tuple_serializer_all_types() -> None:
    """Tests serialization and deserialization of all supported SQL/Vector data types."""
    schema = [
        ("id", DataType.INT),
        ("score", DataType.FLOAT),
        ("is_active", DataType.BOOL),
        ("title", DataType.VARCHAR),
        ("raw_data", DataType.BYTES),
        ("embedding", DataType.VECTOR),
    ]

    row = {
        "id": 123456789,
        "score": 0.987654321,
        "is_active": True,
        "title": "Quantum-Resistant Lattice Cryptography",
        "raw_data": b"\xde\xad\xbe\xef\x00\xff",
        "embedding": [0.1, -0.25, 0.5, 0.999],
    }

    serialized = TupleSerializer.serialize(schema, row)
    deserialized = TupleSerializer.deserialize(schema, serialized)

    assert deserialized["id"] == row["id"]
    assert pytest.approx(deserialized["score"], 1e-6) == row["score"]
    assert deserialized["is_active"] is True
    assert deserialized["title"] == row["title"]
    assert deserialized["raw_data"] == row["raw_data"]
    assert len(deserialized["embedding"]) == 4
    for orig, actual in zip(row["embedding"], deserialized["embedding"]):
        assert pytest.approx(orig, 1e-5) == actual


def test_tuple_serializer_null_values() -> None:
    """Tests Null-Bitmap handling for rows with NULL columns."""
    schema = [
        ("id", DataType.INT),
        ("title", DataType.VARCHAR),
        ("category", DataType.VARCHAR),
        ("score", DataType.FLOAT),
    ]

    row = {
        "id": 42,
        "title": "Zero-Trust Architecture",
        "category": None,
        "score": None,
    }

    serialized = TupleSerializer.serialize(schema, row)
    deserialized = TupleSerializer.deserialize(schema, serialized)

    assert deserialized["id"] == 42
    assert deserialized["title"] == "Zero-Trust Architecture"
    assert deserialized["category"] is None
    assert deserialized["score"] is None


def test_overflow_manager_multi_page() -> None:
    """Tests multi-page splitting and reading for large payloads exceeding single page."""
    allocator = MockPageAllocator(start_id=201)
    # 10KB large payload
    large_payload = bytes([i % 256 for i in range(10_000)])

    pages = OverflowManager.write_overflow(
        start_page_id=200,
        large_data=large_payload,
        page_allocator=allocator,
    )

    # 10000 / (4096 - 28) = ceil(10000 / 4068) = 3 pages
    assert len(pages) == 3
    assert pages[0].page_id == 200
    assert pages[0].flags == int(PageType.OVERFLOW)
    assert pages[0].next_page_id == 201
    assert pages[1].next_page_id == 202
    assert pages[2].next_page_id == 0

    # Store pages in mock storage
    page_store = {p.page_id: p.serialize() for p in pages}

    def fetcher(pid: int) -> bytes:
        return page_store[pid]

    reassembled = OverflowManager.read_overflow(pages[0], fetcher)
    assert reassembled == large_payload


def test_pager_slotted_page_integration() -> None:
    """Tests end-to-end integration between Pager, VFS, and SlottedPage."""
    vfs = MemoryVFS()
    register_vfs("mem_test_slotted", vfs)
    pager = Pager("test_slotted.db", cache_capacity=10, vfs_name="mem_test_slotted")

    # Create a slotted page, insert rows, and write via Pager
    page0 = SlottedPage(page_id=0, page_type=PageType.DATA)
    s0 = page0.insert_tuple(b"Persistent Paper Record 1")
    s1 = page0.insert_tuple(b"Persistent Paper Record 2")

    pager.write_slotted_page(page0)
    pager.flush_all()

    # Read back through Pager
    read_page0 = pager.read_slotted_page(0)
    assert read_page0.page_id == 0
    assert read_page0.get_tuple(s0) == b"Persistent Paper Record 1"
    assert read_page0.get_tuple(s1) == b"Persistent Paper Record 2"
    assert read_page0.validate_checksum() is True

    pager.close()
