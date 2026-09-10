#!/usr/bin/env python3
"""
Lucene-style Immutable Segment Model & Deletion Bitset.
"""

from typing import Dict, Union

from core.structures.roaring_bitmap import RoaringBitmap


class DeletedDocsBitset:
    """Tracks logically deleted doc IDs within an immutable segment using Roaring Bitmap."""

    def __init__(self) -> None:
        self._bitmap = RoaringBitmap()
        self._str_map: Dict[str, int] = {}
        self._next_id: int = 0

    def _resolve_id(self, doc_id: Union[str, int]) -> int:
        if isinstance(doc_id, int):
            return doc_id
        if doc_id.isdigit():
            return int(doc_id)
        if doc_id not in self._str_map:
            self._str_map[doc_id] = self._next_id
            self._next_id += 1
        return self._str_map[doc_id]

    def mark_deleted(self, doc_id: Union[str, int]) -> None:
        num_id = self._resolve_id(doc_id)
        self._bitmap.add(num_id)

    def is_deleted(self, doc_id: Union[str, int]) -> bool:
        if isinstance(doc_id, int):
            return doc_id in self._bitmap
        if doc_id.isdigit():
            return int(doc_id) in self._bitmap
        num_id = self._str_map.get(doc_id)
        return num_id in self._bitmap if num_id is not None else False

    def count(self) -> int:
        return len(self._bitmap)


class SegmentInfo:
    """Metadata describing a single immutable index segment."""

    def __init__(self, segment_id: str, doc_count: int, version: int = 1) -> None:
        self.segment_id = segment_id
        self.doc_count = doc_count
        self.version = version

    def __repr__(self) -> str:
        return f"SegmentInfo(id='{self.segment_id}', docs={self.doc_count}, v={self.version})"
