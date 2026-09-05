#!/usr/bin/env python3
"""
Unit tests for Edge Inference Mechanism, Confidence Attributes, and Graph Filtering.
Tests InferenceEvidence, Edge property persistence, Edge helper methods,
and PropertyGraphEngine conditional traversal (min_confidence, min_tier, rules).
"""

from __future__ import annotations

from domain.security.cti import (
    InferenceEvidence,
    InferredTechnique,
    TechniqueInferenceEngine,
    find_papers_for_technique,
    find_techniques_for_paper,
    sync_cti_inferences_to_graph,
)
from graph.engine import PropertyGraphEngine
from graph.structures import Edge


class TestInferenceEvidenceAndTechnique:
    """Tests for InferenceEvidence and enhanced InferredTechnique data structures."""

    def test_inference_evidence_serialization(self) -> None:
        ev = InferenceEvidence(
            rule_id="RULE-EDGE-PAPER-TECH-REGEX-01",
            rule_name="Direct Technique ID Match",
            rule_category="pattern",
            matched_terms=["T1190"],
            target_field="combined",
            score_contribution=1.0,
            snippet="Exploiting T1190 vulnerabilities in server APIs.",
        )
        d = ev.to_dict()
        assert d["rule_id"] == "RULE-EDGE-PAPER-TECH-REGEX-01"
        assert d["score_contribution"] == 1.0
        assert "T1190" in d["matched_terms"]
        assert d["snippet"] == "Exploiting T1190 vulnerabilities in server APIs."

        restored = InferenceEvidence.from_dict(d)
        assert restored == ev

    def test_technique_inference_engine_generates_rich_metadata(self) -> None:
        engine = TechniqueInferenceEngine(min_confidence=0.4)
        title = "In-Depth Analysis of T1190 and Public Web Exploits"
        abstract = "We investigate remote code execution vulnerabilities weaponizing zero-day payloads."

        results = engine.infer(title=title, text=abstract)
        assert len(results) > 0

        t1190 = next(r for r in results if r.technique_id == "T1190")
        assert t1190.confidence == 1.0
        assert t1190.confidence_tier == "HIGH"
        assert t1190.primary_rule_id == "RULE-EDGE-PAPER-TECH-REGEX-01"
        assert t1190.inference_mechanism == "regex_direct_id"
        assert len(t1190.source_text_hash) == 16
        assert len(t1190.evidences) >= 1
        assert "T1190" in t1190.evidence_quote

        # Verify serialization
        d = t1190.to_dict()
        assert d["confidence_tier"] == "HIGH"
        assert d["inference_mechanism"] == "regex_direct_id"
        assert d["source_text_hash"] == t1190.source_text_hash
        assert len(d["evidences"]) >= 1


class TestEdgeHelperMethods:
    """Tests for Edge class helper methods in structures.py."""

    def test_edge_confidence_and_tier(self) -> None:
        edge_high = Edge(
            src_id="paper:2601.0001",
            dst_id="technique:T1190",
            label="TARGETS",
            weight=0.95,
            properties={
                "confidence": 0.95,
                "confidence_tier": "HIGH",
                "primary_rule_id": "RULE-EDGE-PAPER-TECH-REGEX-01",
                "applied_rules": ["RULE-EDGE-PAPER-TECH-REGEX-01"],
            },
        )
        assert edge_high.get_confidence() == 0.95
        assert edge_high.get_confidence_tier() == "HIGH"
        assert edge_high.is_high_confidence() is True
        assert edge_high.has_rule("RULE-EDGE-PAPER-TECH-REGEX-01") is True
        assert edge_high.has_rule("RULE-NONEXISTENT") is False
        assert edge_high.get_primary_rule() == "RULE-EDGE-PAPER-TECH-REGEX-01"

    def test_edge_tier_fallback_calculation(self) -> None:
        edge_mid = Edge(
            src_id="paper:2601.0002",
            dst_id="technique:T1059",
            label="DISCUSSES",
            weight=0.6,
            properties={"confidence": 0.6},
        )
        assert edge_mid.get_confidence_tier() == "MEDIUM"
        assert edge_mid.is_high_confidence() is False

        edge_low = Edge(
            src_id="paper:2601.0003",
            dst_id="technique:T1082",
            label="DISCUSSES",
            weight=0.3,
            properties={"confidence": 0.3},
        )
        assert edge_low.get_confidence_tier() == "LOW"


