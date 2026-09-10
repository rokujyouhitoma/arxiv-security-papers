#!/usr/bin/env python3
"""
Pure-Python 32-bit Roaring Bitmap implementation.
Provides space-efficient and fast set operations for document ID tracking,
segment deletions (DeletedDocsBitset), and inverted index evaluation.
Zero external dependencies: Pure Python 3.14 standard library.
"""

from __future__ import annotations

import array
import bisect
import struct
from abc import ABC, abstractmethod
from typing import Any, Dict, Iterator, List, Optional, Set, Tuple

# Constants
SERIAL_COOKIE: int = 0x29380001
CHUNK_SIZE: int = 65536
ARRAY_MAX_CAPACITY: int = 4096
BITMAP_WORDS: int = 1024  # 1024 * 64 = 65536 bits

TYPE_ARRAY: int = 1
TYPE_BITMAP: int = 2
TYPE_RUN: int = 3


class Container(ABC):
    """Abstract base container for 16-bit values within a Roaring Bitmap chunk."""

    @abstractmethod
    def get_cardinality(self) -> int:
        """Returns the number of elements in this container."""

    @abstractmethod
    def contains(self, val: int) -> bool:
        """Checks if a 16-bit value is present."""

    @abstractmethod
    def add(self, val: int) -> Container:
        """Adds value and returns updated (or promoted) container."""

    @abstractmethod
    def remove(self, val: int) -> Container:
        """Removes value and returns updated (or demoted) container."""

    @abstractmethod
    def to_list(self) -> List[int]:
        """Returns all elements as a sorted list."""

    @abstractmethod
    def to_bytes(self) -> bytes:
        """Serializes container to raw byte stream."""

    @abstractmethod
    def container_type(self) -> int:
        """Returns container type tag."""

    @abstractmethod
    def clone(self) -> Container:
        """Creates a deep copy of this container."""

    @abstractmethod
    def get_size_in_bytes(self) -> int:
        """Returns approximate memory footprint in bytes."""

    def is_empty(self) -> bool:
        return self.get_cardinality() == 0

    def __len__(self) -> int:
        return self.get_cardinality()

    def __iter__(self) -> Iterator[int]:
        return iter(self.to_list())

    def __contains__(self, val: int) -> bool:
        return self.contains(val)


class ArrayContainer(Container):
    """
    Container storing up to 4096 sorted 16-bit unsigned integers.
    Memory: 2 * n bytes.
    """

    def __init__(self, initial_values: Optional[List[int]] = None) -> None:
        self._data: array.array[int] = array.array("H")
        if initial_values:
            self._data.extend(sorted(set(initial_values)))

    def get_cardinality(self) -> int:
        return len(self._data)

    def container_type(self) -> int:
        return TYPE_ARRAY

    def contains(self, val: int) -> bool:
        idx = bisect.bisect_left(self._data, val)
        return idx < len(self._data) and self._data[idx] == val

    def _promote_to_bitmap(self, new_val: int) -> BitmapContainer:
        bitmap = BitmapContainer()
        for v in self._data:
            bitmap.add(v)
        bitmap.add(new_val)
        return bitmap

    def add(self, val: int) -> Container:
        idx = bisect.bisect_left(self._data, val)
        if idx < len(self._data) and self._data[idx] == val:
            return self
        if len(self._data) >= ARRAY_MAX_CAPACITY:
            return self._promote_to_bitmap(val)
        self._data.insert(idx, val)
        return self

    def remove(self, val: int) -> Container:
        idx = bisect.bisect_left(self._data, val)
        if idx < len(self._data) and self._data[idx] == val:
            del self._data[idx]
        return self

    def to_list(self) -> List[int]:
        return list(self._data)

    def to_bytes(self) -> bytes:
        return self._data.tobytes()

    def clone(self) -> ArrayContainer:
        cloned = ArrayContainer()
        cloned._data = array.array("H", self._data)
        return cloned

    def get_size_in_bytes(self) -> int:
        return len(self._data) * 2 + 64


