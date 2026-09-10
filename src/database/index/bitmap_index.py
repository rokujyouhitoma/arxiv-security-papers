#!/usr/bin/env python3
"""
Bitmap Index engine backed by RoaringBitmap for low-cardinality database columns.
Provides fast equality, IN-set, and composite Boolean (AND/OR/NOT) query evaluation.
Zero external dependencies: Pure Python 3.14 standard library.
"""

from __future__ import annotations

import json
import struct
from typing import Any, Dict, Iterable, List, Optional, Tuple

from core.structures.roaring_bitmap import RoaringBitmap

BITMAP_INDEX_MAGIC: bytes = b"BMIDX01"
BITMAP_INDEX_VERSION: int = 1


def _normalize_key(val: Any) -> str:
    """Normalizes arbitrary column values into deterministic index dictionary keys."""
    if val is None:
        return "__NULL__"
    if isinstance(val, (int, float, str, bool)):
        return str(val)
    if isinstance(val, (list, tuple, dict)):
        return json.dumps(val, sort_keys=True, ensure_ascii=False)
    return str(val)


def _parse_bmidx_header(data: bytes) -> Tuple[Dict[str, Any], int]:
    if len(data) < 12:
        raise ValueError("Corrupt byte stream: insufficient header length")
    magic, version, meta_len = struct.unpack_from("<7sBI", data, 0)
    if magic != BITMAP_INDEX_MAGIC:
        raise ValueError(f"Invalid magic bytes: {magic!r}")
    if version != BITMAP_INDEX_VERSION:
        raise ValueError(f"Unsupported format version: {version}")
    offset = 12
    meta_bytes = data[offset : offset + meta_len]
    meta: Dict[str, Any] = json.loads(meta_bytes.decode("utf-8"))
    return meta, offset + meta_len


class RoaringBitmapIndex:
    """
    Bitmap Index on a specific database table column using RoaringBitmap.
    Maps distinct column values to sets of matching RowIDs.
    """

    def __init__(self, column_name: str, cardinality_threshold: int = 10000) -> None:
        self.column_name: str = column_name
        self.cardinality_threshold: int = cardinality_threshold
        self._bitmaps: Dict[str, RoaringBitmap] = {}

    def insert(self, val: Any, row_id: int) -> None:
        """Indexes row_id under the given column value."""
        norm_key = _normalize_key(val)
        if norm_key not in self._bitmaps:
            if len(self._bitmaps) >= self.cardinality_threshold:
                raise ValueError(
                    f"Column '{self.column_name}' exceeded cardinality threshold "
                    f"({self.cardinality_threshold})"
                )
            self._bitmaps[norm_key] = RoaringBitmap()
        self._bitmaps[norm_key].add(row_id)

    def delete(self, val: Any, row_id: int) -> None:
        """Removes row_id from the given column value index."""
        norm_key = _normalize_key(val)
        if norm_key in self._bitmaps:
            self._bitmaps[norm_key].discard(row_id)
            if self._bitmaps[norm_key].is_empty():
                del self._bitmaps[norm_key]

    def lookup(self, val: Any) -> RoaringBitmap:
        """Returns a cloned RoaringBitmap of RowIDs matching val."""
        norm_key = _normalize_key(val)
        bm = self._bitmaps.get(norm_key)
        return bm.clone() if bm is not None else RoaringBitmap()

    def lookup_in(self, values: Iterable[Any]) -> RoaringBitmap:
        """Returns union (OR) of RowIDs matching any of the given values."""
        res = RoaringBitmap()
        for v in values:
            norm_key = _normalize_key(v)
            bm = self._bitmaps.get(norm_key)
            if bm is not None:
                res = res | bm
        return res

    def all_rows(self) -> RoaringBitmap:
        """Returns union of all indexed RowIDs."""
        res = RoaringBitmap()
        for bm in self._bitmaps.values():
            res = res | bm
        return res

    def cardinality(self) -> int:
        """Returns count of distinct indexed values."""
        return len(self._bitmaps)

    def to_bytes(self) -> bytes:
        """Serializes bitmap index into compact binary format."""
        keys = sorted(self._bitmaps.keys())
        meta_dict = {
            "col": self.column_name,
            "threshold": self.cardinality_threshold,
            "keys": keys,
        }
        meta_bytes = json.dumps(meta_dict, ensure_ascii=False).encode("utf-8")
        header = struct.pack(
            "<7sBI", BITMAP_INDEX_MAGIC, BITMAP_INDEX_VERSION, len(meta_bytes)
        )
        payloads: List[bytes] = []
        for k in keys:
            b_bytes = self._bitmaps[k].to_bytes()
            payloads.append(struct.pack("<I", len(b_bytes)) + b_bytes)
        return header + meta_bytes + b"".join(payloads)

    @classmethod
    def from_bytes(cls, data: bytes) -> RoaringBitmapIndex:
        """Deserializes a RoaringBitmapIndex from compact binary format."""
        meta, offset = _parse_bmidx_header(data)
        idx = cls(meta["col"], meta["threshold"])
        for k in meta["keys"]:
            if offset + 4 > len(data):
                raise ValueError("Corrupt byte stream: truncated bitmap payload length")
            bm_len = struct.unpack_from("<I", data, offset)[0]
            offset += 4
            bm_data = data[offset : offset + bm_len]
            idx._bitmaps[k] = RoaringBitmap.from_bytes(bm_data)
            offset += bm_len
        return idx


