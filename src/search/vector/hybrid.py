#!/usr/bin/env python3
"""
Reciprocal Rank Fusion (RRF) & Multi-Modal Hybrid Scorer.
Combines Lexical (BM25) and Semantic (Vector ANN) search results into unified ranked hits.
"""

from typing import Any, Dict, List, Sequence


class RRFHybridScorer:
    """
    Combines ranked results from multiple search modalities (BM25 + Vector)
    using Reciprocal Rank Fusion (RRF).

    Formula:
        RRF_Score(d) = (w_bm25 / (k + rank_bm25(d))) + (w_vec / (k + rank_vec(d)))
    """

    def __init__(
        self,
        k: int = 60,
        bm25_weight: float = 0.5,
        vector_weight: float = 0.5,
    ) -> None:
        self.k = max(1, k)
        self.bm25_weight = bm25_weight
        self.vector_weight = vector_weight

    def _accumulate_bm25(
        self,
        bm25_results: Sequence[Dict[str, Any]],
        id_key: str,
        doc_map: Dict[str, Dict[str, Any]],
        rrf_scores: Dict[str, float],
        bm25_ranks: Dict[str, int],
        bm25_raw_scores: Dict[str, float],
    ) -> None:
        for rank, doc in enumerate(bm25_results, start=1):
            did = str(doc.get(id_key) or doc.get("arxiv_id") or "")
            if not did:
                continue
            doc_map[did] = dict(doc)
            bm25_ranks[did] = rank
            bm25_raw_scores[did] = float(doc.get("score", 0.0))
            rrf_scores[did] = rrf_scores.get(did, 0.0) + (
                self.bm25_weight / (self.k + rank)
            )

    def _merge_doc_fields(
        self, did: str, doc: Dict[str, Any], doc_map: Dict[str, Dict[str, Any]]
    ) -> None:
        if did not in doc_map:
            doc_map[did] = dict(doc)
        else:
            for k_doc, v_doc in doc.items():
                if k_doc not in doc_map[did]:
                    doc_map[did][k_doc] = v_doc

    def _accumulate_vector(
        self,
        vector_results: Sequence[Dict[str, Any]],
        id_key: str,
        doc_map: Dict[str, Dict[str, Any]],
        rrf_scores: Dict[str, float],
        vector_ranks: Dict[str, int],
        vector_raw_scores: Dict[str, float],
    ) -> None:
        for rank, doc in enumerate(vector_results, start=1):
            did = str(doc.get(id_key) or doc.get("arxiv_id") or "")
            if not did:
                continue
            self._merge_doc_fields(did, doc, doc_map)
            vector_ranks[did] = rank
            vector_raw_scores[did] = float(
                doc.get("vector_similarity", doc.get("score", 0.0))
            )
            rrf_scores[did] = rrf_scores.get(did, 0.0) + (
                self.vector_weight / (self.k + rank)
            )

    def fuse(
        self,
        bm25_results: Sequence[Dict[str, Any]],
        vector_results: Sequence[Dict[str, Any]],
        top_k: int = 10,
        id_key: str = "id",
    ) -> List[Dict[str, Any]]:
        """Fuses BM25 and Vector search results using RRF."""
        doc_map: Dict[str, Dict[str, Any]] = {}
        rrf_scores: Dict[str, float] = {}
        bm25_ranks: Dict[str, int] = {}
        vector_ranks: Dict[str, int] = {}
        bm25_raw_scores: Dict[str, float] = {}
        vector_raw_scores: Dict[str, float] = {}

        self._accumulate_bm25(
            bm25_results, id_key, doc_map, rrf_scores, bm25_ranks, bm25_raw_scores
        )
        self._accumulate_vector(
            vector_results, id_key, doc_map, rrf_scores, vector_ranks, vector_raw_scores
        )

        sorted_ids = sorted(
            rrf_scores.keys(), key=lambda x: rrf_scores[x], reverse=True
        )[:top_k]

        fused_results: List[Dict[str, Any]] = []
        for did in sorted_ids:
            doc = doc_map[did]
            fused_doc = dict(doc)
            fused_doc["rrf_score"] = round(rrf_scores[did], 6)
            fused_doc["bm25_rank"] = bm25_ranks.get(did)
            fused_doc["vector_rank"] = vector_ranks.get(did)
            fused_doc["bm25_raw_score"] = bm25_raw_scores.get(did, 0.0)
            fused_doc["vector_raw_score"] = vector_raw_scores.get(did, 0.0)
            fused_results.append(fused_doc)

        return fused_results
