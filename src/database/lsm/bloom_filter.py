#!/usr/bin/env python3
"""
Probabilistic Bloom Filter Subsystem for LSM-Tree Storage.
Provides zero-dependency, constant-time membership testing to skip unnecessary disk I/O.
Guarantees zero False Negatives and configurable False Positive probability (< 1%).
"""

import math
import struct
import zlib
from typing import List, Optional


class BloomFilter:
    """
    Bit-array based probabilistic data structure with multiple hash functions.
    """

    def __init__(
        self,
        expected_items: int = 1000,
        fp_rate: float = 0.01,
        raw_bits: Optional[bytearray] = None,
        num_bits: Optional[int] = None,
        num_hashes: Optional[int] = None,
    ) -> None:
        if raw_bits is not None and num_bits is not None and num_hashes is not None:
            self.num_bits = num_bits
            self.num_hashes = num_hashes
            self.bit_array = raw_bits
        else:
            if expected_items < 1:
                expected_items = 1
            if fp_rate <= 0 or fp_rate >= 1:
                fp_rate = 0.01

            # Optimal bit count m = - (n * ln(p)) / (ln(2)^2)
            m = int(-1 * (expected_items * math.log(fp_rate)) / (math.log(2) ** 2))
            self.num_bits = max(64, m)
            # Optimal hash count k = (m / n) * ln(2)
            k = int((self.num_bits / expected_items) * math.log(2))
            self.num_hashes = max(1, min(k, 16))

            byte_len = (self.num_bits + 7) // 8
            self.bit_array = bytearray(byte_len)

    def _get_hashes(self, key: str) -> List[int]:
        """
        Generates k independent hash values using double hashing (Kirsch-Mitzenmacher technique).
        hash_i = (h1 + i * h2) % num_bits
        """
        data = key.encode("utf-8")
        # Hash 1: FNV-1a 64-bit
        h1 = 0xCBF29CE484222325
        for b in data:
            h1 ^= b
            h1 = (h1 * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF

        # Hash 2: CRC32 + bit mixer
        crc = zlib.crc32(data)
        h2 = (crc * 0x5BD1E995) & 0xFFFFFFFFFFFFFFFF
        if h2 == 0:
            h2 = 0x9E3779B97F4A7C15

        hashes: List[int] = []
        for i in range(self.num_hashes):
            combined = (h1 + i * h2) & 0xFFFFFFFFFFFFFFFF
            hashes.append(combined % self.num_bits)
        return hashes

    def add(self, key: str) -> None:
        """Adds a key to the Bloom filter."""
        for bit_idx in self._get_hashes(key):
            byte_idx = bit_idx // 8
            bit_offset = bit_idx % 8
            self.bit_array[byte_idx] |= 1 << bit_offset

    def contains(self, key: str) -> bool:
        """
        Tests if key might be in the set.
        Returns False if key is definitely NOT in the set.
        Returns True if key is PROBABLY in the set.
        """
        for bit_idx in self._get_hashes(key):
            byte_idx = bit_idx // 8
            bit_offset = bit_idx % 8
            if not (self.bit_array[byte_idx] & (1 << bit_offset)):
                return False
        return True

    def to_bytes(self) -> bytes:
        """Serializes Bloom filter into binary payload: [num_bits (4B), num_hashes (2B), bit_array]."""
        header = struct.pack("<IH", self.num_bits, self.num_hashes)
        return header + bytes(self.bit_array)

    @classmethod
    def from_bytes(cls, data: bytes) -> "BloomFilter":
        """Deserializes Bloom filter from binary payload."""
        if len(data) < 6:
            raise ValueError("Invalid Bloom filter binary payload: too short")
        num_bits, num_hashes = struct.unpack_from("<IH", data, 0)
        bit_array = bytearray(data[6:])
        return cls(
            raw_bits=bit_array,
            num_bits=num_bits,
            num_hashes=num_hashes,
        )