class BitmapContainer(Container):
    """
    Container storing dense values as a 65,536-bit bitset (1024 64-bit words).
    Memory: 8,192 bytes fixed.
    """

    def __init__(self) -> None:
        self._words: array.array[int] = array.array("Q", [0] * BITMAP_WORDS)
        self._cardinality: int = 0

    def get_cardinality(self) -> int:
        return self._cardinality

    def container_type(self) -> int:
        return TYPE_BITMAP

    def contains(self, val: int) -> bool:
        word_idx = val >> 6
        bit_mask = 1 << (val & 63)
        return bool(self._words[word_idx] & bit_mask)

    def add(self, val: int) -> Container:
        word_idx = val >> 6
        bit_mask = 1 << (val & 63)
        if not (self._words[word_idx] & bit_mask):
            self._words[word_idx] |= bit_mask
            self._cardinality += 1
        return self

    def _demote_to_array(self) -> ArrayContainer:
        arr = ArrayContainer()
        arr._data.extend(self.to_list())
        return arr

    def remove(self, val: int) -> Container:
        word_idx = val >> 6
        bit_mask = 1 << (val & 63)
        if self._words[word_idx] & bit_mask:
            self._words[word_idx] &= ~bit_mask
            self._cardinality -= 1
            if self._cardinality <= ARRAY_MAX_CAPACITY:
                return self._demote_to_array()
        return self

    def to_list(self) -> List[int]:
        res: List[int] = []
        for word_idx, w in enumerate(self._words):
            if w:
                _extract_word_bits(word_idx, w, res)
        return res

    def to_bytes(self) -> bytes:
        return self._words.tobytes()

    def clone(self) -> BitmapContainer:
        cloned = BitmapContainer()
        cloned._words = array.array("Q", self._words)
        cloned._cardinality = self._cardinality
        return cloned

    def get_size_in_bytes(self) -> int:
        return 8192 + 64


def _extract_word_bits(word_idx: int, word: int, out: List[int]) -> None:
    base = word_idx << 6
    w = word
    while w:
        bit = (w & -w).bit_length() - 1
        out.append(base | bit)
        w ^= 1 << bit


class RunContainer(Container):
    """
    Container encoding runs of consecutive 16-bit integers as (start, length).
    Particularly space-efficient for range and contiguous deletions.
    """

    def __init__(self) -> None:
        self._runs: array.array[int] = array.array("H")  # pairs [start, len]
        self._cardinality: int = 0

    def get_cardinality(self) -> int:
        return self._cardinality

    def container_type(self) -> int:
        return TYPE_RUN

    def contains(self, val: int) -> bool:
        n = len(self._runs) >> 1
        for i in range(n):
            start = self._runs[i * 2]
            length = self._runs[i * 2 + 1]
            if start <= val <= start + length:
                return True
        return False

    def add(self, val: int) -> Container:
        if self.contains(val):
            return self
        arr = ArrayContainer(self.to_list())
        return arr.add(val)

    def remove(self, val: int) -> Container:
        if not self.contains(val):
            return self
        arr = ArrayContainer(self.to_list())
        return arr.remove(val)

    def to_list(self) -> List[int]:
        res: List[int] = []
        n = len(self._runs) >> 1
        for i in range(n):
            start = self._runs[i * 2]
            length = self._runs[i * 2 + 1]
            res.extend(range(start, start + length + 1))
        return res

    def to_bytes(self) -> bytes:
        return self._runs.tobytes()

    def clone(self) -> RunContainer:
        cloned = RunContainer()
        cloned._runs = array.array("H", self._runs)
        cloned._cardinality = self._cardinality
        return cloned

    def get_size_in_bytes(self) -> int:
        return len(self._runs) * 2 + 64


def _and_arrays(a1: ArrayContainer, a2: ArrayContainer) -> ArrayContainer:
    res = ArrayContainer()
    d1, d2 = a1._data, a2._data
    i, j, n1, n2 = 0, 0, len(d1), len(d2)
    while i < n1 and j < n2:
        v1, v2 = d1[i], d2[j]
        if v1 == v2:
            res._data.append(v1)
            i += 1
            j += 1
        elif v1 < v2:
            i += 1
        else:
            j += 1
    return res


