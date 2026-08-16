"""
Information Retrieval (IR) Evaluation Package for arXiv Security Papers.
"""

from .dataset import DEFAULT_SECURITY_GOLD_STANDARD, EvaluationQuery
from .evaluator import SearchEvaluator
from .metrics import (
    compute_average_precision,
    compute_f1_score,
    compute_ndcg_at_k,
    compute_precision_at_k,
    compute_recall_at_k,
    compute_reciprocal_rank,
)

__all__ = [
    "compute_precision_at_k",
    "compute_recall_at_k",
    "compute_f1_score",
    "compute_average_precision",
    "compute_reciprocal_rank",
    "compute_ndcg_at_k",
    "EvaluationQuery",
    "DEFAULT_SECURITY_GOLD_STANDARD",
    "SearchEvaluator",
]
