#!/usr/bin/env python3
"""
Information Retrieval (IR) Evaluation Metrics.
Provides pure, standard implementations of:
- Precision@K
- Recall@K
- F1-Score / F_beta
- Average Precision (AP) & Mean Average Precision (MAP)
- Reciprocal Rank (RR) & Mean Reciprocal Rank (MRR)
- Normalized Discounted Cumulative Gain (NDCG@K)
"""

import math
from typing import Any, Dict, List, Sequence, Set, Tuple, Union


def compute_precision_at_k(
    retrieved_ids: Sequence[str],
    relevant_ids: Union[Set[str], Sequence[str]],
    k: int = 10,
) -> float:
    """
    Computes Precision@K: Proportion of top-k retrieved documents that are relevant.
    Precision@K = |Retrieved@K ∩ Relevant| / K
    """
    if k <= 0:
        return 0.0
    rel_set = set(relevant_ids)
    top_k = retrieved_ids[:k]
    hits = sum(1 for doc_id in top_k if doc_id in rel_set)
    return hits / float(k)


def compute_recall_at_k(
    retrieved_ids: Sequence[str],
    relevant_ids: Union[Set[str], Sequence[str]],
    k: int = 10,
) -> float:
    """
    Computes Recall@K: Proportion of total relevant documents retrieved in top-k.
    Recall@K = |Retrieved@K ∩ Relevant| / |Relevant|
    """
    rel_set = set(relevant_ids)
    if not rel_set:
        return 0.0
    top_k = retrieved_ids[:k]
    hits = sum(1 for doc_id in top_k if doc_id in rel_set)
    return hits / float(len(rel_set))


def compute_f1_score(precision: float, recall: float, beta: float = 1.0) -> float:
    """
    Computes F-score (harmonic mean of precision and recall).
    F_beta = (1 + beta^2) * (P * R) / (beta^2 * P + R)
    """
    if precision <= 0.0 or recall <= 0.0:
        return 0.0
    beta_sq = beta * beta
    return (1.0 + beta_sq) * (precision * recall) / (beta_sq * precision + recall)


def compute_average_precision(
    retrieved_ids: Sequence[str],
    relevant_ids: Union[Set[str], Sequence[str]],
) -> float:
    """
    Computes Average Precision (AP) for a single query.
    AP = sum_{k=1}^N (Precision@k * rel(k)) / |Relevant|
    """
    rel_set = set(relevant_ids)
    if not rel_set or not retrieved_ids:
        return 0.0

    hit_count = 0
    precision_sum = 0.0

    for rank, doc_id in enumerate(retrieved_ids, start=1):
        if doc_id in rel_set:
            hit_count += 1
            precision_sum += hit_count / float(rank)

    return precision_sum / float(len(rel_set))


def compute_reciprocal_rank(
    retrieved_ids: Sequence[str],
    relevant_ids: Union[Set[str], Sequence[str]],
) -> float:
    """
    Computes Reciprocal Rank (RR): 1 / rank of the first relevant document.
    """
    rel_set = set(relevant_ids)
    if not rel_set:
        return 0.0

    for rank, doc_id in enumerate(retrieved_ids, start=1):
        if doc_id in rel_set:
            return 1.0 / float(rank)

    return 0.0


def compute_dcg_at_k(
    retrieved_ids: Sequence[str],
    graded_relevance: Dict[str, float],
    k: int = 10,
) -> float:
    """
    Computes Discounted Cumulative Gain at K:
    DCG@K = sum_{i=1}^K (2^{rel_i} - 1) / log2(i + 1)
    """
    dcg = 0.0
    top_k = retrieved_ids[:k]
    for i, doc_id in enumerate(top_k, start=1):
        rel = graded_relevance.get(doc_id, 0.0)
        if rel > 0.0:
            dcg += (math.pow(2.0, rel) - 1.0) / math.log2(i + 1.0)
    return dcg


def _compute_ideal_dcg(graded_relevance: Dict[str, float], k: int) -> float:
    ideal_scores = sorted(graded_relevance.values(), reverse=True)[:k]
    ideal_dcg = 0.0
    for i, rel in enumerate(ideal_scores, start=1):
        if rel > 0.0:
            ideal_dcg += (math.pow(2.0, rel) - 1.0) / math.log2(i + 1.0)
    return ideal_dcg