class TableBitmapIndexes:
    """
    Manages multiple column RoaringBitmapIndexes for a database table.
    Coordinates multi-column Boolean query filtering (AND / OR / NOT).
    """

    def __init__(self) -> None:
        self._indexes: Dict[str, RoaringBitmapIndex] = {}

    def add_index(
        self, column_name: str, cardinality_threshold: int = 10000
    ) -> RoaringBitmapIndex:
        """Creates and registers a new bitmap index for column_name."""
        idx = RoaringBitmapIndex(column_name, cardinality_threshold)
        self._indexes[column_name] = idx
        return idx

    def get_index(self, column_name: str) -> Optional[RoaringBitmapIndex]:
        """Retrieves index for column_name if exists."""
        return self._indexes.get(column_name)

    def insert_row(self, row_id: int, row_data: Dict[str, Any]) -> None:
        """Inserts row_id into all applicable column bitmap indexes."""
        for col, val in row_data.items():
            idx = self._indexes.get(col)
            if idx is not None:
                idx.insert(val, row_id)

    def delete_row(self, row_id: int, row_data: Dict[str, Any]) -> None:
        """Removes row_id from all applicable column bitmap indexes."""
        for col, val in row_data.items():
            idx = self._indexes.get(col)
            if idx is not None:
                idx.delete(val, row_id)

    def _lookup_col(self, col: str, val: Any) -> RoaringBitmap:
        idx = self._indexes.get(col)
        return idx.lookup(val) if idx is not None else RoaringBitmap()

    def eval_and(self, conditions: Dict[str, Any]) -> RoaringBitmap:
        """
        Evaluates composite equality conditions with bitwise AND.
        Example: {'severity': 'CRITICAL', 'status': 'OPEN'}
        """
        if not conditions:
            return RoaringBitmap()
        res: Optional[RoaringBitmap] = None
        for col, val in conditions.items():
            bm = self._lookup_col(col, val)
            res = bm if res is None else (res & bm)
        return res if res is not None else RoaringBitmap()

    def eval_or(self, conditions: Dict[str, Any]) -> RoaringBitmap:
        """
        Evaluates composite equality conditions with bitwise OR.
        Example: {'severity': 'CRITICAL', 'category': 'cs.CR'}
        """
        res = RoaringBitmap()
        for col, val in conditions.items():
            idx = self._indexes.get(col)
            if idx is not None:
                res = res | idx.lookup(val)
        return res

    def eval_not(
        self,
        column_name: str,
        val: Any,
        all_rows: Optional[RoaringBitmap] = None,
    ) -> RoaringBitmap:
        """
        Evaluates NOT condition: all_rows - lookup(val).
        """
        idx = self._indexes.get(column_name)
        if idx is None:
            return all_rows.clone() if all_rows is not None else RoaringBitmap()
        matched = idx.lookup(val)
        universe = all_rows if all_rows is not None else idx.all_rows()
        return universe - matched
