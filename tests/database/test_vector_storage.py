#!/usr/bin/env python3
"""
Unit tests for Pure Python Binary Vector Storage, Deterministic Embedding,
HNSW Approximate Nearest Neighbor Index, and RRF Hybrid Scorer.
"""

import math
import os
import random
import tempfile
import time
from typing import List, Tuple

import pytest

from database import (
    DeterministicEmbedding,
    HNSWIndex,
    VectorDBClient,
    VectorDBProtocolError,
    VectorDBProtocolHandler,
    VectorStorage,
    VectorStorageSecurityError,
)
from search.vector import RRFHybridScorer


def test_deterministic_embedding():
    embedder = DeterministicEmbedding(dim=64)
    v1 = embedder.embed_text("Zero Trust Architecture and Cryptography")
    v2 = embedder.embed_text("Zero Trust Architecture and Cryptography")
    v3 = embedder.embed_text("Quantum Key Distribution")

    assert len(v1) == 64
    assert v1 == v2  # Determinism

    # Check L2 unit length: norm == 1.0
    norm1 = math.sqrt(sum(x * x for x in v1))
    assert abs(norm1 - 1.0) < 1e-5

    # Dot product / cosine similarity
    sim_same = sum(a * b for a, b in zip(v1, v2))
    sim_diff = sum(a * b for a, b in zip(v1, v3))
    assert abs(sim_same - 1.0) < 1e-5
    assert sim_diff < sim_same


def test_vector_storage_binary_io():
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "test.vdb")
        storage = VectorStorage(vdb_path, dim=32)

        # Generate sample vectors
        vectors: List[Tuple[float, ...]] = [
            tuple(float(i + j) for j in range(32)) for i in range(10)
        ]
        metadata = [{"id": f"paper_{i}", "title": f"Paper {i}"} for i in range(10)]

        # 1. Write all vectors
        storage.write_all(vectors, metadata)
        assert storage.count == 10
        assert os.path.exists(vdb_path)

        # 2. Memory-mapped zero-copy read
        with VectorStorage(vdb_path, dim=32) as loaded_storage:
            assert loaded_storage.count == 10
            vec0 = loaded_storage.get_vector(0)
            assert len(vec0) == 32
            assert vec0[0] == pytest.approx(0.0)
            assert vec0[31] == pytest.approx(31.0)

            # Retrieve by doc_id
            vec5 = loaded_storage.get_vector_by_id("paper_5")
            assert vec5 is not None
            assert vec5[0] == pytest.approx(5.0)

            meta5 = loaded_storage.get_metadata(5)
            assert meta5["title"] == "Paper 5"

        # 3. Append vector
        new_vec = tuple(float(100 + j) for j in range(32))
        new_idx = storage.append(new_vec, {"id": "paper_10", "title": "Paper 10"})
        assert new_idx == 10
        assert storage.count == 11
        assert storage.get_vector(10)[0] == pytest.approx(100.0)


def test_vector_storage_security_validation():
    with tempfile.TemporaryDirectory() as tmpdir:
        corrupt_path = os.path.join(tmpdir, "corrupt.vdb")
        # Write invalid magic bytes
        with open(corrupt_path, "wb") as f:
            f.write(b"BADMAGIC" + b"\x00" * 24)

        with pytest.raises(VectorStorageSecurityError):
            VectorStorage(corrupt_path, dim=32)


def test_hnsw_ann_search_accuracy():
    """
    Validates HNSW Approximate Nearest Neighbor search against brute-force linear scan.
    Verifies Recall@K >= 0.90.
    """
    dim = 64
    num_items = 300
    top_k = 5
    rng = random.Random(42)

    # Generate normalized random vectors
    embedder = DeterministicEmbedding(dim=dim)
    vectors: List[Tuple[float, ...]] = []
    for _ in range(num_items):
        raw = [rng.gauss(0.0, 1.0) for _ in range(dim)]
        vectors.append(embedder.normalize(raw))

    # 1. Build HNSW Index
    index = HNSWIndex(dim=dim, M=16, ef_construction=64, ef_search=32, seed=42)
    index.build_from_storage(vectors)

    # 2. Evaluate accuracy across test queries
    hits = 0
    total_queries = 20

    for q_idx in range(total_queries):
        q_raw = [rng.gauss(0.0, 1.0) for _ in range(dim)]
        q_vec = embedder.normalize(q_raw)

        # Ground truth via brute force scan
        all_sims = [
            (i, sum(a * b for a, b in zip(q_vec, vectors[i]))) for i in range(num_items)
        ]
        all_sims.sort(key=lambda x: x[1], reverse=True)
        ground_truth_top_ids = set(idx for idx, _ in all_sims[:top_k])

        # HNSW search
        ann_results = index.search(q_vec, top_k=top_k)
        ann_ids = set(idx for idx, _ in ann_results)

        # Overlap
        hits += len(ground_truth_top_ids & ann_ids)

    recall_at_k = hits / (total_queries * top_k)
    assert (
        recall_at_k >= 0.90
    ), f"HNSW Recall@{top_k} was {recall_at_k:.2f}, expected >= 0.90"


