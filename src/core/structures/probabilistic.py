#!/usr/bin/env python3
"""
Zero-dependency probabilistic data structures for streaming observability and analytics.
Provides Count-Min Sketch for frequency estimation and t-digest for quantile estimation.
"""

from __future__ import annotations

import hashlib
import math
from dataclasses import dataclass
from typing import List, Sequence, Tuple


def _fnv1a_hash(data: bytes, seed: int = 0) -> int:
    """Computes 64-bit FNV-1a hash with seed."""
    h = 0xCBF29CE484222325 ^ seed
    for b in data:
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def _generate_indices(item_bytes: bytes, depth: int, width: int) -> List[int]:
    """Generates depth hash indices using double hashing."""
    h1 = _fnv1a_hash(item_bytes, 0)
    digest = hashlib.sha256(item_bytes).digest()
    h2 = int.from_bytes(digest[:8], "big") | 1

    indices: List[int] = []
    for i in range(depth):
        idx = (h1 + i * h2) % width
        indices.append(idx)
    return indices


class CountMinSketch:
    """
    Count-Min Sketch for frequency estimation over large data streams.
    Guarantees that estimated frequency is never an underestimate.
    """

    def __init__(
        self,
        width: int = 2048,
        depth: int = 5,
    ) -> None:
        self.width = max(16, width)
        self.depth = max(1, min(depth, 32))
        self.table: List[List[int]] = [[0] * self.width for _ in range(self.depth)]
        self._total: int = 0

    @property
    def total_count(self) -> int:
        return self._total

    def add(self, item: str, count: int = 1) -> None:
        """Increments frequency count for item."""
        if count <= 0:
            return
        item_bytes = item.encode("utf-8")
        indices = _generate_indices(item_bytes, self.depth, self.width)
        for row, col in enumerate(indices):
            self.table[row][col] += count
        self._total += count

    def estimate(self, item: str) -> int:
        """Estimates frequency of item (never underestimates)."""
        item_bytes = item.encode("utf-8")
        indices = _generate_indices(item_bytes, self.depth, self.width)
        min_val = self.table[0][indices[0]]
        for row in range(1, self.depth):
            val = self.table[row][indices[row]]
            if val < min_val:
                min_val = val
        return min_val

    def merge(self, other: CountMinSketch) -> None:
        """Merges another sketch with identical width and depth."""
        if self.width != other.width or self.depth != other.depth:
            raise ValueError("Cannot merge sketches with different dimensions")
        for r in range(self.depth):
            for c in range(self.width):
                self.table[r][c] += other.table[r][c]
        self._total += other._total

    def clear(self) -> None:
        """Resets all frequency counters."""
        for row in self.table:
            for c in range(self.width):
                row[c] = 0
        self._total = 0


@dataclass
class Centroid:
    """Centroid of clustered points in a t-digest."""

    mean: float
    weight: float


def _validate_sample(value: float, weight: float) -> bool:
    """Validates sample value and weight."""
    if math.isnan(value) or math.isinf(value):
        return False
    return not (weight <= 0.0 or math.isnan(weight) or math.isinf(weight))


def _max_cluster_weight(q: float, total_weight: float, delta: float) -> float:
    """Calculates max allowed cluster weight at quantile q."""
    return 4.0 * total_weight * delta * q * (1.0 - q)


def _step_merge_centroid(
    curr_mean: float,
    curr_weight: float,
    cand: Centroid,
) -> Tuple[float, float]:
    """Combines a candidate centroid into current centroid."""
    new_weight = curr_weight + cand.weight
    new_mean = (curr_mean * curr_weight + cand.mean * cand.weight) / new_weight
    return new_mean, new_weight


def _interpolate_quantile(
    c1: Centroid,
    c2: Centroid,
    q1: float,
    q2: float,
    target_q: float,
) -> float:
    """Linearly interpolates quantile between two centroids."""
    if q2 <= q1:
        return c1.mean
    ratio = (target_q - q1) / (q2 - q1)
    return c1.mean + ratio * (c2.mean - c1.mean)