class TestGraphEngineEdgeFiltering:
    """Tests for PropertyGraphEngine edge filtering by confidence, tier, and rules."""

    def test_get_out_edges_filtering(self) -> None:
        engine = PropertyGraphEngine(memory_only=True)
        engine.add_vertex("paper:1")
        engine.add_vertex("tech:T1")
        engine.add_vertex("tech:T2")
        engine.add_vertex("tech:T3")

        engine.add_edge(
            src_id="paper:1",
            dst_id="tech:T1",
            label="TARGETS",
            weight=0.9,
            properties={
                "confidence": 0.9,
                "confidence_tier": "HIGH",
                "primary_rule_id": "RULE-1",
                "inference_mechanism": "regex_direct_id",
            },
        )
        engine.add_edge(
            src_id="paper:1",
            dst_id="tech:T2",
            label="TARGETS",
            weight=0.6,
            properties={
                "confidence": 0.6,
                "confidence_tier": "MEDIUM",
                "primary_rule_id": "RULE-2",
                "inference_mechanism": "title_keyword",
            },
        )
        engine.add_edge(
            src_id="paper:1",
            dst_id="tech:T3",
            label="DISCUSSES",
            weight=0.3,
            properties={
                "confidence": 0.3,
                "confidence_tier": "LOW",
                "primary_rule_id": "RULE-3",
                "inference_mechanism": "abstract_semantic_scoring",
            },
        )

        # 1. Unfiltered
        all_edges = engine.get_out_edges("paper:1")
        assert len(all_edges) == 3

        # 2. Min confidence threshold
        high_conf_edges = engine.get_out_edges("paper:1", min_confidence=0.7)
        assert len(high_conf_edges) == 1
        assert high_conf_edges[0].dst_id == "tech:T1"

        # 3. Min tier constraint (MEDIUM -> MEDIUM & HIGH)
        mid_tier_edges = engine.get_out_edges("paper:1", min_tier="MEDIUM")
        assert len(mid_tier_edges) == 2
        assert {e.dst_id for e in mid_tier_edges} == {"tech:T1", "tech:T2"}

        # 4. Allowed rules filter
        rule_filtered = engine.get_out_edges("paper:1", allowed_rules=["RULE-2"])
        assert len(rule_filtered) == 1
        assert rule_filtered[0].dst_id == "tech:T2"

        # 5. Allowed mechanisms filter
        mech_filtered = engine.get_out_edges(
            "paper:1", allowed_mechanisms=["regex_direct_id"]
        )
        assert len(mech_filtered) == 1
        assert mech_filtered[0].dst_id == "tech:T1"


class TestPersistenceBridgeWithConfidence:
    """Tests for graph_bridge persistence and query filtering."""

    def test_sync_and_filtered_query(self) -> None:
        graph = PropertyGraphEngine(memory_only=True)
        tech_inf = InferredTechnique(
            technique_id="T1190",
            technique_name="Exploit Public-Facing Application",
            tactic="initial-access",
            confidence=0.92,
            matched_keywords=["T1190", "rce"],
            research_focus="offensive",
            applied_rules=[
                "RULE-EDGE-PAPER-TECH-REGEX-01",
                "RULE-EDGE-FOCUS-OFFENSIVE-01",
            ],
            primary_rule_id="RULE-EDGE-PAPER-TECH-REGEX-01",
            inference_mechanism="regex_direct_id",
            evidences=[
                InferenceEvidence(
                    rule_id="RULE-EDGE-PAPER-TECH-REGEX-01",
                    rule_name="Direct Technique ID Match",
                    rule_category="pattern",
                    matched_terms=["T1190"],
                    target_field="combined",
                    score_contribution=1.0,
                    snippet="Found T1190 in abstract",
                )
            ],
            confidence_tier="HIGH",
            source_text_hash="abcdef1234567890",
            evidence_quote="Found T1190 in abstract",
        )

        res = sync_cti_inferences_to_graph(
            paper_id="2601.12345",
            title="Analysis of T1190 Exploits",
            inferences=[tech_inf],
            graph_engine=graph,
            save=False,
        )
        assert res["techniques_synced"] == 1

        # Check edge properties
        paper_edges = graph.get_out_edges("paper:2601.12345")
        assert len(paper_edges) == 1
        edge = paper_edges[0]
        assert edge.properties["confidence_tier"] == "HIGH"
        assert edge.properties["primary_rule_id"] == "RULE-EDGE-PAPER-TECH-REGEX-01"
        assert edge.properties["inference_mechanism"] == "regex_direct_id"
        assert edge.properties["source_text_hash"] == "abcdef1234567890"
        assert len(edge.properties["evidences"]) == 1

        # Filtered query: find_papers_for_technique with HIGH tier
        papers_high = find_papers_for_technique(
            "T1190", graph, min_tier="HIGH", rule_id="RULE-EDGE-PAPER-TECH-REGEX-01"
        )
        assert len(papers_high) == 1
        assert papers_high[0].id == "paper:2601.12345"

        # Filtered query with rule mismatch returns empty list
        papers_mismatch = find_papers_for_technique(
            "T1190", graph, rule_id="RULE-NONEXISTENT"
        )
        assert len(papers_mismatch) == 0

        # Filtered query: find_techniques_for_paper
        techs = find_techniques_for_paper("2601.12345", graph, min_confidence=0.8)
        assert len(techs) == 1
        assert techs[0].id == "technique:T1190"
