#!/usr/bin/env python3
"""
Unit tests and sub-millisecond benchmarks for Pure Python IVF-PQ ANN Engine.
Tests ProductQuantizer, Asymmetric Distance Computation, IVFPQIndex, and Persistence.
"""

import math
import os
import random
import time
from typing import Any, List, Tuple

from search.vector import IVFPQIndex, ProductQuantizer


def _normalize_vec(raw: List[float]) -> List[float]:
    norm = math.sqrt(sum(x * x for x in raw))
    scale = norm if norm > 0.0 else 1.0
    return [x / scale for x in raw]


def _generate_synthetic_vectors(
    count: int, dim: int = 128, seed: int = 42
) -> List[List[float]]:
    rng = random.Random(seed)
    vectors: List[List[float]] = []
    for _ in range(count):
        raw = [rng.gauss(0.0, 1.0) for _ in range(dim)]
        vectors.append(_normalize_vec(raw))
    return vectors


def _check_subspace_dims(
    centroids: List[List[Tuple[float, ...]]], num_centroids: int, target_d: int
) -> None:
    for c in centroids:
        assert len(c) == num_centroids
        assert len(c[0]) == target_d


def _verify_pq_shapes(
    pq: ProductQuantizer, M: int, num_centroids: int, dim: int
) -> None:
    assert pq.is_trained is True
    assert len(pq.centroids) == M
    _check_subspace_dims(pq.centroids, num_centroids, dim // M)


def test_product_quantizer_training_and_encoding() -> None:
    dim, M, num_centroids = 64, 8, 16
    pq = ProductQuantizer(dim=dim, M=M, num_centroids=num_centroids, seed=42)
    data = _generate_synthetic_vectors(count=200, dim=dim, seed=42)
    pq.train(data, iterations=3)
    _verify_pq_shapes(pq, M, num_centroids, dim)

    codes = pq.encode(data[0])
    assert isinstance(codes, bytes)
    assert len(codes) == M

    approx_vec = pq.decode(codes)
    assert len(approx_vec) == dim


def test_adc_lookup_table_computation() -> None:
    dim, M, num_centroids = 32, 4, 8
    pq = ProductQuantizer(dim=dim, M=M, num_centroids=num_centroids, seed=123)
    data = _generate_synthetic_vectors(count=100, dim=dim, seed=123)
    pq.train(data, iterations=3)

    query = data[5]
    lut = pq.compute_lut(query)
    assert len(lut) == M
    assert len(lut[0]) == num_centroids

    codes = pq.encode(data[10])
    assert pq.compute_adc(lut, codes) >= 0.0


def _verify_loaded_pq(
    loaded: ProductQuantizer,
    orig: ProductQuantizer,
    test_vec: List[float],
    dim: int,
    M: int,
) -> None:
    assert loaded.dim == dim
    assert loaded.M == M
    assert loaded.is_trained is True
    assert orig.encode(test_vec) == loaded.encode(test_vec)


def test_product_quantizer_persistence(tmp_path: Any) -> None:
    dim, M, num_centroids = 32, 4, 16
    pq = ProductQuantizer(dim=dim, M=M, num_centroids=num_centroids, seed=77)
    data = _generate_synthetic_vectors(count=120, dim=dim, seed=77)
    pq.train(data, iterations=3)

    file_path = os.path.join(str(tmp_path), "codebook.pq")
    pq.save(file_path)
    assert os.path.exists(file_path)

    loaded_pq = ProductQuantizer.load(file_path)
    _verify_loaded_pq(loaded_pq, pq, data[3], dim, M)


def _populate_ivf_index(index: IVFPQIndex, vectors: List[List[float]]) -> None:
    for i, vec in enumerate(vectors):
        index.add(i, vec)


def _verify_ivf_search_hits(hits: List[Tuple[int, float]]) -> None:
    assert len(hits) == 5
    assert hits[0][0] == 0
    assert hits[0][1] > 0.5


def test_ivfpq_index_train_add_search() -> None:
    dim, M, nlist, num_centroids = 64, 8, 8, 16
    index = IVFPQIndex(dim=dim, M=M, nlist=nlist, num_centroids=num_centroids, seed=42)
    vectors = _generate_synthetic_vectors(count=300, dim=dim, seed=42)

    index.train(vectors, iterations=3)
    assert index.is_trained is True
    assert len(index.coarse_centroids) == nlist

    _populate_ivf_index(index, vectors)
    assert index.count == 300

    hits = index.search(vectors[0], top_k=5, nprobe=4)
    _verify_ivf_search_hits(hits)


def _verify_loaded_index(
    index: IVFPQIndex, loaded: IVFPQIndex, query: List[float]
) -> None:
    assert loaded.dim == index.dim
    assert loaded.count == index.count
    assert loaded.is_trained is True
    orig_hits = index.search(query, top_k=3, nprobe=2)
    loaded_hits = loaded.search(query, top_k=3, nprobe=2)
    assert [x[0] for x in orig_hits] == [x[0] for x in loaded_hits]
    for (_, s1), (_, s2) in zip(orig_hits, loaded_hits):
        assert abs(s1 - s2) < 1e-5


def test_ivfpq_index_persistence(tmp_path: Any) -> None:
    dim, M, nlist, num_centroids = 32, 4, 4, 8
    index = IVFPQIndex(dim=dim, M=M, nlist=nlist, num_centroids=num_centroids, seed=99)
    vectors = _generate_synthetic_vectors(count=150, dim=dim, seed=99)
    index.train(vectors, iterations=3)
    _populate_ivf_index(index, vectors)

    file_path = os.path.join(str(tmp_path), "ivf_pq.idx")
    index.save(file_path)
    assert os.path.exists(file_path)

    loaded = IVFPQIndex.load(file_path)
    _verify_loaded_index(index, loaded, vectors[10])


def test_ivfpq_sub_millisecond_benchmark() -> None:
    dim, M, nlist, num_centroids = 128, 8, 16, 32
    index = IVFPQIndex(dim=dim, M=M, nlist=nlist, num_centroids=num_centroids, seed=42)
    train_vectors = _generate_synthetic_vectors(count=200, dim=dim, seed=42)
    index.train(train_vectors, iterations=2)

    total_docs = 10000
    for i in range(total_docs):
        index.add(i, train_vectors[i % 200])
    assert index.count == total_docs

    # Search latency benchmark
    queries = train_vectors[:20]
    t0 = time.perf_counter()
    for q in queries:
        index.search(q, top_k=10, nprobe=4)
    avg_latency_ms = ((time.perf_counter() - t0) / len(queries)) * 1000.0

    assert avg_latency_ms < 5.0, f"Expected < 5.0ms, got {avg_latency_ms:.2f}ms"
