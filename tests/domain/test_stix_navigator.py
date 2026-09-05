#!/usr/bin/env python3
"""
Unit Tests for Pure-Python STIX 2.1 Model, Technique Inference,
Navigator Layer v4.5 Generator, and PropertyGraphEngine Persistence.
"""

from __future__ import annotations

import json
import os
import tempfile
import uuid

from graph.engine import PropertyGraphEngine
from src.domain.security.cti import (
    AttackPattern,
    CourseOfAction,
    InferredTechnique,
    NavigatorLayerConfig,
    StixBundle,
    StixRelationship,
    TechniqueInferenceEngine,
    batch_sync_papers_to_graph,
    export_navigator_file,
    find_papers_for_technique,
    find_techniques_for_paper,
    generate_navigator_layer,
    generate_stix_id,
    sync_cti_inferences_to_graph,
)


class TestStixModel:
    """Tests for Pure-Python STIX 2.1 Data Models."""

    def test_deterministic_id_generation(self) -> None:
        id1 = generate_stix_id("attack-pattern", "T1190")
        id2 = generate_stix_id("attack-pattern", "T1190")
        id3 = generate_stix_id("attack-pattern", "T1566")

        assert id1 == id2
        assert id1 != id3
        assert id1.startswith("attack-pattern--")
        # Validate UUID part
        uuid_part = id1.split("--")[1]
        assert uuid.UUID(uuid_part).version == 5

    def test_attack_pattern_sdo(self) -> None:
        pattern = AttackPattern(
            name="Exploit Public-Facing Application",
            description="Adversaries may attempt to exploit vulnerabilities.",
            external_references=[
                {"source_name": "mitre-attack", "external_id": "T1190"}
            ],
            kill_chain_phases=[
                {"kill_chain_name": "mitre-attack", "phase_name": "initial-access"}
            ],
        )
        d = pattern.to_dict()
        assert d["type"] == "attack-pattern"
        assert d["spec_version"] == "2.1"
        assert d["name"] == "Exploit Public-Facing Application"
        assert d["id"].startswith("attack-pattern--")
        assert len(d["external_references"]) == 1
        assert len(d["kill_chain_phases"]) == 1

    def test_course_of_action_and_relationship(self) -> None:
        coa = CourseOfAction(
            name="Network Segmentation",
            description="Segment network zones.",
            external_references=[
                {"source_name": "mitre-attack", "external_id": "M1030"}
            ],
        )
        rel = StixRelationship(
            relationship_type="mitigates",
            source_ref=coa.id,
            target_ref="attack-pattern--12345",
        )
        bundle = StixBundle(objects=[coa.to_dict(), rel.to_dict()])
        bundle_dict = bundle.to_dict()

        assert bundle_dict["type"] == "bundle"
        assert bundle_dict["id"].startswith("bundle--")
        assert len(bundle_dict["objects"]) == 2

        json_str = bundle.to_json()
        loaded = json.loads(json_str)
        assert loaded["id"] == bundle.id


class TestTechniqueInference:
    """Tests for Keyword & Context-Driven Technique Inference Engine."""

    def test_direct_regex_id_matching(self) -> None:
        engine = TechniqueInferenceEngine(min_confidence=0.4)
        title = "Novel Analysis of T1190 and Zero-Day Exploits"
        abstract = "We investigate how T1059 interpreters execute malicious payloads."

        results = engine.infer(title=title, text=abstract)
        matched_ids = {r.technique_id for r in results}

        assert "T1190" in matched_ids
        assert "T1059" in matched_ids
        for r in results:
            if r.technique_id in ("T1190", "T1059"):
                assert r.confidence == 1.0

    def test_vocabulary_matching_and_focus_classification(self) -> None:
        engine = TechniqueInferenceEngine(min_confidence=0.4)

        # Offensive context
        off_title = "Exploiting Public Web APIs via SQL Injection and RCE"
        off_text = (
            "We present a novel proof of concept attack weaponizing vulnerabilities."
        )
        off_results = engine.infer(title=off_title, text=off_text)

        assert len(off_results) > 0
        top = off_results[0]
        assert top.technique_id == "T1190"
        assert top.research_focus == "offensive"
        assert any("rce" in kw or "sql injection" in kw for kw in top.matched_keywords)

        # Defensive context
        def_title = "Mitigating Phishing and Credential Harvesting"
        def_text = (
            "A robust countermeasure and detection firewall against social engineering."
        )
        def_results = engine.infer(title=def_title, text=def_text)

        assert len(def_results) > 0
        top_def = def_results[0]
        assert top_def.technique_id == "T1566"
        assert top_def.research_focus == "defensive"


