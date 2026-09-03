#!/usr/bin/env python3
"""
Pure Python Inverted File with Product Quantization (IVF-PQ) ANN Index.
Combines coarse Voronoi cell partitioning with Asymmetric Distance Computation.
Zero external dependencies (Standard Library Only: math, heapq, struct, os).
"""

import heapq
import math
import os
import random
import struct
from typing import Any, Dict, List, Sequence, Tuple

from .quantization import ProductQuantizer


class IVFPQIndex:
    """
    Pure Python IVF-PQ Approximate Nearest Neighbor (ANN) Index.
    Partitions the vector space into `nlist` coarse Voronoi clusters,
    quantizing vectors into `M` byte codes for sub-millisecond ADC search.
    """

    MAGIC = b"OKFIVFPQ"
    HEADER_FORMAT = "<8sHHHHIQ"  # magic(8B), version(2B), dim(2B), M(2B), nlist(2B), K(4B), count(8B)
    HEADER_SIZE = struct.calcsize(HEADER_FORMAT)

    def __init__(
        self,
        dim: int = 128,
        M: int = 8,
        nlist: int = 16,
        num_centroids: int = 256,
        seed: int = 42,
    ) -> None:
        self.dim = int(dim)
        self.M = int(M)
        self.nlist = int(nlist)
        self.num_centroids = int(num_centroids)
        self.rng = random.Random(seed)

        self.pq = ProductQuantizer(
            dim=self.dim, M=self.M, num_centroids=self.num_centroids, seed=seed
        )
        self.coarse_centroids: List[Tuple[float, ...]] = []
        self.inverted_lists: Dict[int, List[Tuple[int, bytes]]] = {
            i: [] for i in range(self.nlist)
        }
        self.count: int = 0
        self.is_trained: bool = False

    def _euclidean_sq(self, v1: Sequence[float], v2: Sequence[float]) -> float:
        return sum((a - b) ** 2 for a, b in zip(v1, v2))

    def _find_closest_centroid(
        self, vec: Sequence[float], centroids: List[Tuple[float, ...]]
    ) -> int:
        best_idx = 0
        best_dist = float("inf")
        for idx, cvec in enumerate(centroids):
            dist = self._euclidean_sq(vec, cvec)
            if dist < best_dist:
                best_dist = dist
                best_idx = idx
        return best_idx

    def _init_coarse_centroids(
        self, vectors: Sequence[Sequence[float]]
    ) -> List[Tuple[float, ...]]:
        k = min(self.nlist, len(vectors))
        if k == 0:
            return [(0.0,) * self.dim for _ in range(self.nlist)]
        step = max(1, len(vectors) // k)
        initial: List[Tuple[float, ...]] = [
            tuple(vectors[min(i * step, len(vectors) - 1)]) for i in range(k)
        ]
        while len(initial) < self.nlist:
            initial.append(initial[-1])
        return initial

    def _accumulate_coarse_sums(
        self,
        vectors: Sequence[Sequence[float]],
        assignments: List[int],
    ) -> Tuple[List[List[float]], List[int]]:
        sums = [[0.0] * self.dim for _ in range(self.nlist)]
        counts = [0] * self.nlist
        for vec, c_idx in zip(vectors, assignments):
            counts[c_idx] += 1
            for d in range(self.dim):
                sums[c_idx][d] += vec[d]
        return sums, counts

    def _update_coarse_centroids(
        self,
        vectors: Sequence[Sequence[float]],
        assignments: List[int],
        old_centroids: List[Tuple[float, ...]],
    ) -> List[Tuple[float, ...]]:
        sums, counts = self._accumulate_coarse_sums(vectors, assignments)
        new_centroids: List[Tuple[float, ...]] = []
        for c_idx in range(self.nlist):
            cnt = counts[c_idx]
            if cnt > 0:
                new_centroids.append(
                    tuple(sums[c_idx][d] / cnt for d in range(self.dim))
                )
            else:
                new_centroids.append(old_centroids[c_idx])
        return new_centroids

    def _train_coarse_kmeans(
        self, vectors: Sequence[Sequence[float]], iterations: int = 5
    ) -> List[Tuple[float, ...]]:
        centroids = self._init_coarse_centroids(vectors)
        if len(vectors) <= 1:
            return centroids

        for _ in range(iterations):
            assignments = [self._find_closest_centroid(v, centroids) for v in vectors]
            centroids = self._update_coarse_centroids(vectors, assignments, centroids)
        return centroids

    def train(self, vectors: Sequence[Sequence[float]], iterations: int = 5) -> None:
        """Trains coarse Voronoi clusters and Product Quantizer codebooks."""
        if not vectors:
            return
        self.coarse_centroids = self._train_coarse_kmeans(
            vectors, iterations=iterations
        )
        self.pq.train(vectors, iterations=iterations)
        self.is_trained = True

    def add(self, doc_id: int, vector: Sequence[float]) -> None:
        """Quantizes and assigns a document vector to its coarse inverted list."""
        if not self.is_trained:
            raise RuntimeError("IVFPQIndex must be trained before adding vectors")
        if len(vector) != self.dim:
            raise ValueError(f"Vector dimension {len(vector)} != {self.dim}")

        coarse_id = self._find_closest_centroid(vector, self.coarse_centroids)
        codes = self.pq.encode(vector)
        self.inverted_lists[coarse_id].append((int(doc_id), codes))
        self.count += 1

    def add_batch(
        self, doc_ids: Sequence[int], vectors: Sequence[Sequence[float]]
    ) -> None:
        """Batch insertion of vectors."""
        if len(doc_ids) != len(vectors):
            raise ValueError("doc_ids length != vectors length")
        for did, vec in zip(doc_ids, vectors):
            self.add(did, vec)

    def _select_coarse_probes(self, query: Sequence[float], nprobe: int) -> List[int]:
        dists: List[Tuple[float, int]] = []
        for c_idx, cvec in enumerate(self.coarse_centroids):
            dist = self._euclidean_sq(query, cvec)
            dists.append((dist, c_idx))
        dists.sort(key=lambda x: x[0])
        return [c_idx for _, c_idx in dists[: max(1, nprobe)]]

    def _scan_inverted_list(
        self,
        c_idx: int,
        lut: List[List[float]],
        candidates: List[Tuple[float, int]],
    ) -> None:
        for doc_id, codes in self.inverted_lists.get(c_idx, []):
            dist = self.pq.compute_adc(lut, codes)
            candidates.append((dist, doc_id))

    def _validate_search_params(self, query: Sequence[float]) -> bool:
        if not self.is_trained or self.count == 0:
            return False
        if len(query) != self.dim:
            raise ValueError(f"Query dimension {len(query)} != {self.dim}")
        return True

    def search(
        self,
        query: Sequence[float],
        top_k: int = 10,
        nprobe: int = 4,
    ) -> List[Tuple[int, float]]:
        """
        Searches Top-K nearest neighbors using Asymmetric Distance Computation.
        Returns list of (doc_id, similarity_score).
        """
        if not self._validate_search_params(query):
            return []

        probe_centroids = self._select_coarse_probes(query, nprobe)
        lut = self.pq.compute_lut(query)
        candidates: List[Tuple[float, int]] = []

        for c_idx in probe_centroids:
            self._scan_inverted_list(c_idx, lut, candidates)

        top_matches = heapq.nsmallest(top_k, candidates, key=lambda x: x[0])
        return [
            (did, 1.0 / (1.0 + math.sqrt(max(0.0, dist)))) for dist, did in top_matches
        ]

    def save(self, file_path: str) -> None:
        """Saves IVF-PQ index to a binary file."""
        os.makedirs(os.path.dirname(os.path.abspath(file_path)), exist_ok=True)
        header = struct.pack(
            self.HEADER_FORMAT,
            self.MAGIC,
            1,  # version
            self.dim,
            self.M,
            self.nlist,
            self.num_centroids,
            self.count,
        )

        flat_coarse: List[float] = []
        for cvec in self.coarse_centroids:
            flat_coarse.extend(cvec)
        coarse_bytes = struct.pack(f"<{len(flat_coarse)}f", *flat_coarse)

        list_records: List[bytes] = []
        for c_idx in range(self.nlist):
            postings = self.inverted_lists.get(c_idx, [])
            list_records.append(struct.pack("<I", len(postings)))
            for did, codes in postings:
                list_records.append(struct.pack(f"<I{self.M}s", did, codes))

        pq_path = file_path + ".pq"
        self.pq.save(pq_path)

        with open(file_path, "wb") as f:
            f.write(header)
            f.write(coarse_bytes)
            f.writelines(list_records)

    @classmethod
    def _read_coarse_centroids(
        cls, f: Any, nlist: int, dim: int
    ) -> List[Tuple[float, ...]]:
        coarse_floats = nlist * dim
        coarse_bytes = f.read(coarse_floats * 4)
        flat_coarse = struct.unpack(f"<{coarse_floats}f", coarse_bytes)
        centroids: List[Tuple[float, ...]] = []
        for i in range(nlist):
            centroids.append(tuple(flat_coarse[i * dim : (i + 1) * dim]))
        return centroids

    @classmethod
    def _read_inverted_lists(
        cls, f: Any, nlist: int, M: int
    ) -> Dict[int, List[Tuple[int, bytes]]]:
        inv_lists: Dict[int, List[Tuple[int, bytes]]] = {}
        rec_size = 4 + M
        for c_idx in range(nlist):
            p_cnt_bytes = f.read(4)
            if not p_cnt_bytes:
                break
            p_cnt = struct.unpack("<I", p_cnt_bytes)[0]
            chunk = f.read(p_cnt * rec_size)
            postings: List[Tuple[int, bytes]] = []
            for p_idx in range(p_cnt):
                offset = p_idx * rec_size
                did, codes = struct.unpack(f"<I{M}s", chunk[offset : offset + rec_size])
                postings.append((did, codes))
            inv_lists[c_idx] = postings
        return inv_lists

    @classmethod
    def load(cls, file_path: str) -> "IVFPQIndex":
        """Loads IVF-PQ index from a binary file."""
        pq_path = file_path + ".pq"
        if not os.path.exists(pq_path):
            raise FileNotFoundError(f"PQ codebook not found at {pq_path}")
        pq = ProductQuantizer.load(pq_path)

        with open(file_path, "rb") as f:
            header_bytes = f.read(cls.HEADER_SIZE)
            if len(header_bytes) < cls.HEADER_SIZE:
                raise ValueError("Invalid IVF-PQ file: header truncated")
            magic, version, dim, M, nlist, num_centroids, count = struct.unpack(
                cls.HEADER_FORMAT, header_bytes
            )
            if magic != cls.MAGIC:
                raise ValueError(f"Invalid magic bytes: {magic}")

            index = cls(dim=dim, M=M, nlist=nlist, num_centroids=num_centroids)
            index.pq = pq
            index.count = count
            index.coarse_centroids = cls._read_coarse_centroids(f, nlist, dim)
            index.inverted_lists = cls._read_inverted_lists(f, nlist, M)
            index.is_trained = True
            return index
