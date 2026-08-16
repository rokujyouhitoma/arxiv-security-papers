#!/usr/bin/env python3
"""
Citation Network & Authority Index using Power Iteration PageRank.
"""

from collections import defaultdict
from typing import Dict, List, Set


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
        ranks = {doc_id: initial_score for doc_id in all_doc_ids}

        for _ in range(max_iter):
            new_ranks = {}
            for doc_id in all_doc_ids:
                inbound_sum = sum(
                    ranks.get(src, initial_score)
                    / max(len(self.citations.get(src, [])), 1)
                    for src in self.inbound.get(doc_id, [])
                )
                new_ranks[doc_id] = (1.0 - damping) / N + damping * inbound_sum
            ranks = new_ranks

        self.pagerank = ranks
        return self.pagerank

    def get_score(self, doc_id: str) -> float:
        return self.pagerank.get(doc_id, 0.0001)