def _and_bitmaps(b1: BitmapContainer, b2: BitmapContainer) -> Container:
    res = BitmapContainer()
    card = 0
    for idx in range(BITMAP_WORDS):
        w = b1._words[idx] & b2._words[idx]
        res._words[idx] = w
        card += w.bit_count()
    res._cardinality = card
    if card < ARRAY_MAX_CAPACITY:
        return res._demote_to_array()
    return res


def _or_bitmaps(b1: BitmapContainer, b2: BitmapContainer) -> BitmapContainer:
    res = BitmapContainer()
    card = 0
    for idx in range(BITMAP_WORDS):
        w = b1._words[idx] | b2._words[idx]
        res._words[idx] = w
        card += w.bit_count()
    res._cardinality = card
    return res


def _sub_bitmaps(b1: BitmapContainer, b2: BitmapContainer) -> Container:
    res = BitmapContainer()
    card = 0
    for idx in range(BITMAP_WORDS):
        w = b1._words[idx] & ~b2._words[idx]
        res._words[idx] = w
        card += w.bit_count()
    res._cardinality = card
    if card < ARRAY_MAX_CAPACITY:
        return res._demote_to_array()
    return res


def _sub_arrays(a1: ArrayContainer, a2: ArrayContainer) -> ArrayContainer:
    res = ArrayContainer()
    s2 = set(a2._data)
    for v in a1._data:
        if v not in s2:
            res._data.append(v)
    return res


def _make_bitmap_from_list(values: List[int]) -> BitmapContainer:
    bmp = BitmapContainer()
    for v in values:
        bmp.add(v)
    return bmp


def _and_generic(c1: Container, c2: Container) -> Container:
    s1, s2 = set(c1.to_list()), set(c2.to_list())
    inter = sorted(s1 & s2)
    if len(inter) >= ARRAY_MAX_CAPACITY:
        return _make_bitmap_from_list(inter)
    return ArrayContainer(inter)


def _and_container(c1: Container, c2: Container) -> Container:
    if isinstance(c1, ArrayContainer) and isinstance(c2, ArrayContainer):
        return _and_arrays(c1, c2)
    if isinstance(c1, BitmapContainer) and isinstance(c2, BitmapContainer):
        return _and_bitmaps(c1, c2)
    return _and_generic(c1, c2)


def _or_generic(c1: Container, c2: Container) -> Container:
    s1, s2 = set(c1.to_list()), set(c2.to_list())
    un = sorted(s1 | s2)
    if len(un) >= ARRAY_MAX_CAPACITY:
        return _make_bitmap_from_list(un)
    return ArrayContainer(un)


def _or_container(c1: Container, c2: Container) -> Container:
    if isinstance(c1, BitmapContainer) and isinstance(c2, BitmapContainer):
        return _or_bitmaps(c1, c2)
    return _or_generic(c1, c2)


def _sub_generic(c1: Container, c2: Container) -> Container:
    s1, s2 = set(c1.to_list()), set(c2.to_list())
    diff = sorted(s1 - s2)
    if len(diff) >= ARRAY_MAX_CAPACITY:
        return _make_bitmap_from_list(diff)
    return ArrayContainer(diff)


def _sub_container(c1: Container, c2: Container) -> Container:
    if isinstance(c1, BitmapContainer) and isinstance(c2, BitmapContainer):
        return _sub_bitmaps(c1, c2)
    if isinstance(c1, ArrayContainer) and isinstance(c2, ArrayContainer):
        return _sub_arrays(c1, c2)
    return _sub_generic(c1, c2)


