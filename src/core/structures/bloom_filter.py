"""High-performance probabilistic Bloom Filter and Scalable Bloom Filter implementations.

Provides zero-dependency, constant-time set membership testing with zero false negatives.
Unified across database LSM-Tree engine, web crawler/spider deduplication, and caching.
"""

from __future__ import annotations

import hashlib
import math
import struct
from typing import List, Optional, Sequence

_MASK64 = 0xFFFFFFFFFFFFFFFF


def _calculate_optimal_bits(capacity: int, error_rate: float) -> int:
    """Calculate optimal number of bits for given capacity and false positive rate."""
    m = int(-(capacity * math.log(error_rate)) / (math.log(2) ** 2))
    return max(64, m)


def _calculate_optimal_hashes(num_bits: int, capacity: int) -> int:
    """Calculate optimal number of hash functions capped for performance."""
    k = int((num_bits / capacity) * math.log(2))
    return max(1, min(k, 32))


def _extract_double_hash_pair(data: bytes) -> tuple[int, int]:
    """Extract two independent 64-bit seed hashes from SHA-256 digest."""
    digest = hashlib.sha256(data).digest()
    h1 = int.from_bytes(digest[:8], "big")
    h2 = int.from_bytes(digest[8:16], "big") | 1
    return h1, h2


def _resolve_effective_specs(
    capacity: int,
    error_rate: float,
    expected_items: Optional[int],
    fp_rate: Optional[float],
) -> tuple[int, float]:
    """Resolve backwards-compatible parameters for BloomFilter construction."""
    cap = capacity if expected_items is None else expected_items
    err = error_rate if fp_rate is None else fp_rate
    return cap, err


def _has_all_raw_components(
    raw_bits: Optional[bytearray],
    num_bits: Optional[int],
    num_hashes: Optional[int],
) -> bool:
    """Check if all raw binary components are provided."""
    return raw_bits is not None and num_bits is not None and num_hashes is not None


def _unpack_bloom_payload(data: bytes) -> tuple[int, int, bytearray]:
    """Unpack header and bit array from binary payload with validation."""
    if len(data) < 6:
        raise ValueError("Invalid Bloom filter binary payload: too short")

    num_bits, num_hashes = struct.unpack_from("<IH", data, 0)
    bit_array = bytearray(data[6:])
    expected_len = (num_bits + 7) // 8
    if len(bit_array) != expected_len:
        raise ValueError(
            f"Payload size mismatch: expected {expected_len} bytes, got {len(bit_array)}"
        )
    return num_bits, num_hashes, bit_array