def test_hnsw_persistence():
    with tempfile.TemporaryDirectory() as tmpdir:
        index_file = os.path.join(tmpdir, "hnsw.json")
        dim = 16
        index = HNSWIndex(dim=dim, M=8, seed=123)

        vectors = {
            i: tuple(float(i * 0.1 + j * 0.01) for j in range(dim)) for i in range(20)
        }
        for idx, vec in vectors.items():
            index.add_item(idx, vec)

        index.save(index_file)
        assert os.path.exists(index_file)

        # Load
        loaded_index = HNSWIndex.load(index_file, vectors=vectors)
        assert loaded_index.dim == dim
        assert loaded_index.max_level == index.max_level

        # Compare search outputs
        q = tuple(0.5 for _ in range(dim))
        orig_res = index.search(q, top_k=3)
        loaded_res = loaded_index.search(q, top_k=3)
        assert orig_res == loaded_res


def test_rrf_hybrid_scorer():
    scorer = RRFHybridScorer(k=60, bm25_weight=0.6, vector_weight=0.4)

    bm25_docs = [
        {"id": "doc_A", "score": 12.5, "title": "Paper A"},
        {"id": "doc_B", "score": 10.0, "title": "Paper B"},
        {"id": "doc_C", "score": 8.0, "title": "Paper C"},
    ]

    vector_docs = [
        {"id": "doc_B", "score": 0.95, "title": "Paper B"},
        {"id": "doc_D", "score": 0.90, "title": "Paper D"},
        {"id": "doc_A", "score": 0.85, "title": "Paper A"},
    ]

    fused = scorer.fuse(bm25_docs, vector_docs, top_k=3)

    assert len(fused) == 3
    # doc_B (BM25 rank 2, Vector rank 1) and doc_A (BM25 rank 1, Vector rank 3) should be on top
    fused_ids = [d["id"] for d in fused]
    assert "doc_B" in fused_ids
    assert "doc_A" in fused_ids
    assert "rrf_score" in fused[0]
    assert "bm25_rank" in fused[0]
    assert "vector_rank" in fused[0]


def test_hnsw_sub_10ms_latency():
    """Verifies that HNSW search completes in < 10ms for 1,000 vectors."""
    dim = 64
    num_items = 1000
    rng = random.Random(99)
    embedder = DeterministicEmbedding(dim=dim)

    vectors: List[Tuple[float, ...]] = []
    for _ in range(num_items):
        raw = [rng.random() for _ in range(dim)]
        vectors.append(embedder.normalize(raw))

    index = HNSWIndex(dim=dim, M=16, ef_construction=32, ef_search=16, seed=99)
    index.build_from_storage(vectors)

    query = embedder.normalize([rng.random() for _ in range(dim)])

    # Measure search latency
    latencies_ms: List[float] = []
    for _ in range(50):
        t0 = time.perf_counter()
        _ = index.search(query, top_k=10)
        latencies_ms.append((time.perf_counter() - t0) * 1000.0)

    p95_ms = sorted(latencies_ms)[int(len(latencies_ms) * 0.95)]
    avg_ms = sum(latencies_ms) / len(latencies_ms)

    assert avg_ms < 5.0, f"Average search latency {avg_ms:.2f}ms >= 5.0ms"
    assert p95_ms < 10.0, f"P95 search latency {p95_ms:.2f}ms >= 10.0ms"


def test_vector_db_protocol_client_loose_coupling():
    """
    Verifies that all Vector DB operations succeed strictly through the DB Protocol Client.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "protocol_test.vdb")
        storage = VectorStorage(vdb_path, dim=16)
        handler = VectorDBProtocolHandler(storage=storage)
        client = VectorDBClient(handler=handler)

        # 1. Ping
        assert client.ping() is True

        # 2. Bulk Write via protocol
        sample_vecs = [
            tuple(1.0 if j == i else 0.0 for j in range(16)) for i in range(10)
        ]
        sample_meta = [
            {"id": f"p_{i}", "title": f"Protocol Paper {i}"} for i in range(10)
        ]
        count = client.bulk_write(sample_vecs, sample_meta)
        assert count == 10

        # 3. Info via protocol
        info = client.get_info()
        assert info["dimension"] == 16
        assert info["count"] == 10

        # 4. Insert single vector via protocol
        new_vec = tuple(1.0 if j == 10 else 0.0 for j in range(16))
        new_id = client.insert(new_vec, {"id": "p_10", "title": "Protocol Paper 10"})
        assert new_id == "p_10"

        # 5. Get by ID via protocol
        doc = client.get_by_id("p_10")
        assert doc is not None
        assert doc["id"] == "p_10"
        assert doc["metadata"]["title"] == "Protocol Paper 10"

        # Non-existent doc
        missing_doc = client.get_by_id("non_existent")
        assert missing_doc is None

        # 6. KNN Search via protocol
        query_vec = tuple(1.0 if j == 10 else 0.0 for j in range(16))
        knn_matches = client.search_knn(vector=query_vec, top_k=3)
        assert len(knn_matches) == 3
        # The exact match p_10 should be top
        assert knn_matches[0]["id"] == "p_10"
        assert knn_matches[0]["score"] == pytest.approx(1.0, abs=1e-3)

        # 7. Invalid operation error handling
        raw_error_resp = handler.handle_request({"op": "unknown_op", "params": {}})
        assert raw_error_resp["status"] == "error"
        assert "Unknown operation" in raw_error_resp["error"]

        # 8. Protocol client exception handling
        with pytest.raises(VectorDBProtocolError):
            client.insert([], {})
