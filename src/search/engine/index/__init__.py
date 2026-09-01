#!/usr/bin/env python3
"""
Index Storage, Inverted Index, VByte Compression, and Segment Management (Lucene Paradigm).
"""

import struct
from typing import Any, Dict, List, Optional, Set


def encode_vbyte(numbers: List[int]) -> bytes:
    """Encodes a list of positive integers using Variable Byte (VByte) encoding."""
    out = bytearray()
    for n in numbers:
        if n < 0:
            raise ValueError(f"VByte only supports non-negative integers: {n}")
        val = n
        while val >= 128:
            out.append((val & 0x7F) | 0x80)
            val >>= 7
        out.append(val & 0x7F)
    return bytes(out)


def decode_vbyte(data: bytes) -> List[int]:
    """Decodes a byte sequence into a list of integers using Variable Byte (VByte) decoding."""
    numbers: List[int] = []
    current = 0
    shift = 0
    for byte in data:
        current |= (byte & 0x7F) << shift
        if (byte & 0x80) == 0:
            numbers.append(current)
            current = 0
            shift = 0
        else:
            shift += 7
    return numbers


def encode_gap_vbyte(sorted_doc_ids: List[int]) -> bytes:
    """Encodes a sorted list of doc_ids using delta (gap) compression and VByte."""
    if not sorted_doc_ids:
        return b""
    gaps = [sorted_doc_ids[0]]
    for i in range(1, len(sorted_doc_ids)):
        gaps.append(sorted_doc_ids[i] - sorted_doc_ids[i - 1])
    return encode_vbyte(gaps)


def decode_gap_vbyte(data: bytes) -> List[int]:
    """Decodes a delta-compressed VByte byte stream back to sorted doc_ids."""
    if not data:
        return []
    gaps = decode_vbyte(data)
    if not gaps:
        return []
    doc_ids = [gaps[0]]
    for i in range(1, len(gaps)):
        doc_ids.append(doc_ids[i - 1] + gaps[i])
    return doc_ids


class PostingEntry:
    """Posting list entry containing document ID, term frequency, and term positions."""

    __slots__ = ("doc_id", "tf", "positions")

    def __init__(
        self, doc_id: int, tf: int = 1, positions: Optional[List[int]] = None
    ) -> None:
        self.doc_id = doc_id
        self.tf = tf
        self.positions: List[int] = positions or []

    def to_dict(self) -> Dict[str, Any]:
        return {"doc_id": self.doc_id, "tf": self.tf, "positions": self.positions}

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "PostingEntry":
        return cls(
            doc_id=data["doc_id"],
            tf=data.get("tf", 1),
            positions=data.get("positions", []),
        )


class PostingsList:
    """
    Inverted Index Postings List for a term with optional VByte gap-compressed memory storage.
    """

    def __init__(self, term: str) -> None:
        self.term = term
        self.postings: Dict[int, PostingEntry] = {}
        self._compressed_cache: Optional[bytes] = None

    def add(self, doc_id: int, position: Optional[int] = None) -> None:
        self._compressed_cache = None
        if doc_id not in self.postings:
            self.postings[doc_id] = PostingEntry(
                doc_id, tf=1, positions=[position] if position is not None else []
            )
        else:
            entry = self.postings[doc_id]
            entry.tf += 1
            if position is not None:
                entry.positions.append(position)

    def doc_freq(self) -> int:
        return len(self.postings)

    def get_postings(self) -> List[PostingEntry]:
        return sorted(self.postings.values(), key=lambda p: p.doc_id)

    def compress(self) -> bytes:
        """Compresses the sorted doc_ids and frequencies using VByte."""
        sorted_entries = self.get_postings()
        doc_ids = [e.doc_id for e in sorted_entries]
        tfs = [e.tf for e in sorted_entries]
        doc_bytes = encode_gap_vbyte(doc_ids)
        tf_bytes = encode_vbyte(tfs)
        # Header: doc_bytes_len (4 bytes) + doc_bytes + tf_bytes
        self._compressed_cache = (
            struct.pack("<I", len(doc_bytes)) + doc_bytes + tf_bytes
        )
        return self._compressed_cache

    def decompress(self) -> List[PostingEntry]:
        """Decompresses posting entries from compressed bytes."""
        if not self._compressed_cache:
            return self.get_postings()
        doc_len = struct.unpack("<I", self._compressed_cache[:4])[0]
        doc_bytes = self._compressed_cache[4 : 4 + doc_len]
        tf_bytes = self._compressed_cache[4 + doc_len :]
        doc_ids = decode_gap_vbyte(doc_bytes)
        tfs = decode_vbyte(tf_bytes)
        return [PostingEntry(doc_id=d, tf=t) for d, t in zip(doc_ids, tfs)]


class DocValues:
    """Columnar in-memory storage for high-speed faceting, filtering, and sorting."""

    def __init__(self, name: str) -> None:
        self.name = name
        self._values: Dict[int, Any] = {}

    def set(self, doc_id: int, value: Any) -> None:
        self._values[doc_id] = value

    def get(self, doc_id: int) -> Optional[Any]:
        return self._values.get(doc_id)

    def get_all(self) -> Dict[int, Any]:
        return self._values


