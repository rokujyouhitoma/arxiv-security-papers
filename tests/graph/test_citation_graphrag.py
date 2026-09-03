#!/usr/bin/env python3
"""
Unit Tests for Citation Network and CTI Multi-Hop GraphRAG Pipeline.
Validates Issue 129 requirements:
- Citation link extraction and [:CITES] edge creation
- Pure Python PageRank centrality computation
- Multi-hop causal reasoning across attack techniques, citations, and mitigations
"""

import unittest

from graph.citation_linker import CitationLinker
from graph.engine import PropertyGraphEngine
from graph.graphrag import GraphRAGPipeline
from graph.traversal import compute_pagerank


class TestCitationGraphRAG(unittest.TestCase):
    """Tests for citation linking, PageRank, and GraphRAG multihop exploration."""

    def setUp(self) -> None:
        self.engine = PropertyGraphEngine()

        # Add Paper vertices
        self.engine.add_vertex(
            "Paper:2401.0001", "Paper", {"title": "Foundational Memory Exploit"}
        )
        self.engine.add_vertex(
            "Paper:2401.0002", "Paper", {"title": "Derived ROP Chain Attack"}
        )
        self.engine.add_vertex(
            "Paper:2401.0003", "Paper", {"title": "Formal Verification Defense"}
        )

        # Add CTI vertices
        self.engine.add_vertex(
            "AttackTechnique:T1059", "AttackTechnique", {"name": "Command Execution"}
        )
        self.engine.add_vertex(
            "DefenseMechanism:ASLR", "DefenseMechanism", {"name": "ASLR Defense"}
        )

        # Add initial CTI edges
        self.engine.add_edge(
            "Paper:2401.0001", "AttackTechnique:T1059", "EXPLOITS", {}, 1.0
        )
        self.engine.add_edge(
            "DefenseMechanism:ASLR", "AttackTechnique:T1059", "MITIGATES", {}, 1.0
        )
        self.engine.add_edge(
            "Paper:2401.0003", "DefenseMechanism:ASLR", "PROPOSES", {}, 1.0
        )

    def test_citation_linker_extraction_and_edge_creation(self) -> None:
        """Tests extracting cited arXiv IDs and building [:CITES] edges."""
        text = "As shown in prior research (arXiv:2401.0001 and 2401.0002v2), memory leaks occur."
        cited = CitationLinker.extract_cited_arxiv_ids(text, self_id="2401.0002")
        self.assertEqual(cited, ["2401.0001"])

        # Link paper 2401.0002 citing 2401.0001
        added = CitationLinker.link_paper_citations(self.engine, "2401.0002", text)
        self.assertEqual(added, 1)

        edges = list(self.engine.get_outgoing_edges("Paper:2401.0002"))
        self.assertTrue(
            any(e.label == "CITES" and e.dst_id == "Paper:2401.0001" for e in edges)
        )

    def test_compute_pagerank(self) -> None:
        """Tests PageRank score convergence across directed graph."""
        # Add citations: Paper 2 and Paper 3 cite Paper 1 (making Paper 1 the hub)
        self.engine.add_edge("Paper:2401.0002", "Paper:2401.0001", "CITES", {}, 1.0)
        self.engine.add_edge("Paper:2401.0003", "Paper:2401.0001", "CITES", {}, 1.0)

        scores = compute_pagerank(self.engine, max_iter=30)
        self.assertEqual(len(scores), self.engine.vertex_count)
        # Paper 1 should have highest PageRank among papers due to incoming citations
        self.assertGreater(scores["Paper:2401.0001"], scores["Paper:2401.0002"])
        self.assertGreater(scores["Paper:2401.0001"], scores["Paper:2401.0003"])

    def test_graphrag_query_attack_evolution(self) -> None:
        """Tests multihop attack evolution query starting from an AttackTechnique."""
        # Link Paper 2 citing Paper 1
        self.engine.add_edge("Paper:2401.0002", "Paper:2401.0001", "CITES", {}, 1.0)

        rag = GraphRAGPipeline(self.engine)
        result = rag.query_attack_evolution("T1059", max_depth=3)

        self.assertGreater(result["total_nodes_visited"], 2)
        papers = result["evolution_papers"]
        paper_ids = [p["paper_id"] for p in papers]
        self.assertIn("2401.0001", paper_ids)

        mitigations = result["mitigations"]
        self.assertTrue(any("ASLR" in m["defense_id"] for m in mitigations))


if __name__ == "__main__":
    unittest.main()