class BloomFilter:
    """Standard probabilistic Bloom Filter using Kirsch-Mitzenmacher double hashing."""

    def __init__(
        self,
        capacity: int = 1000,
        error_rate: float = 0.01,
        *,
        expected_items: Optional[int] = None,
        fp_rate: Optional[float] = None,
        raw_bits: Optional[bytearray] = None,
        num_bits: Optional[int] = None,
        num_hashes: Optional[int] = None,
    ) -> None:
        if _has_all_raw_components(raw_bits, num_bits, num_hashes):
            assert (
                raw_bits is not None and num_bits is not None and num_hashes is not None
            )
            self._init_from_raw(raw_bits, num_bits, num_hashes, capacity, error_rate)
            return

        eff_cap, eff_err = _resolve_effective_specs(
            capacity, error_rate, expected_items, fp_rate
        )
        self._init_from_specs(eff_cap, eff_err)

    def _init_from_raw(
        self,
        raw_bits: bytearray,
        num_bits: int,
        num_hashes: int,
        capacity: int,
        error_rate: float,
    ) -> None:
        self.num_bits: int = num_bits
        self.num_hashes: int = num_hashes
        self.bit_array: bytearray = raw_bits
        self.capacity: int = max(1, capacity)
        self.error_rate: float = error_rate
        self.count: int = 0

    def _init_from_specs(self, capacity: int, error_rate: float) -> None:
        if capacity <= 0:
            raise ValueError("Capacity must be greater than 0")
        if not (0 < error_rate < 1):
            raise ValueError("Error rate must be between 0 and 1 exclusive")

        self.capacity = capacity
        self.error_rate = error_rate
        self.num_bits = _calculate_optimal_bits(capacity, error_rate)
        self.num_hashes = _calculate_optimal_hashes(self.num_bits, capacity)
        byte_len = (self.num_bits + 7) // 8
        self.bit_array = bytearray(byte_len)
        self.count = 0

    def _get_hashes(self, key: str) -> List[int]:
        """Generate k bit positions using Kirsch-Mitzenmacher double hashing."""
        h1, h2 = _extract_double_hash_pair(key.encode("utf-8"))
        hashes: List[int] = []
        for i in range(self.num_hashes):
            pos = (h1 + i * h2) & _MASK64
            hashes.append(pos % self.num_bits)
        return hashes

    # Spider alias
    _hashes = _get_hashes

    def add(self, key: str) -> bool:
        """Add a key to the filter.

        Returns:
            True if the key was not previously present, False if already present.
        """
        positions: Sequence[int] = self._get_hashes(key)
        already_present = True
        for pos in positions:
            byte_idx = pos // 8
            bit_idx = pos % 8
            if not (self.bit_array[byte_idx] & (1 << bit_idx)):
                already_present = False
                self.bit_array[byte_idx] |= 1 << bit_idx

        if not already_present:
            self.count += 1
        return not already_present

    def contains(self, key: str) -> bool:
        """Check if a key is probably in the set (guarantees 0 false negatives)."""
        positions: Sequence[int] = self._get_hashes(key)
        for pos in positions:
            byte_idx = pos // 8
            bit_idx = pos % 8
            if not (self.bit_array[byte_idx] & (1 << bit_idx)):
                return False
        return True

    def __contains__(self, key: str) -> bool:
        return self.contains(key)

    def __len__(self) -> int:
        return self.count

    def clear(self) -> None:
        """Reset all bits in the Bloom filter to 0."""
        self.bit_array = bytearray(len(self.bit_array))
        self.count = 0

    def to_bytes(self) -> bytes:
        """Serialize filter into binary payload: [num_bits (4B), num_hashes (2B), bit_array]."""
        header = struct.pack("<IH", self.num_bits, self.num_hashes)
        return header + bytes(self.bit_array)

    @classmethod
    def from_bytes(
        cls,
        data: bytes,
        capacity: Optional[int] = None,
        error_rate: Optional[float] = None,
        count: Optional[int] = None,
    ) -> BloomFilter:
        """Deserialize Bloom filter from binary payload."""
        num_bits, num_hashes, bit_array = _unpack_bloom_payload(data)
        effective_cap = 1000 if capacity is None else capacity
        effective_err = 0.01 if error_rate is None else error_rate

        bf = cls(
            capacity=effective_cap,
            error_rate=effective_err,
            raw_bits=bit_array,
            num_bits=num_bits,
            num_hashes=num_hashes,
        )
        if count is not None:
            bf.count = count
        return bf


class ScalableBloomFilter:
    """Scalable Bloom Filter that dynamically adds sub-filters as capacity fills."""

    def __init__(
        self,
        initial_capacity: int = 10000,
        error_rate: float = 0.0001,
        scale_factor: int = 2,
    ) -> None:
        if initial_capacity <= 0:
            raise ValueError("Initial capacity must be greater than 0")
        if not (0 < error_rate < 1):
            raise ValueError("Error rate must be between 0 and 1 exclusive")
        if scale_factor <= 1:
            raise ValueError("Scale factor must be greater than 1")

        self.initial_capacity: int = initial_capacity
        self.error_rate: float = error_rate
        self.scale_factor: int = scale_factor
        self.filters: List[BloomFilter] = [
            BloomFilter(capacity=initial_capacity, error_rate=error_rate * 0.5)
        ]

    def _grow(self) -> BloomFilter:
        """Add a new sub-filter with scaled capacity and tightened error rate."""
        current = self.filters[-1]
        next_cap = current.capacity * self.scale_factor
        next_error = current.error_rate * 0.8
        new_filter = BloomFilter(capacity=next_cap, error_rate=next_error)
        self.filters.append(new_filter)
        return new_filter

    def add(self, key: str) -> bool:
        """Add a key. Returns True if key is new, False if already exists."""
        if key in self:
            return False

        current = self.filters[-1]
        if current.count >= current.capacity:
            current = self._grow()

        current.add(key)
        return True

    def contains(self, key: str) -> bool:
        """Check if a key is probably in any sub-filter."""
        for f in reversed(self.filters):
            if key in f:
                return True
        return False

    def __contains__(self, key: str) -> bool:
        return self.contains(key)

    def __len__(self) -> int:
        return sum(len(f) for f in self.filters)
