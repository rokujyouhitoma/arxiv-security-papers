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
from typing import Dict, Sequence, Set, Union


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

    # Ideal DCG: Sort all relevant documents by score descending
    ideal_scores = sorted(graded_relevance.values(), reverse=True)[:k]
    ideal_dcg = 0.0
    for i, rel in enumerate(ideal_scores, start=1):
        if rel > 0.0:
            ideal_dcg += (math.pow(2.0, rel) - 1.0) / math.log2(i + 1.0)

    if ideal_dcg <= 0.0:
        return 0.0

    return actual_dcg / ideal_dcg
