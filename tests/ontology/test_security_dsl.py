#!/usr/bin/env python3
"""
Unit tests for Cybersecurity Ontology DSL and Model Integration.
Validates that security domain definitions declared via Pure Python DSL
compile into the W3C Turtle ontology model (v2.0.0).
"""

from __future__ import annotations

from ontology.security import (
    ALL_SECURITY_CLASSES,
    SECURITY_PREFIXES,
    build_security_ontology_ast,
    export_security_ontology_turtle,
)


def test_all_14_security_classes_registered() -> None:
    """Verifies that all 14 core cybersecurity concepts are registered in DSL."""
    assert "sec" in SECURITY_PREFIXES
    assert len(ALL_SECURITY_CLASSES) == 14
    class_names = [c.__name__ for c in ALL_SECURITY_CLASSES]
    expected_names = [
        "Paper",
        "ThreatActor",
        "AttackTechnique",
        "Vulnerability",
        "TargetAsset",
        "DefenseMechanism",
        "BenchmarkMetric",
        "Incident",
        "DetectionRule",
        "PoCArtifact",
        "Precondition",
        "ResearchGap",
        "ResidualRisk",
        "PublicationVenue",
    ]
    for name in expected_names:
        assert name in class_names


def test_build_security_ontology_ast() -> None:
    """Tests that build_security_ontology_ast validates and returns complete AST."""
    doc = build_security_ontology_ast()
    assert doc.metadata.version_info == "2.0.0"
    assert doc.metadata.uri == "https://arxiv-security-papers.org/ontology/security"

    # Verify classes count
    assert len(doc.classes) == 14
    curies = list(doc.classes.keys())
    assert "sec:Paper" in curies
    assert "sec:ThreatActor" in curies
    assert "sec:AttackTechnique" in curies
    assert "sec:Vulnerability" in curies
    assert "sec:TargetAsset" in curies
    assert "sec:DefenseMechanism" in curies

    # Verify properties
    obj_prop_curies = list(doc.object_properties.keys())
    assert "sec:exploits" in obj_prop_curies
    assert "sec:targets" in obj_prop_curies
    assert "sec:mitigates" in obj_prop_curies
    assert "sec:blocks" in obj_prop_curies
    assert "sec:requiresPrecondition" in obj_prop_curies
    assert "sec:presentedAt" in obj_prop_curies

    data_prop_curies = list(doc.datatype_properties.keys())
    assert "sec:arxivId" in data_prop_curies
    assert "sec:severity" in data_prop_curies
    assert "sec:accessLevel" in data_prop_curies

    # Verify axioms
    assert len(doc.axioms) > 0


def test_export_security_ontology_turtle() -> None:
    """Tests that export_security_ontology_turtle produces valid W3C Turtle code."""
    ttl = export_security_ontology_turtle()

    # Prefixes
    assert "@prefix sec:" in ttl
    assert "<https://arxiv-security-papers.org/ontology/security#> ." in ttl
    assert "@prefix owl:" in ttl

    # Ontology Metadata
    assert "<https://arxiv-security-papers.org/ontology/security>" in ttl
    assert 'owl:versionInfo "2.0.0"' in ttl

    # Classes
    assert "sec:Paper" in ttl
    assert 'rdfs:label "セキュリティ論文"@ja' in ttl
    assert "sec:AttackTechnique" in ttl
    assert 'rdfs:label "攻撃手法"@ja' in ttl
    assert "sec:Precondition" in ttl

    # Properties
    assert "sec:blocks" in ttl
    assert "sec:requiresPrecondition" in ttl
    assert "sec:arxivId" in ttl

    # Axioms
    assert "owl:disjointWith" in ttl
