#!/usr/bin/env python3
"""
HyperLogLog (HLL) Probabilistic Cardinality Estimation.
Estimates the Number of Distinct Values (NDV) with O(1) memory and bounded error.
"""

import hashlib
import math
from typing import Any, List


class HyperLogLog:
    """
    HyperLogLog probabilistic distinct value counter.
    Default precision p = 6 (m = 64 registers, ~13% standard error).
    p = 8 gives m = 256 registers (~6.5% error).
    """

    def __init__(self, p: int = 6) -> None:
        if not (4 <= p <= 16):
            raise ValueError("Precision p must be between 4 and 16")
        self.p = p
        self.m = 1 << p
        self.registers: List[int] = [0] * self.m

        # Compute alpha_m constant
        if self.m == 16:
            self.alpha_m = 0.673
        elif self.m == 32:
            self.alpha_m = 0.697
        elif self.m == 64:
            self.alpha_m = 0.709
        else:
            self.alpha_m = 0.7213 / (1.0 + 1.079 / self.m)

    def _hash(self, val: Any) -> int:
        """Computes 64-bit integer hash from string/number representation."""
        s = str(val).encode("utf-8")
        digest = hashlib.sha256(s).digest()
        # Extract 64-bit integer from leading 8 bytes
        return int.from_bytes(digest[:8], byteorder="little")

    def _rho(self, w: int, max_bits: int = 64) -> int:
        """Counts leading zeros plus 1."""
        if w == 0:
            return max_bits
        lz = 0
        while (w & (1 << (max_bits - 1 - lz))) == 0 and lz < max_bits:
            lz += 1
        return lz + 1

    def add(self, val: Any) -> None:
        """Adds an element to the HLL sketch."""
        if val is None:
            return
        x = self._hash(val)
        idx = x & (self.m - 1)
        w = x >> self.p
        r = self._rho(w, 64 - self.p)
        if r > self.registers[idx]:
            self.registers[idx] = r

    def estimate_cardinality(self) -> int:
        """Computes estimated distinct count (NDV)."""
        # Harmonic mean of 2^(-M[j])
        z = sum(2.0 ** (-r) for r in self.registers)
        raw_estimate = (self.alpha_m * (self.m**2)) / z

        # Small range correction (Linear Counting)
        if raw_estimate <= 2.5 * self.m:
            zeros = self.registers.count(0)
            if zeros > 0:
                return int(round(self.m * math.log(self.m / zeros)))

        return int(round(raw_estimate))

    def merge(self, other: "HyperLogLog") -> "HyperLogLog":
        """Merges two HLL sketches with identical precision."""
        if self.p != other.p:
            raise ValueError("Cannot merge HLL sketches with different precision")
        merged = HyperLogLog(p=self.p)
        merged.registers = [
            max(r1, r2) for r1, r2 in zip(self.registers, other.registers)
        ]
        return merged
