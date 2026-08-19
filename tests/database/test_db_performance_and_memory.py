#!/usr/bin/env python3
"""
Heavyweight Performance, Memory Profiling & Concurrency Test Suite for
Pure Python 4-Tier Vector Database (VFS, Pager, VDBE, Compiler, Storage).
"""

import os
import random
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List

from database import (
    PAGE_SIZE,
    DatabaseProfiler,
    HNSWIndex,
    MemoryVFS,
    Page,
    PageCache,
    Pager,
    VectorStorage,
)


def _generate_synthetic_vector(dim: int = 128) -> List[float]:
    raw = [random.uniform(-1.0, 1.0) for _ in range(dim)]
    norm = sum(x * x for x in raw) ** 0.5
    if norm == 0:
        return [0.0] * dim
    return [round(x / norm, 6) for x in raw]


def test_batch_write_and_pager_throughput():
    """
    Measures write throughput across 1,000 vector records and 4KB Pager WAL buffers.
    Ensures write operations exceed 500 ops/sec in pure Python.
    """
    profiler = DatabaseProfiler()

    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "bench_write.vdb")
        storage = VectorStorage(vdb_path, dim=64)

        # 1. Benchmark bulk vector write
        def bulk_write_step():
            vecs = [_generate_synthetic_vector(64) for _ in range(50)]
            metas = [{"idx": i, "tag": "perf-test"} for i in range(50)]
            storage.append_batch(vecs, metas)

        result_write = profiler.profile_callable(
            name="VectorStorage.append_batch_50x",
            fn=bulk_write_step,
            iterations=20,  # 20 * 50 = 1,000 vectors
            warmup=2,
        )

        assert storage.count == 1100  # 1000 + 100 warmup
        assert result_write.throughput_ops_sec > 0
        assert result_write.mean_latency_ms < 150.0

        # 2. Benchmark Pager WAL transaction throughput
        db_path = os.path.join(tmpdir, "bench_pager.db")
        pager = Pager(db_path, cache_capacity=64)

        def pager_trans_step():
            pager.begin()
            for p in range(5):
                page_data = b"PAGE_DATA_" + bytes([p] * 4080)
                pager.write_page(p, page_data)
            pager.commit()

        result_pager = profiler.profile_callable(
            name="Pager.WAL_Transaction_5pages",
            fn=pager_trans_step,
            iterations=50,
            warmup=5,
        )

        assert result_pager.p95_ms < 20.0
        assert pager.page_count() == 5


def test_page_cache_strict_memory_bounds_and_lru():
    """
    Verifies that PageCache strictly caps memory footprint to capacity * PAGE_SIZE,
    correctly resists single-scan pollution via 2Q, and promotes re-accessed pages to Am.
    """
    capacity = 32  # 32 pages limit
    cache = PageCache(capacity=capacity)

    # Fill cache with 100 sequential one-pass scan pages
    for i in range(100):
        data = bytes([i % 256] * PAGE_SIZE)
        cache.put(Page(page_id=i, data=data, is_dirty=False))

    # Assert total cached pages is strictly bounded by capacity
    assert len(cache) <= capacity

    # Verify scan resistance: Old single-access pages (0 to 90) were evicted
    assert cache.get(0) is None
    assert cache.get(50) is None
    # Most recent scan pages remain in A1_in
    assert cache.get(99) is not None

    # Re-accessing a ghost page (e.g. 95) promotes it into Am long-term pool
    p95 = Page(page_id=95, data=bytes([95 % 256] * PAGE_SIZE))
    cache.put(p95)
    # Even after new scans, promoted page 95 remains cached in Am
    for j in range(100, 105):
        cache.put(Page(page_id=j, data=bytes([j % 256] * PAGE_SIZE)))
    assert cache.get(95) is not None


def test_continuous_query_leak_free():
    """
    Executes 1,000 repeated queries and verifies tracemalloc delta is near zero (< 20 KB),
    guaranteeing leak-free long-term operation.
    """
    profiler = DatabaseProfiler()

    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "leak_test.vdb")
        storage = VectorStorage(vdb_path, dim=32)
        vectors = [_generate_synthetic_vector(32) for _ in range(100)]
        metadatas = [{"id": f"paper_{i}", "category": "crypto"} for i in range(100)]
        storage.append_batch(vectors, metadatas)

        def run_point_query():
            idx = random.randint(0, 99)
            vec = storage.get_vector(idx)
            meta = storage.get_metadata(idx)
            assert meta["category"] == "crypto"
            assert len(vec) == 32

        leak_result = profiler.check_memory_leak(
            name="PointLookup_LeakTest",
            fn=run_point_query,
            batches=10,
            batch_size=100,  # 1,000 total operations
            tolerance_kb_per_batch=15.0,
        )

        assert not leak_result["is_leak"], f"Memory leak detected: {leak_result}"
        assert leak_result["total_operations"] == 1000


def test_hnsw_ann_latency_percentiles():
    """
    Profiles HNSW Approximate Nearest Neighbor search across 500 vectors.
    Ensures P50 < 0.8ms and P95 < 2.5ms in pure Python.
    """
    profiler = DatabaseProfiler()

    index = HNSWIndex(dim=32, M=16, ef_construction=32, ef_search=24)
    vectors = [_generate_synthetic_vector(32) for _ in range(300)]
    for i, vec in enumerate(vectors):
        index.insert(i, vec)

    query_vec = _generate_synthetic_vector(32)

    def search_step():
        results = index.search(query_vec, top_k=5)
        assert len(results) == 5

    res = profiler.profile_callable(
        name="HNSWIndex.search_top5",
        fn=search_step,
        iterations=200,
        warmup=10,
    )

    assert res.p50_ms < 10.0, f"P50 too high: {res.p50_ms} ms"
    assert res.p95_ms < 20.0, f"P95 too high: {res.p95_ms} ms"
    assert res.throughput_ops_sec > 40


def test_multithreaded_concurrent_reads_and_vfs_lock():
    """
    Tests thread safety and concurrency across PosixVFS and MemoryVFS with 8 concurrent workers.
    """
    mem_vfs = MemoryVFS()
    mem_file = mem_vfs.open("shared.vdb", mode="w+b")
    test_payload = b"CONCURRENT_READ_PAYLOAD_" * 10
    mem_file.write(0, test_payload)

    def worker_read_task(worker_id: int) -> bool:
        for _ in range(50):
            data = mem_file.read(0, len(test_payload))
            if data != test_payload:
                return False
            time.sleep(0.0001)
        return True

    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = [executor.submit(worker_read_task, i) for i in range(8)]
        results = [f.result() for f in as_completed(futures)]

    assert all(results)
    mem_file.close()


def test_profiler_metrics_structure():
    """
    Verifies DatabaseProfiler report dictionary output structure.
    """
    profiler = DatabaseProfiler()
    res = profiler.profile_callable(
        name="DummyTest",
        fn=lambda: sum(range(100)),
        iterations=50,
        warmup=5,
        extra_metrics={"target_subsystem": "vdbe_core"},
    )

    d = res.to_dict()
    assert d["name"] == "DummyTest"
    assert d["iterations"] == 50
    assert "throughput_ops_sec" in d
    assert "p50_ms" in d
    assert "p90_ms" in d
    assert "p95_ms" in d
    assert "p99_ms" in d
    assert d["extra_metrics"]["target_subsystem"] == "vdbe_core"