def compute_ndcg_at_k(
    retrieved_ids: Sequence[str],
    graded_relevance: Dict[str, float],
    k: int = 10,
) -> float:
    """
    Computes Normalized Discounted Cumulative Gain at K:
    NDCG@K = DCG@K / IDCG@K
    """
    if k <= 0 or not graded_relevance:
        return 0.0

    actual_dcg = compute_dcg_at_k(retrieved_ids, graded_relevance, k=k)
    ideal_dcg = _compute_ideal_dcg(graded_relevance, k)
    if ideal_dcg <= 0.0:
        return 0.0

    return actual_dcg / ideal_dcg


class PerformanceMetrics:
    """System efficiency and throughput profiling metrics for search evaluation."""

    def __init__(
        self,
        qps: float,
        latency_p50_ms: float,
        latency_p95_ms: float,
        latency_p99_ms: float,
        avg_latency_ms: float,
        memory_rss_mb: float,
    ) -> None:
        self.qps = qps
        self.latency_p50_ms = latency_p50_ms
        self.latency_p95_ms = latency_p95_ms
        self.latency_p99_ms = latency_p99_ms
        self.avg_latency_ms = avg_latency_ms
        self.memory_rss_mb = memory_rss_mb

    def to_dict(self) -> Dict[str, float]:
        """Serializes metrics to a dictionary."""
        return {
            "qps": self.qps,
            "latency_p50_ms": self.latency_p50_ms,
            "latency_p95_ms": self.latency_p95_ms,
            "latency_p99_ms": self.latency_p99_ms,
            "avg_latency_ms": self.avg_latency_ms,
            "memory_rss_mb": self.memory_rss_mb,
        }


def _collect_query_latencies(
    search_fn: Any, queries: Sequence[str], top_k: int, iterations: int
) -> Tuple[List[float], float]:
    import time

    latencies_ms: List[float] = []
    t_start = time.perf_counter()
    for _ in range(iterations):
        for q in queries:
            t0 = time.perf_counter()
            search_fn(q, top_k)
            t1 = time.perf_counter()
            latencies_ms.append((t1 - t0) * 1000.0)
    total_time = time.perf_counter() - t_start
    return latencies_ms, total_time


def _compute_percentile_latencies(
    latencies_ms: List[float],
) -> Tuple[float, float, float, float]:
    if not latencies_ms:
        return 0.0, 0.0, 0.0, 0.0
    total_queries = len(latencies_ms)
    latencies_sorted = sorted(latencies_ms)
    p50_idx = int(total_queries * 0.50)
    p95_idx = min(total_queries - 1, int(total_queries * 0.95))
    p99_idx = min(total_queries - 1, int(total_queries * 0.99))

    p50 = latencies_sorted[p50_idx]
    p95 = latencies_sorted[p95_idx]
    p99 = latencies_sorted[p99_idx]
    avg_lat = sum(latencies_ms) / float(total_queries)
    return p50, p95, p99, avg_lat


def profile_search_performance(
    search_fn: Any,
    queries: Sequence[str],
    top_k: int = 10,
    warmup: int = 2,
    iterations: int = 1,
) -> PerformanceMetrics:
    """Profiles query latency, throughput (QPS), and memory usage for a given search function."""
    import resource

    if not queries:
        return PerformanceMetrics(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

    for _ in range(warmup):
        for q in queries:
            search_fn(q, top_k)

    latencies_ms, total_time = _collect_query_latencies(
        search_fn, queries, top_k, iterations
    )
    p50, p95, p99, avg_lat = _compute_percentile_latencies(latencies_ms)

    total_queries = len(latencies_ms)
    qps = float(total_queries) / total_time if total_time > 0 else 0.0

    rusage = resource.getrusage(resource.RUSAGE_SELF)
    rss_mb = rusage.ru_maxrss / 1024.0

    return PerformanceMetrics(
        qps=round(qps, 2),
        latency_p50_ms=round(p50, 3),
        latency_p95_ms=round(p95, 3),
        latency_p99_ms=round(p99, 3),
        avg_latency_ms=round(avg_lat, 3),
        memory_rss_mb=round(rss_mb, 2),
    )
