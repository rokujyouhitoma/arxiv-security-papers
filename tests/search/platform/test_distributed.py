"""
Tests for Distributed Search & Sharding Aggregation (src/search/platform/distributed/).
"""

from search.engine.search import ScoreDoc, TopDocs
from search.platform.distributed import DistributedSearcher, ShardHandler, ShardResponse


def test_distributed_search_sharding_and_facets():
    shard_handler = ShardHandler()

    def shard_node_1(q: str, p: dict) -> ShardResponse:
        docs = [ScoreDoc(0, 10.0, {"id": "p_node1_1", "title": "Paper 1"})]
        return ShardResponse("node_1", TopDocs(1, docs), {"category": {"cs.CR": 1}})

    def shard_node_2(q: str, p: dict) -> ShardResponse:
        docs = [ScoreDoc(0, 20.0, {"id": "p_node2_1", "title": "Paper 2"})]
        return ShardResponse(
            "node_2", TopDocs(1, docs), {"category": {"cs.CR": 2, "quant-ph": 1}}
        )

    shard_handler.register_shard("node_1", shard_node_1)
    shard_handler.register_shard("node_2", shard_node_2)

    dist_searcher = DistributedSearcher(shard_handler)
    top_docs, merged_facets = dist_searcher.search("*:*", top_k=2)

    assert top_docs.total_hits == 2
    # Highest score first (node_2 has score 20.0)
    assert top_docs.score_docs[0].fields["id"] == "p_node2_1"
    assert top_docs.score_docs[0].fields["_shard_"] == "node_2"
    assert merged_facets["category"]["cs.CR"] == 3
    assert merged_facets["category"]["quant-ph"] == 1