def _interpolate_at_index(
    centroids: Sequence[Centroid],
    idx: int,
    cum_weight: float,
    total_weight: float,
    q: float,
) -> float:
    """Calculates interpolated quantile for centroid at idx."""
    c = centroids[idx]
    if idx == 0:
        return c.mean
    prev_c = centroids[idx - 1]
    q_prev = (cum_weight - prev_c.weight / 2.0) / total_weight
    q_curr = (cum_weight + c.weight / 2.0) / total_weight
    return _interpolate_quantile(prev_c, c, q_prev, q_curr, q)


def _scan_quantile_centroids(
    centroids: Sequence[Centroid],
    target_weight: float,
    total_weight: float,
    q: float,
) -> float:
    """Scans centroids to locate target quantile weight."""
    cum_weight = 0.0
    for i, c in enumerate(centroids):
        if cum_weight + c.weight >= target_weight:
            return _interpolate_at_index(centroids, i, cum_weight, total_weight, q)
        cum_weight += c.weight
    return centroids[-1].mean


def _validate_quantile_arg(q: float) -> None:
    """Validates that quantile target is in [0.0, 1.0]."""
    if q < 0.0 or q > 1.0:
        raise ValueError("Quantile must be in [0.0, 1.0]")


class TDigest:
    """
    t-digest data structure for accurate streaming quantile estimation (p50, p90, p99).
    Maintains bounded memory by clustering centroids.
    """

    def __init__(self, delta: float = 0.01, buffer_ratio: int = 5) -> None:
        self.delta = max(0.001, min(0.5, delta))
        self.max_centroids = max(10, int(1.0 / self.delta))
        self.buffer_limit = self.max_centroids * buffer_ratio
        self.centroids: List[Centroid] = []
        self._buffer: List[Centroid] = []
        self._total_weight: float = 0.0

    @property
    def total_weight(self) -> float:
        return self._total_weight

    def __len__(self) -> int:
        return len(self.centroids) + len(self._buffer)

    def add(self, value: float, weight: float = 1.0) -> None:
        """Adds a sample value with given weight."""
        if not _validate_sample(value, weight):
            return
        self._buffer.append(Centroid(mean=float(value), weight=float(weight)))
        self._total_weight += weight
        if len(self._buffer) >= self.buffer_limit:
            self.compress()

    def _flush_buffer(self) -> List[Centroid]:
        """Combines and sorts existing centroids with buffered centroids."""
        all_centroids = self.centroids + self._buffer
        self._buffer = []
        all_centroids.sort(key=lambda c: c.mean)
        return all_centroids

    def compress(self) -> None:
        """Merges centroids to maintain size bound while preserving tail accuracy."""
        all_c = self._flush_buffer()
        if not all_c:
            return

        merged: List[Centroid] = []
        curr_mean = all_c[0].mean
        curr_weight = all_c[0].weight
        cum_weight = 0.0

        for cand in all_c[1:]:
            q = (cum_weight + curr_weight / 2.0) / max(1.0, self._total_weight)
            max_w = max(1.0, _max_cluster_weight(q, self._total_weight, self.delta))
            if curr_weight + cand.weight <= max_w:
                curr_mean, curr_weight = _step_merge_centroid(
                    curr_mean, curr_weight, cand
                )
            else:
                merged.append(Centroid(curr_mean, curr_weight))
                cum_weight += curr_weight
                curr_mean = cand.mean
                curr_weight = cand.weight

        merged.append(Centroid(curr_mean, curr_weight))
        self.centroids = merged

    def _prepare_query(self) -> None:
        """Flushes buffer if needed before answering quantile query."""
        if self._buffer:
            self.compress()

    def quantile(self, q: float) -> float:
        """
        Estimates the q-th quantile (0.0 <= q <= 1.0).
        For example: q=0.5 for median, q=0.99 for 99th percentile.
        """
        _validate_quantile_arg(q)
        self._prepare_query()
        if not self.centroids:
            return 0.0
        if len(self.centroids) == 1:
            return self.centroids[0].mean

        target_weight = q * self._total_weight
        return _scan_quantile_centroids(
            self.centroids, target_weight, self._total_weight, q
        )

    def clear(self) -> None:
        """Clears all centroids and samples."""
        self.centroids.clear()
        self._buffer.clear()
        self._total_weight = 0.0
