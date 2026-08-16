#!/usr/bin/env python3
"""
Lucene-style Immutable Segment Model & Deletion Bitset.
"""

from typing import Set


class DeletedDocsBitset:
    """Tracks logically deleted doc IDs within an immutable segment."""

    def __init__(self) -> None:
        self.deleted_set: Set[str] = set()

    def mark_deleted(self, doc_id: str) -> None:
        self.deleted_set.add(doc_id)

    def is_deleted(self, doc_id: str) -> bool:
        return doc_id in self.deleted_set

    def count(self) -> int:
        return len(self.deleted_set)


class SegmentInfo:
    """Metadata describing a single immutable index segment."""

    def __init__(self, segment_id: str, doc_count: int, version: int = 1) -> None:
        self.segment_id = segment_id
        self.doc_count = doc_count
        self.version = version

    def __repr__(self) -> str:
        return f"SegmentInfo(id='{self.segment_id}', docs={self.doc_count}, v={self.version})"
