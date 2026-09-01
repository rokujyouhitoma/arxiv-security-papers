#!/usr/bin/env python3
"""
Citation Network & Authority Index using Power Iteration PageRank.
"""

from collections import defaultdict
from typing import Dict, List, Optional, Set


class CitationNetworkIndex:
    """
    Citation Network & Authority Index using Power Iteration PageRank.
    """

    def __init__(self) -> None:
        self.citations: Dict[str, Set[str]] = defaultdict(set)
        self.inbound: Dict[str, Set[str]] = defaultdict(set)
        self.pagerank: Dict[str, float] = {}

    def add_citation(self, source_paper: str, target_paper: str) -> None:
        self.citations[source_paper].add(target_paper)
        self.inbound[target_paper].add(source_paper)

    def _calc_node_inbound(
        self, doc_id: str, ranks: Dict[str, float], initial_score: float
    ) -> float:
        return sum(
            ranks.get(src, initial_score) / max(len(self.citations.get(src, set())), 1)
            for src in self.inbound.get(doc_id, set())
        )

    def _pagerank_iteration(
        self,
        all_doc_ids: List[str],
        ranks: Dict[str, float],
        initial_score: float,
        damping: float,
        N: int,
    ) -> Dict[str, float]:
        new_ranks: Dict[str, float] = {}
        for doc_id in all_doc_ids:
            inbound_sum = self._calc_node_inbound(doc_id, ranks, initial_score)
            new_ranks[doc_id] = (1.0 - damping) / N + damping * inbound_sum
        return new_ranks

    def _init_pagerank_scores(
        self, all_doc_ids: List[str], initial_score: float
    ) -> Optional[Dict[str, float]]:
        if not self.inbound and not self.citations:
            self.pagerank = {doc_id: initial_score for doc_id in all_doc_ids}
            return self.pagerank
        return None

    def compute_pagerank(
        self,
        all_doc_ids: List[str],
        damping: float = 0.85,
        max_iter: int = 20,
    ) -> Dict[str, float]:
        N = len(all_doc_ids)
        if N == 0:
            return {}

        initial_score = 1.0 / N
        trivial = self._init_pagerank_scores(all_doc_ids, initial_score)
        if trivial is not None:
            return trivial

        ranks = {doc_id: initial_score for doc_id in all_doc_ids}
        for _ in range(max_iter):
            ranks = self._pagerank_iteration(
                all_doc_ids, ranks, initial_score, damping, N
            )

        self.pagerank = ranks
        return self.pagerank

    def get_score(self, doc_id: str) -> float:
        return self.pagerank.get(doc_id, 0.0001)
