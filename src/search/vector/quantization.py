#!/usr/bin/env python3
"""
Pure Python Product Quantization (PQ) and Asymmetric Distance Computation (ADC).
Zero external dependencies (Standard Library Only: math, random, struct).
"""

import os
import random
import struct
from typing import List, Sequence, Tuple


class ProductQuantizer:
    """
    Pure Python Product Quantizer.
    Splits a high-dimensional vector of dimension `dim` into `M` subvectors,
    each quantized into one of `num_centroids` (default 256 = 1 byte) centroids.
    """

    MAGIC = b"OKFPQ001"
    HEADER_FORMAT = "<8sHHHI"  # magic(8B), version(2B), dim(2B), M(2B), K(4B)
    HEADER_SIZE = struct.calcsize(HEADER_FORMAT)

    def __init__(
        self,
        dim: int = 128,
        M: int = 8,
        num_centroids: int = 256,
        seed: int = 42,
    ) -> None:
        if dim % M != 0:
            raise ValueError(f"Dimension {dim} must be divisible by M {M}")
        if num_centroids <= 0 or num_centroids > 256:
            raise ValueError("num_centroids must be between 1 and 256")

        self.dim = int(dim)
        self.M = int(M)
        self.d_sub = self.dim // self.M
        self.num_centroids = int(num_centroids)
        self.rng = random.Random(seed)
        # centroids: List of M lists, each containing num_centroids subvectors of length d_sub
        self.centroids: List[List[Tuple[float, ...]]] = [[] for _ in range(self.M)]
        self.is_trained = False

    def _euclidean_sq(self, v1: Sequence[float], v2: Sequence[float]) -> float:
        return sum((a - b) ** 2 for a, b in zip(v1, v2))

    def _extract_subvectors(
        self, vectors: Sequence[Sequence[float]], m: int
    ) -> List[Tuple[float, ...]]:
        start = m * self.d_sub
        end = start + self.d_sub
        return [tuple(v[start:end]) for v in vectors]

    def _init_kmeans_centroids(
        self, subvectors: List[Tuple[float, ...]]
    ) -> List[Tuple[float, ...]]:
        k = min(self.num_centroids, len(subvectors))
        if k == 0:
            return [(0.0,) * self.d_sub for _ in range(self.num_centroids)]

        # Sample initial centroids deterministically
        step = max(1, len(subvectors) // k)
        initial: List[Tuple[float, ...]] = [
            subvectors[min(i * step, len(subvectors) - 1)] for i in range(k)
        ]
        while len(initial) < self.num_centroids:
            initial.append(initial[-1])
        return initial

    def _assign_subvectors(
        self,
        subvectors: List[Tuple[float, ...]],
        centroids: List[Tuple[float, ...]],
    ) -> List[int]:
        assignments: List[int] = []
        for svec in subvectors:
            best_idx = 0
            best_dist = float("inf")
            for c_idx, c_vec in enumerate(centroids):
                dist = self._euclidean_sq(svec, c_vec)
                if dist < best_dist:
                    best_dist = dist
                    best_idx = c_idx
            assignments.append(best_idx)
        return assignments

    def _accumulate_sums(
        self, subvectors: List[Tuple[float, ...]], assignments: List[int]
    ) -> Tuple[List[List[float]], List[int]]:
        sums = [[0.0] * self.d_sub for _ in range(self.num_centroids)]
        counts = [0] * self.num_centroids
        for svec, cluster in zip(subvectors, assignments):
            counts[cluster] += 1
            for d in range(self.d_sub):
                sums[cluster][d] += svec[d]
        return sums, counts

    def _update_centroids(
        self,
        subvectors: List[Tuple[float, ...]],
        assignments: List[int],
        old_centroids: List[Tuple[float, ...]],
    ) -> List[Tuple[float, ...]]:
        sums, counts = self._accumulate_sums(subvectors, assignments)
        new_centroids: List[Tuple[float, ...]] = []
        for c_idx in range(self.num_centroids):
            cnt = counts[c_idx]
            if cnt > 0:
                new_centroids.append(
                    tuple(sums[c_idx][d] / cnt for d in range(self.d_sub))
                )
            else:
                new_centroids.append(old_centroids[c_idx])
        return new_centroids

    def _train_single_subspace(
        self,
        subvectors: List[Tuple[float, ...]],
        iterations: int = 5,
    ) -> List[Tuple[float, ...]]:
        centroids = self._init_kmeans_centroids(subvectors)
        if len(subvectors) <= 1:
            return centroids

        for _ in range(iterations):
            assignments = self._assign_subvectors(subvectors, centroids)
            centroids = self._update_centroids(subvectors, assignments, centroids)
        return centroids

    def train(self, vectors: Sequence[Sequence[float]], iterations: int = 5) -> None:
        """Trains PQ codebooks across all M subspaces."""
        if not vectors:
            return

        for m in range(self.M):
            subvectors = self._extract_subvectors(vectors, m)
            self.centroids[m] = self._train_single_subspace(
                subvectors, iterations=iterations
            )
        self.is_trained = True

    def _encode_subspace(
        self, svec: Sequence[float], centroids: List[Tuple[float, ...]]
    ) -> int:
        best_idx = 0
        best_dist = float("inf")
        for idx, cvec in enumerate(centroids):
            dist = self._euclidean_sq(svec, cvec)
            if dist < best_dist:
                best_dist = dist
                best_idx = idx
        return best_idx

    def encode(self, vector: Sequence[float]) -> bytes:
        """Encodes a D-dimensional vector into M bytes."""
        if not self.is_trained:
            raise RuntimeError("ProductQuantizer must be trained before encoding")
        if len(vector) != self.dim:
            raise ValueError(f"Vector dimension {len(vector)} != {self.dim}")

        codes = bytearray(self.M)
        for m in range(self.M):
            start = m * self.d_sub
            svec = vector[start : start + self.d_sub]
            codes[m] = self._encode_subspace(svec, self.centroids[m])
        return bytes(codes)

    def decode(self, codes: bytes) -> List[float]:
        """Reconstructs approximate vector from M bytes."""
        if len(codes) != self.M:
            raise ValueError(f"Codes length {len(codes)} != {self.M}")

        res: List[float] = []
        for m, code_byte in enumerate(codes):
            c_idx = code_byte
            if c_idx < len(self.centroids[m]):
                res.extend(self.centroids[m][c_idx])
            else:
                res.extend([0.0] * self.d_sub)
        return res

    def compute_lut(self, query: Sequence[float]) -> List[List[float]]:
        """
        Computes Asymmetric Distance Computation (ADC) Look-Up Table (LUT).
        LUT shape: [M][num_centroids], where LUT[m][k] = ||q_m - C_{m, k}||^2.
        """
        if not self.is_trained:
            raise RuntimeError("ProductQuantizer must be trained before computing LUT")
        if len(query) != self.dim:
            raise ValueError(f"Query dimension {len(query)} != {self.dim}")

        lut: List[List[float]] = []
        for m in range(self.M):
            start = m * self.d_sub
            q_sub = query[start : start + self.d_sub]
            lut_m: List[float] = []
            for cvec in self.centroids[m]:
                lut_m.append(self._euclidean_sq(q_sub, cvec))
            lut.append(lut_m)
        return lut

    def compute_adc(self, lut: List[List[float]], codes: bytes) -> float:
        """
        Asymmetric Distance Computation (ADC) using precomputed LUT.
        Runtime: O(M) array index lookups and additions.
        """
        dist = 0.0
        for m in range(self.M):
            dist += lut[m][codes[m]]
        return dist

    def save(self, file_path: str) -> None:
        """Saves codebook to a binary file."""
        os.makedirs(os.path.dirname(os.path.abspath(file_path)), exist_ok=True)
        header = struct.pack(
            self.HEADER_FORMAT,
            self.MAGIC,
            1,  # version
            self.dim,
            self.M,
            self.num_centroids,
        )
        flat_centroids: List[float] = []
        for m in range(self.M):
            for cvec in self.centroids[m]:
                flat_centroids.extend(cvec)

        centroids_bytes = struct.pack(f"<{len(flat_centroids)}f", *flat_centroids)
        with open(file_path, "wb") as f:
            f.write(header)
            f.write(centroids_bytes)

    @classmethod
    def load(cls, file_path: str) -> "ProductQuantizer":
        """Loads codebook from a binary file."""
        with open(file_path, "rb") as f:
            header_bytes = f.read(cls.HEADER_SIZE)
            if len(header_bytes) < cls.HEADER_SIZE:
                raise ValueError("Invalid PQ file: header truncated")
            magic, version, dim, M, num_centroids = struct.unpack(
                cls.HEADER_FORMAT, header_bytes
            )
            if magic != cls.MAGIC:
                raise ValueError(f"Invalid magic bytes: {magic}")

            pq = cls(dim=dim, M=M, num_centroids=num_centroids)
            total_floats = M * num_centroids * pq.d_sub
            payload_bytes = f.read(total_floats * 4)
            flat = struct.unpack(f"<{total_floats}f", payload_bytes)

            idx = 0
            for m in range(M):
                pq.centroids[m] = []
                for _ in range(num_centroids):
                    svec = flat[idx : idx + pq.d_sub]
                    pq.centroids[m].append(tuple(svec))
                    idx += pq.d_sub
            pq.is_trained = True
            return pq