class StoredFields:
    """Row-oriented document storage for raw metadata and snippet extraction."""

    def __init__(self) -> None:
        self._docs: Dict[int, Dict[str, Any]] = {}

    def put(self, doc_id: int, fields: Dict[str, Any]) -> None:
        self._docs[doc_id] = dict(fields)

    def get(self, doc_id: int) -> Optional[Dict[str, Any]]:
        return self._docs.get(doc_id)

    def __len__(self) -> int:
        return len(self._docs)


class DeletedDocsBitset:
    """Bitset tracking tombstoned/deleted document IDs."""

    def __init__(self) -> None:
        self._deleted: Set[int] = set()

    def delete(self, doc_id: int) -> None:
        self._deleted.add(doc_id)

    def is_deleted(self, doc_id: int) -> bool:
        return doc_id in self._deleted

    def count(self) -> int:
        return len(self._deleted)


class Segment:
    """
    Immutable Index Segment containing Postings, DocValues, and StoredFields.
    """

    def __init__(self, segment_id: str) -> None:
        self.segment_id = segment_id
        self.postings: Dict[str, PostingsList] = {}
        self.doc_values: Dict[str, DocValues] = {}
        self.stored_fields = StoredFields()
        self.deleted_docs = DeletedDocsBitset()
        self.doc_count = 0
        self.field_lengths: Dict[str, Dict[int, int]] = {}

    def __repr__(self) -> str:
        return f"Segment(id='{self.segment_id}', docs={self.doc_count}, live={self.live_docs_count()})"

    def _store_doc_values(self, doc_id: int, fields: Dict[str, Any]) -> None:
        for fname, val in fields.items():
            if fname not in self.doc_values:
                self.doc_values[fname] = DocValues(fname)
            self.doc_values[fname].set(doc_id, val)

    def _store_postings_field(self, doc_id: int, fname: str, tokens: List[str]) -> None:
        if fname not in self.field_lengths:
            self.field_lengths[fname] = {}
        self.field_lengths[fname][doc_id] = len(tokens)

        for pos, token in enumerate(tokens):
            key = f"{fname}:{token}"
            if key not in self.postings:
                self.postings[key] = PostingsList(key)
            self.postings[key].add(doc_id, position=pos)

    def add_document(
        self, doc_id: int, fields: Dict[str, Any], analyzed_fields: Dict[str, List[str]]
    ) -> None:
        self.stored_fields.put(doc_id, fields)
        self.doc_count = max(self.doc_count, doc_id + 1)
        self._store_doc_values(doc_id, fields)

        for fname, tokens in analyzed_fields.items():
            self._store_postings_field(doc_id, fname, tokens)

    def is_deleted(self, doc_id: int) -> bool:
        return self.deleted_docs.is_deleted(doc_id)

    def live_docs_count(self) -> int:
        return self.doc_count - self.deleted_docs.count()


class TieredMergePolicy:
    """
    Tiered Merge Policy that evaluates and merges small immutable segments into larger segments.
    """

    def __init__(
        self, max_segments: int = 10, max_merged_segment_docs: int = 50000
    ) -> None:
        self.max_segments = max_segments
        self.max_merged_segment_docs = max_merged_segment_docs

    def find_merges(self, segments: List[Segment]) -> List[List[Segment]]:
        """Finds candidate segments for compaction and merging."""
        active = [s for s in segments if s.live_docs_count() > 0]
        if len(active) <= self.max_segments:
            return []
        # Group smallest segments
        sorted_segs = sorted(active, key=lambda s: s.live_docs_count())
        candidates = sorted_segs[: self.max_segments]
        return [candidates]

    def merge_segments(
        self, segments_to_merge: List[Segment], new_segment_id: str
    ) -> Segment:
        """Merges multiple segments into a single consolidated segment."""
        merged = Segment(new_segment_id)
        doc_id_offset = 0

        for seg in segments_to_merge:
            for old_doc_id in range(seg.doc_count):
                if seg.is_deleted(old_doc_id):
                    continue
                new_doc_id = doc_id_offset + old_doc_id
                stored = seg.stored_fields.get(old_doc_id) or {}
                merged.stored_fields.put(new_doc_id, stored)
                self._merge_doc_values(seg, merged, old_doc_id, new_doc_id)
                self._merge_postings(seg, merged, old_doc_id, new_doc_id)

            doc_id_offset += seg.doc_count
        merged.doc_count = doc_id_offset
        return merged

    def _merge_doc_values(
        self, src: Segment, dst: Segment, old_id: int, new_id: int
    ) -> None:
        for dv_name, dv in src.doc_values.items():
            val = dv.get(old_id)
            if val is not None:
                if dv_name not in dst.doc_values:
                    dst.doc_values[dv_name] = DocValues(dv_name)
                dst.doc_values[dv_name].set(new_id, val)

    def _append_posting_entry(
        self, dst: Segment, pkey: str, new_id: int, entry: PostingEntry
    ) -> None:
        if pkey not in dst.postings:
            dst.postings[pkey] = PostingsList(pkey)
        for pos in entry.positions:
            dst.postings[pkey].add(new_id, position=pos)
        if not entry.positions:
            for _ in range(entry.tf):
                dst.postings[pkey].add(new_id, position=None)

    def _merge_postings(
        self, src: Segment, dst: Segment, old_id: int, new_id: int
    ) -> None:
        for pkey, plist in src.postings.items():
            entry = plist.postings.get(old_id)
            if entry:
                self._append_posting_entry(dst, pkey, new_id, entry)