class RoaringBitmap:
    """
    Pure-Python 32-bit Roaring Bitmap.
    Partitions 32-bit unsigned integer keys into 16-bit chunks and containers.
    Provides fast, compressed set operations and memory-efficient cardinality tracking.
    """

    def __init__(self, initial_values: Optional[List[int]] = None) -> None:
        self._chunks: Dict[int, Container] = {}
        if initial_values:
            for val in initial_values:
                self.add(val)

    def _validate_val(self, x: int) -> None:
        if not (0 <= x < 0x100000000):
            raise ValueError(f"Value {x} out of 32-bit unsigned range [0, 2^32)")

    def add(self, x: int) -> None:
        """Inserts a 32-bit unsigned integer into the bitmap."""
        self._validate_val(x)
        key = x >> 16
        val = x & 0xFFFF
        if key not in self._chunks:
            self._chunks[key] = ArrayContainer([val])
        else:
            self._chunks[key] = self._chunks[key].add(val)

    def remove(self, x: int) -> None:
        """Removes a 32-bit unsigned integer. Raises KeyError if not found."""
        self._validate_val(x)
        key = x >> 16
        val = x & 0xFFFF
        if key not in self._chunks or not self._chunks[key].contains(val):
            raise KeyError(x)
        container = self._chunks[key].remove(val)
        if container.is_empty():
            del self._chunks[key]
        else:
            self._chunks[key] = container

    def discard(self, x: int) -> None:
        """Removes an integer safely if present without raising error."""
        try:
            self.remove(x)
        except (KeyError, ValueError):
            pass

    def contains(self, x: int) -> bool:
        """Checks if a 32-bit integer is present."""
        if not (0 <= x < 0x100000000):
            return False
        key = x >> 16
        container = self._chunks.get(key)
        return container.contains(x & 0xFFFF) if container is not None else False

    def __contains__(self, x: int) -> bool:
        return self.contains(x)

    def __len__(self) -> int:
        return sum(c.get_cardinality() for c in self._chunks.values())

    def __bool__(self) -> bool:
        return len(self) > 0

    def is_empty(self) -> bool:
        return len(self) == 0

    def clear(self) -> None:
        self._chunks.clear()

    def __iter__(self) -> Iterator[int]:
        for key in sorted(self._chunks.keys()):
            base = key << 16
            for val in self._chunks[key]:
                yield base | val

    def to_list(self) -> List[int]:
        return list(self)

    def to_set(self) -> Set[int]:
        return set(self)

    def clone(self) -> RoaringBitmap:
        cloned = RoaringBitmap()
        for k, c in self._chunks.items():
            cloned._chunks[k] = c.clone()
        return cloned

    def intersection(self, other: RoaringBitmap) -> RoaringBitmap:
        """Returns the intersection (AND) of two RoaringBitmaps."""
        res = RoaringBitmap()
        common_keys = set(self._chunks.keys()) & set(other._chunks.keys())
        for key in common_keys:
            c = _and_container(self._chunks[key], other._chunks[key])
            if not c.is_empty():
                res._chunks[key] = c
        return res

    def union(self, other: RoaringBitmap) -> RoaringBitmap:
        """Returns the union (OR) of two RoaringBitmaps."""
        res = self.clone()
        for key, c2 in other._chunks.items():
            if key not in res._chunks:
                res._chunks[key] = c2.clone()
            else:
                res._chunks[key] = _or_container(res._chunks[key], c2)
        return res

    def difference(self, other: RoaringBitmap) -> RoaringBitmap:
        """Returns the difference (ANDNOT) of two RoaringBitmaps."""
        res = RoaringBitmap()
        for key, c1 in self._chunks.items():
            if key not in other._chunks:
                res._chunks[key] = c1.clone()
            else:
                c = _sub_container(c1, other._chunks[key])
                if not c.is_empty():
                    res._chunks[key] = c
        return res

    def symmetric_difference(self, other: RoaringBitmap) -> RoaringBitmap:
        """Returns the symmetric difference (XOR) of two RoaringBitmaps."""
        u = self.union(other)
        i = self.intersection(other)
        return u.difference(i)

    def __and__(self, other: RoaringBitmap) -> RoaringBitmap:
        return self.intersection(other)

    def __or__(self, other: RoaringBitmap) -> RoaringBitmap:
        return self.union(other)

    def __sub__(self, other: RoaringBitmap) -> RoaringBitmap:
        return self.difference(other)

    def __xor__(self, other: RoaringBitmap) -> RoaringBitmap:
        return self.symmetric_difference(other)

    def __eq__(self, other: Any) -> bool:
        if isinstance(other, RoaringBitmap):
            if len(self) != len(other):
                return False
            return self.to_list() == other.to_list()
        if isinstance(other, (set, frozenset)):
            return self.to_set() == other
        if isinstance(other, (list, tuple)):
            return self.to_list() == list(other)
        return False

    def get_size_in_bytes(self) -> int:
        """Calculates total allocated container memory footprint."""
        return sum(c.get_size_in_bytes() for c in self._chunks.values()) + 64

    def to_bytes(self) -> bytes:
        """Serializes bitmap to a compact binary format."""
        chunks = sorted(self._chunks.items())
        header = struct.pack("<II", SERIAL_COOKIE, len(chunks))
        meta_blocks: List[bytes] = []
        payloads: List[bytes] = []
        for key, container in chunks:
            c_type = container.container_type()
            card = container.get_cardinality()
            data = container.to_bytes()
            meta_blocks.append(struct.pack("<HBH", key, c_type, card))
            payloads.append(struct.pack("<I", len(data)) + data)
        return header + b"".join(meta_blocks) + b"".join(payloads)

    @classmethod
    def from_bytes(cls, data: bytes) -> RoaringBitmap:
        """Deserializes a RoaringBitmap from binary format."""
        if len(data) < 8:
            raise ValueError("Corrupt byte stream: insufficient length")
        cookie, chunk_count = struct.unpack_from("<II", data, 0)
        if cookie != SERIAL_COOKIE:
            raise ValueError(f"Invalid magic cookie: {hex(cookie)}")

        res = cls()
        headers, offset = _parse_chunk_headers(data, chunk_count, 8)
        res._chunks = _parse_chunk_payloads(data, headers, offset)
        return res


