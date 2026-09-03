#!/usr/bin/env python3
"""
Late-Interaction (ColBERT-style MaxSim) Re-ranking Operator.
Computes token-level maximum cosine similarity sums over query and document token sequences.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import math
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

MAX_QUERY_TOKENS = 32
MAX_DOC_TOKENS = 128
EPSILON = 1e-9


def dot_product(vec_a: Sequence[float], vec_b: Sequence[float]) -> float:
    """Computes inner product between two equal-length numeric vectors."""
    return sum(a * b for a, b in zip(vec_a, vec_b))


def vector_norm(vec: Sequence[float]) -> float:
    """Computes Euclidean L2 norm of a vector."""
    return math.sqrt(sum(x * x for x in vec))


def cosine_similarity(vec_a: Sequence[float], vec_b: Sequence[float]) -> float:
    """Computes cosine similarity in [-1.0, 1.0], guarding against zero division."""
    norm_a = vector_norm(vec_a)
    norm_b = vector_norm(vec_b)
    denom = norm_a * norm_b
    if denom < EPSILON:
        return 0.0
    val = dot_product(vec_a, vec_b) / denom
    if math.isnan(val) or math.isinf(val):
        return 0.0
    return max(-1.0, min(1.0, val))


def _max_sim_for_token(
    q_vec: Sequence[float], d_vecs: Sequence[Sequence[float]]
) -> float:
    """Finds maximum cosine similarity of a query token across all document tokens."""
    max_sim = -1.0
    for d_vec in d_vecs:
        sim = cosine_similarity(q_vec, d_vec)
        if sim > max_sim:
            max_sim = sim
    return max(0.0, max_sim)


def compute_maxsim(
    query_embeddings: Sequence[Sequence[float]],
    doc_embeddings: Sequence[Sequence[float]],
) -> float:
    """
    Computes ColBERT MaxSim operator:
    Score(Q, D) = Sum_{q in Q} Max_{d in D} CosineSim(q, d)
    Enforces strict token clipping (|Q| <= 32, |D| <= 128).
    """
    q_vecs = query_embeddings[:MAX_QUERY_TOKENS]
    d_vecs = doc_embeddings[:MAX_DOC_TOKENS]

    if not q_vecs or not d_vecs:
        return 0.0

    total_maxsim = sum(_max_sim_for_token(q_vec, d_vecs) for q_vec in q_vecs)
    return total_maxsim / len(q_vecs)


def _extract_doc_tokens(
    cand: Dict[str, Any],
    doc_token_getter: Optional[Callable[[Dict[str, Any]], List[str]]],
) -> List[str]:
    """Extracts and clips tokens for a candidate document."""
    if doc_token_getter:
        return doc_token_getter(cand)[:MAX_DOC_TOKENS]
    title = str(cand.get("title", ""))
    desc = str(cand.get("description", "")) or str(cand.get("snippet", ""))
    return (title + " " + desc).lower().split()[:MAX_DOC_TOKENS]


def _score_single_candidate(
    cand: Dict[str, Any],
    q_vecs: Sequence[Sequence[float]],
    embed: Callable[[str], Sequence[float]],
    doc_token_getter: Optional[Callable[[Dict[str, Any]], List[str]]],
) -> Tuple[float, Dict[str, Any]]:
    """Calculates MaxSim score for a single candidate."""
    d_tokens = _extract_doc_tokens(cand, doc_token_getter)
    if not d_tokens:
        return 0.0, cand

    d_vecs = [embed(token) for token in d_tokens]
    maxsim_score = compute_maxsim(q_vecs, d_vecs)
    cand_copy = dict(cand)
    cand_copy["maxsim_score"] = round(maxsim_score, 4)
    return maxsim_score, cand_copy


def _score_all_candidates(
    candidates: List[Dict[str, Any]],
    q_vecs: Sequence[Sequence[float]],
    embed: Callable[[str], Sequence[float]],
    doc_token_getter: Optional[Callable[[Dict[str, Any]], List[str]]],
    top_k: int,
) -> List[Dict[str, Any]]:
    """Scores, sorts, and returns top_k reranked candidates."""
    scored = [
        _score_single_candidate(cand, q_vecs, embed, doc_token_getter)
        for cand in candidates
    ]
    scored.sort(key=lambda x: x[0], reverse=True)
    return [item[1] for item in scored[:top_k]]


def _resolve_embedding_fn(
    fn: Optional[Callable[[str], Sequence[float]]],
) -> Callable[[str], Sequence[float]]:
    """Returns provided embedding function or deterministic fallback."""
    if fn:
        return fn
    from ..vector import DeterministicEmbedding

    embedder = DeterministicEmbedding(dim=32)
    return lambda t: embedder.embed_text(t)


class LateInteractionReranker:
    """
    Two-Stage Late-Interaction Reranker using token-level embeddings.
    """

    def __init__(
        self,
        embedding_fn: Optional[Callable[[str], Sequence[float]]] = None,
        embedding_dim: int = 128,
    ) -> None:
        self.embedding_fn = embedding_fn
        self.embedding_dim = embedding_dim

    def score(
        self,
        query_embeddings: Sequence[Sequence[float]],
        doc_embeddings: Sequence[Sequence[float]],
    ) -> float:
        """Computes MaxSim score for given query and document embeddings."""
        return compute_maxsim(query_embeddings, doc_embeddings)

    def rerank_candidates(
        self,
        query_tokens: List[str],
        candidates: List[Dict[str, Any]],
        doc_token_getter: Optional[Callable[[Dict[str, Any]], List[str]]] = None,
        top_k: int = 10,
    ) -> List[Dict[str, Any]]:
        """
        Reranks top candidates using MaxSim score.
        If embedding_fn is provided, token vectors are used;
        otherwise fallback deterministic hashing embeddings are generated.
        """
        if not (candidates and query_tokens):
            return candidates[:top_k]

        embed = _resolve_embedding_fn(self.embedding_fn)
        q_vecs = [embed(token) for token in query_tokens[:MAX_QUERY_TOKENS]]
        return _score_all_candidates(candidates, q_vecs, embed, doc_token_getter, top_k)
