#!/usr/bin/env python3
"""
Visibility Map (Tombstone & Liveness Tracking) using RoaringBitmap.
Coordinates fast tuple liveness evaluation, index candidate filtering, and VACUUM compaction.
Zero external dependencies: Pure Python 3.14 standard library.
"""

from __future__ import annotations

import struct

from core.structures.roaring_bitmap import RoaringBitmap

VISIBILITY_MAP_MAGIC: bytes = b"VISMAP1"
VISIBILITY_MAP_VERSION: int = 1


class VisibilityMap:
    """
    Tracks database tuple liveness and tombstones using RoaringBitmap.
    Provides sub-microsecond visibility checks and batch set-difference filtering.
    """

    def __init__(self) -> None:
        self._live_rows: RoaringBitmap = RoaringBitmap()
        self._tombstones: RoaringBitmap = RoaringBitmap()

    def mark_inserted(self, row_id: int) -> None:
        """Marks row_id as live (inserted)."""
        self._live_rows.add(row_id)
        self._tombstones.discard(row_id)

    def mark_deleted(self, row_id: int) -> None:
        """Marks row_id as deleted (tombstone)."""
        self._tombstones.add(row_id)
        self._live_rows.discard(row_id)

    def is_visible(self, row_id: int) -> bool:
        """Returns True if row_id is currently live and not deleted."""
        return (row_id in self._live_rows) and (row_id not in self._tombstones)

    def filter_visible(self, candidates: RoaringBitmap) -> RoaringBitmap:
        """
        Filters candidates by subtracting tombstones using RoaringBitmap difference.
        Returns a new RoaringBitmap containing only live RowIDs.
        """
        return candidates - self._tombstones

    def live_count(self) -> int:
        """Returns total count of currently live rows."""
        return len(self._live_rows)

    def tombstone_count(self) -> int:
        """Returns total count of tombstone rows."""
        return len(self._tombstones)

    def get_live_rows(self) -> RoaringBitmap:
        """Returns a clone of live rows bitmap."""
        return self._live_rows.clone()

    def get_tombstones(self) -> RoaringBitmap:
        """Returns a clone of tombstones bitmap."""
        return self._tombstones.clone()

    def vacuum_compact(self, retained_rows: RoaringBitmap) -> None:
        """
        Applies VACUUM compaction: sets live rows to retained_rows and clears tombstones.
        """
        self._live_rows = retained_rows.clone()
        self._tombstones.clear()

    def to_bytes(self) -> bytes:
        """Serializes VisibilityMap to binary format."""
        live_bytes = self._live_rows.to_bytes()
        tomb_bytes = self._tombstones.to_bytes()
        header = struct.pack(
            "<7sBII",
            VISIBILITY_MAP_MAGIC,
            VISIBILITY_MAP_VERSION,
            len(live_bytes),
            len(tomb_bytes),
        )
        return header + live_bytes + tomb_bytes

    @classmethod
    def from_bytes(cls, data: bytes) -> VisibilityMap:
        """Deserializes VisibilityMap from binary format."""
        if len(data) < 16:
            raise ValueError("Corrupt byte stream: insufficient header length")
        magic, version, live_len, tomb_len = struct.unpack_from("<7sBII", data, 0)
        if magic != VISIBILITY_MAP_MAGIC:
            raise ValueError(f"Invalid magic bytes: {magic!r}")
        if version != VISIBILITY_MAP_VERSION:
            raise ValueError(f"Unsupported format version: {version}")

        offset = 16
        if offset + live_len + tomb_len > len(data):
            raise ValueError("Corrupt byte stream: truncated payload")

        vmap = cls()
        vmap._live_rows = RoaringBitmap.from_bytes(data[offset : offset + live_len])
        offset += live_len
        vmap._tombstones = RoaringBitmap.from_bytes(data[offset : offset + tomb_len])
        return vmap