def _parse_chunk_headers(
    data: bytes, chunk_count: int, offset: int
) -> Tuple[List[Tuple[int, int, int]], int]:
    headers: List[Tuple[int, int, int]] = []
    for _ in range(chunk_count):
        if offset + 5 > len(data):
            raise ValueError("Corrupt byte stream: truncated chunk metadata")
        key, c_type, card = struct.unpack_from("<HBH", data, offset)
        headers.append((key, c_type, card))
        offset += 5
    return headers, offset


def _parse_single_payload(
    data: bytes, offset: int, c_type: int, card: int
) -> Tuple[Container, int]:
    if offset + 4 > len(data):
        raise ValueError("Corrupt byte stream: truncated payload length")
    payload_len = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    if offset + payload_len > len(data):
        raise ValueError("Corrupt byte stream: truncated payload data")
    payload = data[offset : offset + payload_len]
    return _deserialize_container(c_type, card, payload), offset + payload_len


def _parse_chunk_payloads(
    data: bytes, headers: List[Tuple[int, int, int]], offset: int
) -> Dict[int, Container]:
    chunks: Dict[int, Container] = {}
    for key, c_type, card in headers:
        container, offset = _parse_single_payload(data, offset, c_type, card)
        chunks[key] = container
    return chunks


def _deserialize_container(c_type: int, card: int, payload: bytes) -> Container:
    if c_type == TYPE_ARRAY:
        arr = ArrayContainer()
        arr._data.frombytes(payload)
        return arr
    if c_type == TYPE_BITMAP:
        bmp = BitmapContainer()
        bmp._words = array.array("Q")
        bmp._words.frombytes(payload)
        bmp._cardinality = card
        return bmp
    if c_type == TYPE_RUN:
        run = RunContainer()
        run._runs.frombytes(payload)
        run._cardinality = card
        return run
    raise ValueError(f"Unknown container type {c_type}")
