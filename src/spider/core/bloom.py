"""Pure Python Scalable Bloom Filter implementation using standard library only."""

from __future__ import annotations

import hashlib
import math
from typing import List, Sequence


class BloomFilter:
    """Standard Bloom Filter with double hashing technique."""

    def __init__(self, capacity: int = 100000, error_rate: float = 0.0001) -> None:
        if capacity <= 0:
            raise ValueError("Capacity must be greater than 0")
        if not (0 < error_rate < 1):
            raise ValueError("Error rate must be between 0 and 1 exclusive")

        self.capacity: int = capacity
        self.error_rate: float = error_rate
        self.num_bits: int = int(
            -(capacity * math.log(error_rate)) / (math.log(2) ** 2)
        )
        self.num_hashes: int = max(1, int((self.num_bits / capacity) * math.log(2)))
        self.bit_array: bytearray = bytearray((self.num_bits + 7) // 8)
        self.count: int = 0

    def _hashes(self, key: str) -> List[int]:
        digest: bytes = hashlib.sha256(key.encode("utf-8")).digest()
        h1: int = int.from_bytes(digest[:8], "big")
        h2: int = int.from_bytes(digest[8:16], "big")
        return [(h1 + i * h2) % self.num_bits for i in range(self.num_hashes)]

    def add(self, key: str) -> bool:
        """Add a key to the filter. Returns True if key was not present, False if already present."""
        positions: Sequence[int] = self._hashes(key)
        already_present: bool = True
        for pos in positions:
            byte_idx: int = pos // 8
            bit_idx: int = pos % 8
            if not (self.bit_array[byte_idx] & (1 << bit_idx)):
                already_present = False
                self.bit_array[byte_idx] |= 1 << bit_idx

        if not already_present:
            self.count += 1
        return not already_present

    def __contains__(self, key: str) -> bool:
        positions: Sequence[int] = self._hashes(key)
        for pos in positions:
            byte_idx: int = pos // 8
            bit_idx: int = pos % 8
            if not (self.bit_array[byte_idx] & (1 << bit_idx)):
                return False
        return True

    def __len__(self) -> int:
        return self.count

    def to_bytes(self) -> bytes:
        """Serialize bloom filter to bytes."""
        return bytes(self.bit_array)

    @classmethod
    def from_bytes(
        cls, data: bytes, capacity: int, error_rate: float, count: int
    ) -> BloomFilter:
        """Deserialize bloom filter from bytes."""
        bf = cls(capacity=capacity, error_rate=error_rate)
        bf.bit_array = bytearray(data)
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
        self.initial_capacity: int = initial_capacity
        self.error_rate: float = error_rate
        self.scale_factor: int = scale_factor
        self.filters: List[BloomFilter] = [
            BloomFilter(capacity=initial_capacity, error_rate=error_rate * 0.5)
        ]

    def add(self, key: str) -> bool:
        """Add a key. Returns True if key is new, False if already exists."""
        if key in self:
            return False

        current: BloomFilter = self.filters[-1]
        if current.count >= current.capacity:
            next_cap: int = current.capacity * self.scale_factor
            next_error: float = current.error_rate * 0.8
            new_filter = BloomFilter(capacity=next_cap, error_rate=next_error)
            self.filters.append(new_filter)
            current = new_filter

        current.add(key)
        return True

    def __contains__(self, key: str) -> bool:
        for f in reversed(self.filters):
            if key in f:
                return True
        return False

    def __len__(self) -> int:
        return sum(len(f) for f in self.filters)
