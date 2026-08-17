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

    def fuse(
        self,
        bm25_results: Sequence[Dict[str, Any]],
        vector_results: Sequence[Dict[str, Any]],
        top_k: int = 10,
        id_key: str = "id",
    ) -> List[Dict[str, Any]]:
        """
        Fuses BM25 and Vector search results using RRF.
        Returns Top-K fused results with rank and score breakdowns.
        """
        doc_map: Dict[str, Dict[str, Any]] = {}
        rrf_scores: Dict[str, float] = {}
        bm25_ranks: Dict[str, int] = {}
        vector_ranks: Dict[str, int] = {}
        bm25_raw_scores: Dict[str, float] = {}
        vector_raw_scores: Dict[str, float] = {}

        # 1. Process BM25 Rankings
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

        # 2. Process Vector Rankings
        for rank, doc in enumerate(vector_results, start=1):
            did = str(doc.get(id_key) or doc.get("arxiv_id") or "")
            if not did:
                continue
            if did not in doc_map:
                doc_map[did] = dict(doc)
            else:
                # Merge document fields if missing
                for k_doc, v_doc in doc.items():
                    if k_doc not in doc_map[did]:
                        doc_map[did][k_doc] = v_doc
            vector_ranks[did] = rank
            vector_raw_scores[did] = float(
                doc.get("vector_similarity", doc.get("score", 0.0))
            )
            rrf_scores[did] = rrf_scores.get(did, 0.0) + (
                self.vector_weight / (self.k + rank)
            )

        # 3. Sort by RRF Score descending
        sorted_ids = sorted(
            rrf_scores.keys(), key=lambda d: rrf_scores[d], reverse=True
        )

        # 4. Construct Final Result Objects
        fused: List[Dict[str, Any]] = []
        for did in sorted_ids[:top_k]:
            res = doc_map[did]
            res["score"] = round(rrf_scores[did], 6)
            res["rrf_score"] = round(rrf_scores[did], 6)
            res["bm25_rank"] = bm25_ranks.get(did)
            res["bm25_score"] = round(bm25_raw_scores.get(did, 0.0), 4)
            res["vector_rank"] = vector_ranks.get(did)
            res["vector_similarity"] = round(vector_raw_scores.get(did, 0.0), 4)
            fused.append(res)

        return fused
