#!/usr/bin/env python3
"""
Micro-benchmark for HNSW vector distance computation and search throughput.
Used to measure baseline and post-optimization performance for Issue 379.
"""

import math
import operator
import time
from typing import Any, Callable, Dict, List, Sequence, Tuple


def bench_dot_implementations(dim: int = 128, iterations: int = 100_000) -> Dict[str, float]:
    v1: Sequence[float] = [float(i) for i in range(dim)]
    v2: Sequence[float] = [float(i * 2) for i in range(dim)]

    results: Dict[str, float] = {}

    # 1. Generator (Current baseline)
    t0 = time.perf_counter()
    for _ in range(iterations):
        _ = sum(x * y for x, y in zip(v1, v2))
    results["1_generator_sum_zip"] = time.perf_counter() - t0

    # 2. List comprehension
    t0 = time.perf_counter()
    for _ in range(iterations):
        _ = sum([x * y for x, y in zip(v1, v2)])
    results["2_listcomp_sum_zip"] = time.perf_counter() - t0

    # 3. For loop with zip
    t0 = time.perf_counter()
    for _ in range(iterations):
        dot = 0.0
        for x, y in zip(v1, v2):
            dot += x * y
    results["3_for_zip"] = time.perf_counter() - t0

    # 4. For loop with range index
    t0 = time.perf_counter()
    for _ in range(iterations):
        dot = 0.0
        for i in range(dim):
            dot += v1[i] * v2[i]
    results["4_for_range_index"] = time.perf_counter() - t0

    # 5. sum(map(operator.mul, v1, v2))
    mul = operator.mul
    t0 = time.perf_counter()
    for _ in range(iterations):
        _ = sum(map(mul, v1, v2))
    results["5_sum_map_mul"] = time.perf_counter() - t0

    # 6. math.fsum(map(mul, v1, v2))
    t0 = time.perf_counter()
    for _ in range(iterations):
        _ = math.fsum(map(mul, v1, v2))
    results["6_math_fsum_map_mul"] = time.perf_counter() - t0

    # 7. Unrolled while loop (4-way)
    t0 = time.perf_counter()
    for _ in range(iterations):
        dot = 0.0
        idx = 0
        while idx < dim:
            dot += (
                v1[idx] * v2[idx]
                + v1[idx + 1] * v2[idx + 1]
                + v1[idx + 2] * v2[idx + 2]
                + v1[idx + 3] * v2[idx + 3]
            )
            idx += 4
    results["7_unrolled_while_4"] = time.perf_counter() - t0

    return results


def bench_hnsw_ann_search(num_vectors: int = 500, dim: int = 128, search_queries: int = 500) -> Dict[str, float]:
    import os
    import random
    import sys

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    src_dir = os.path.join(repo_root, "src")
    if src_dir not in sys.path:
        sys.path.insert(0, src_dir)

    from database.index.index import HNSWIndex

    rng = random.Random(42)
    vectors: List[Tuple[float, ...]] = []
    for _ in range(num_vectors):
        raw = [rng.uniform(-1.0, 1.0) for _ in range(dim)]
        norm = math.sqrt(sum(x * x for x in raw)) or 1.0
        vectors.append(tuple(x / norm for x in raw))

    # Build HNSW Index
    index = HNSWIndex(dim=dim, M=16, ef_construction=64, ef_search=32, distance_metric="cosine", seed=42)
    t_build_0 = time.perf_counter()
    for i, vec in enumerate(vectors):
        index.insert(i, vec)
    build_time = time.perf_counter() - t_build_0

    # Search queries
    queries: List[Tuple[float, ...]] = []
    for _ in range(search_queries):
        raw = [rng.uniform(-1.0, 1.0) for _ in range(dim)]
        norm = math.sqrt(sum(x * x for x in raw)) or 1.0
        queries.append(tuple(x / norm for x in raw))

    t_search_0 = time.perf_counter()
    for q in queries:
        _ = index.search(q, top_k=5)
    search_time = time.perf_counter() - t_search_0

    qps = search_queries / search_time if search_time > 0 else 0.0

    return {
        "build_time_sec": build_time,
        "search_time_sec": search_time,
        "queries_per_sec": qps,
        "avg_latency_ms": (search_time / search_queries) * 1000.0,
    }


def main() -> None:
    print("=== Issue 379: HNSW Micro-Benchmark ===")
    print("--- 1. Pure Dot Product Implementations (100,000 ops, dim=128) ---")
    dot_res = bench_dot_implementations(dim=128, iterations=100_000)
    baseline = dot_res.get("1_generator_sum_zip", 1.0)
    for name, dur in sorted(dot_res.items()):
        speedup = baseline / dur if dur > 0 else 0.0
        print(f"  {name:25s}: {dur:6.4f}s ({speedup:5.2f}x vs baseline)")

    print("\n--- 2. HNSW Index ANN Search (500 vectors, 500 queries, dim=128) ---")
    ann_res = bench_hnsw_ann_search(num_vectors=500, dim=128, search_queries=500)
    print(f"  Build time (500 vectors): {ann_res['build_time_sec']:.4f}s")
    print(f"  Search time (500 queries): {ann_res['search_time_sec']:.4f}s")
    print(f"  Queries Per Second (QPS): {ann_res['queries_per_sec']:.2f} qps")
    print(f"  Avg Search Latency:       {ann_res['avg_latency_ms']:.4f} ms")


if __name__ == "__main__":
    main()
