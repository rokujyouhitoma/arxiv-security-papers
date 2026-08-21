#!/usr/bin/env python3
"""
Distributed Search Architecture and Shard Result Aggregation (Solr Paradigm).
Coordinates query fan-out across multiple index shards and merges Top-K docs and facet counts.
"""

from collections import Counter
from typing import Any, Callable, Dict, List, Optional, Tuple

from ...engine.search import ScoreDoc, TopDocs


class ShardResponse:
    """Encapsulates TopDocs and Facet results from a single shard."""

    def __init__(
        self,
        shard_id: str,
        top_docs: TopDocs,
        facets: Optional[Dict[str, Dict[str, int]]] = None,
    ) -> None:
        self.shard_id = shard_id
        self.top_docs = top_docs
        self.facets = facets or {}


class ShardHandler:
    """Manages communication and query dispatching to multiple shards."""

    def __init__(self) -> None:
        self._shard_executors: Dict[
            str, Callable[[str, Dict[str, Any]], ShardResponse]
        ] = {}

    def register_shard(
        self, shard_id: str, search_fn: Callable[[str, Dict[str, Any]], ShardResponse]
    ) -> None:
        self._shard_executors[shard_id] = search_fn

    def search_all_shards(
        self, query_str: str, params: Optional[Dict[str, Any]] = None
    ) -> List[ShardResponse]:
        p = params or {}
        responses: List[ShardResponse] = []
        for shard_id, search_fn in self._shard_executors.items():
            resp = search_fn(query_str, p)
            responses.append(resp)
        return responses


class DistributedSearcher:
    """Merges distributed shard responses into unified TopDocs and global facet aggregations."""

    def __init__(self, shard_handler: Optional[ShardHandler] = None) -> None:
        self.shard_handler = shard_handler or ShardHandler()

    def merge_results(
        self, responses: List[ShardResponse], top_k: int = 10
    ) -> Tuple[TopDocs, Dict[str, Dict[str, int]]]:
        all_score_docs: List[ScoreDoc] = []
        total_hits = 0
        merged_facets: Dict[str, Counter[str]] = {}

        for resp in responses:
            total_hits += resp.top_docs.total_hits
            for sdoc in resp.top_docs.score_docs:
                # Attach shard_id metadata
                sdoc.fields["_shard_"] = resp.shard_id
                all_score_docs.append(sdoc)

            # Merge facets
            for facet_name, counts in resp.facets.items():
                if facet_name not in merged_facets:
                    merged_facets[facet_name] = Counter()
                merged_facets[facet_name].update(counts)

        # Global Sort by Score descending
        all_score_docs.sort(key=lambda d: d.score, reverse=True)
        top_slice = all_score_docs[:top_k]

        global_top_docs = TopDocs(total_hits=total_hits, score_docs=top_slice)
        global_facets = {k: dict(v) for k, v in merged_facets.items()}
        return global_top_docs, global_facets

    def search(
        self, query_str: str, params: Optional[Dict[str, Any]] = None, top_k: int = 10
    ) -> Tuple[TopDocs, Dict[str, Dict[str, int]]]:
        responses = self.shard_handler.search_all_shards(query_str, params)
        return self.merge_results(responses, top_k=top_k)