class TestNavigatorLayer:
    """Tests for ATT&CK Navigator Layer v4.5 Generator and Exporter."""

    def test_layer_generation_and_export(self) -> None:
        inferences_by_paper = {
            "2401.00001": [
                InferredTechnique(
                    technique_id="T1190",
                    technique_name="Exploit Public-Facing Application",
                    tactic="initial-access",
                    confidence=0.9,
                    matched_keywords=["rce"],
                    research_focus="offensive",
                )
            ],
            "2401.00002": [
                InferredTechnique(
                    technique_id="T1190",
                    technique_name="Exploit Public-Facing Application",
                    tactic="initial-access",
                    confidence=0.85,
                    matched_keywords=["sql injection"],
                    research_focus="offensive",
                ),
                InferredTechnique(
                    technique_id="T1566",
                    technique_name="Phishing",
                    tactic="initial-access",
                    confidence=0.75,
                    matched_keywords=["phishing"],
                    research_focus="defensive",
                ),
            ],
        }

        config = NavigatorLayerConfig(name="Test Layer v4.5")
        layer = generate_navigator_layer(inferences_by_paper, config)

        assert layer["name"] == "Test Layer v4.5"
        assert layer["domain"] == "enterprise-attack"
        assert layer["versions"]["navigator"] == "4.5"
        assert len(layer["techniques"]) == 2

        tech_map = {t["techniqueID"]: t for t in layer["techniques"]}
        # T1190 is in 2 papers -> score 2, orange color
        assert tech_map["T1190"]["score"] == 2
        assert tech_map["T1190"]["color"] == "#f6b26b"
        assert "2401.00001" in tech_map["T1190"]["comment"]
        assert "2401.00002" in tech_map["T1190"]["comment"]

        # T1566 is in 1 paper -> score 1, yellow color
        assert tech_map["T1566"]["score"] == 1
        assert tech_map["T1566"]["color"] == "#ffd966"

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = os.path.join(tmpdir, "navigator_layer.json")
            saved_path = export_navigator_file(layer, out_file)
            assert os.path.exists(saved_path)

            with open(saved_path, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            assert loaded["name"] == "Test Layer v4.5"


class TestGraphPersistenceBridge:
    """Tests for PropertyGraphEngine Vertex and Edge Persistence."""

    def test_sync_cti_inferences_to_graph(self) -> None:
        graph = PropertyGraphEngine(workspace_dir="/tmp/test_graph", memory_only=True)

        inferences = [
            InferredTechnique(
                technique_id="T1190",
                technique_name="Exploit Public-Facing Application",
                tactic="initial-access",
                confidence=0.95,
                matched_keywords=["rce", "sql injection"],
                research_focus="offensive",
            ),
            InferredTechnique(
                technique_id="T1486",
                technique_name="Data Encrypted for Impact",
                tactic="impact",
                confidence=0.8,
                matched_keywords=["ransomware"],
                research_focus="defensive",
            ),
        ]

        result = sync_cti_inferences_to_graph(
            paper_id="2401.99999v1",
            title="Analysis of Web Exploitation and Ransomware Defense",
            inferences=inferences,
            graph_engine=graph,
            save=False,
        )

        assert result["paper_vertex_id"] == "paper:2401.99999"
        assert result["techniques_synced"] == 2
        assert len(result["edges_created"]) == 2

        # Verify vertices in graph
        paper_v = graph.get_vertex("paper:2401.99999")
        assert paper_v is not None
        assert paper_v.label == "Paper"
        assert paper_v.properties["arxiv_id"] == "2401.99999"

        t1190_v = graph.get_vertex("technique:T1190")
        assert t1190_v is not None
        assert t1190_v.label == "AttackTechnique"
        assert t1190_v.properties["mitre_id"] == "T1190"

        # Verify edges and labels
        edges = graph.get_out_edges("paper:2401.99999")
        edge_map = {e.dst_id: e for e in edges}

        assert "technique:T1190" in edge_map
        assert edge_map["technique:T1190"].label == "TARGETS"  # Offensive
        assert edge_map["technique:T1190"].weight == 0.95

        assert "technique:T1486" in edge_map
        assert edge_map["technique:T1486"].label == "PROPOSES_DEFENSE"  # Defensive
        assert edge_map["technique:T1486"].weight == 0.8

        # Verify bidirectional traversal queries
        papers_for_t1190 = find_papers_for_technique("T1190", graph)
        assert len(papers_for_t1190) == 1
        assert papers_for_t1190[0].id == "paper:2401.99999"

        techs_for_paper = find_techniques_for_paper("2401.99999", graph)
        assert len(techs_for_paper) == 2
        tech_ids = {t.id for t in techs_for_paper}
        assert "technique:T1190" in tech_ids
        assert "technique:T1486" in tech_ids

    def test_batch_sync_papers_to_graph(self) -> None:
        graph = PropertyGraphEngine(workspace_dir="/tmp/test_graph", memory_only=True)

        batch = [
            {
                "paper_id": "2401.00001",
                "title": "Paper 1",
                "inferences": [
                    InferredTechnique(
                        technique_id="T1190",
                        technique_name="Exploit",
                        tactic="initial-access",
                        confidence=0.8,
                    )
                ],
            },
            {
                "paper_id": "2401.00002",
                "title": "Paper 2",
                "inferences": [
                    InferredTechnique(
                        technique_id="T1190",
                        technique_name="Exploit",
                        tactic="initial-access",
                        confidence=0.7,
                    ),
                    InferredTechnique(
                        technique_id="T1566",
                        technique_name="Phishing",
                        tactic="initial-access",
                        confidence=0.6,
                    ),
                ],
            },
        ]

        summary = batch_sync_papers_to_graph(batch, graph, save=False)
        assert summary["synced_papers"] == 2
        assert summary["synced_edges"] == 3

        papers = find_papers_for_technique("T1190", graph)
        assert len(papers) == 2
        paper_ids = {p.id for p in papers}
        assert "paper:2401.00001" in paper_ids
        assert "paper:2401.00002" in paper_ids
