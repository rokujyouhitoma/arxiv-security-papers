#!/usr/bin/env python3
"""
Unit tests for Full-Spectrum Security Knowledge Ontology (Issue #179).
Verifies:
1. Extended classes and properties in Turtle / OWL engine.
2. High-order entity extraction (Preconditions, Gaps, DetectionRules, PoC, Venues).
3. Graph database ingestion with semantic edge types.
4. EIROM rule registry integration.
"""

from __future__ import annotations

from graph.engine import PropertyGraphEngine
from ontology.extractor import OntologyExtractor
from ontology.schema import (
    EntityType,
    PoCArtifactEntity,
    Predicate,
    SecurityOntologySchema,
)
from ontology.turtle_engine import build_full_spectrum_security_ontology


class TestFullSpectrumOntology:
    """Comprehensive test suite for Full-Spectrum Security Knowledge Ontology."""

    def test_schema_full_spectrum_types_and_predicates(self) -> None:
        """Verifies EntityType, Predicate, and ALLOWED_RELATIONS consistency."""
        assert EntityType.PRECONDITION.value == "Precondition"
        assert EntityType.DETECTION_RULE.value == "DetectionRule"
        assert EntityType.POC_ARTIFACT.value == "PoCArtifact"
        assert EntityType.RESEARCH_GAP.value == "ResearchGap"
        assert EntityType.RESIDUAL_RISK.value == "ResidualRisk"
        assert EntityType.PUBLICATION_VENUE.value == "PublicationVenue"

        assert Predicate.BLOCKS.value == "BLOCKS"
        assert Predicate.GENERATES_RULE.value == "GENERATES_RULE"
        assert Predicate.REQUIRES_PRECONDITION.value == "REQUIRES_PRECONDITION"
        assert Predicate.LEAVES_UNADDRESSED.value == "LEAVES_UNADDRESSED"
        assert Predicate.IDENTIFIES_GAP.value == "IDENTIFIES_GAP"
        assert Predicate.PRESENTED_AT.value == "PRESENTED_AT"

        # Check inverse predicates
        assert Predicate.BLOCKS.inverse == "BLOCKED_BY"
        assert Predicate.PRESENTED_AT.inverse == "HOSTED_PAPER"

        # Validate allowed relations
        assert SecurityOntologySchema.validate_triple(
            EntityType.DETECTION_RULE, Predicate.BLOCKS
        )
        assert SecurityOntologySchema.validate_triple(
            EntityType.PAPER, Predicate.REQUIRES_PRECONDITION
        )
        assert SecurityOntologySchema.validate_triple(
            EntityType.PAPER, Predicate.PRESENTED_AT
        )

    def test_turtle_engine_v2_generation(self) -> None:
        """Verifies W3C Turtle generation with extended classes and properties."""
        doc = build_full_spectrum_security_ontology()
        ttl_content = doc.serialize()

        assert 'owl:versionInfo "2.0.0"' in ttl_content
        assert "sec:Precondition rdf:type owl:Class" in ttl_content
        assert "sec:DetectionRule rdf:type owl:Class" in ttl_content
        assert "sec:PoCArtifact rdf:type owl:Class" in ttl_content
        assert "sec:ResearchGap rdf:type owl:Class" in ttl_content
        assert "sec:PublicationVenue rdf:type owl:Class" in ttl_content
        assert "sec:blocks rdf:type owl:ObjectProperty" in ttl_content
        assert "sec:requiresPrecondition rdf:type owl:ObjectProperty" in ttl_content
        assert "sec:presentedAt rdf:type owl:ObjectProperty" in ttl_content
        assert "sec:reproducibilityTier rdf:type owl:DatatypeProperty" in ttl_content

    def test_extended_knowledge_extraction(self) -> None:
        """Verifies automatic extraction of high-order entities from markdown content."""
        sample_markdown = """---
title: "Advanced EDR Bypass via Kernel Callback Manipulation"
description: "カーネルコールバックの改変による高度EDR回避攻撃とSigmaルールによる検知手法の提案"
tags:
  - kernel-security
  - edr-bypass
  - cwe-787
---

# Introduction
This paper analyzes kernel-level bypasses.
The adversary requires local access and root privilege to tamper with system callbacks.
We evaluate attack success rate against modern EDRs.
Our PoC is open-sourced at https://github.com/sec-research/edr-bypass-poc.
To mitigate this technique, we provide actionable sigma rule definitions.
However, scalability limitation remains a challenge for future work, and
this leaves unaddressed residual risk in virtualized environments.
This paper was presented at USENIX Sec 2026.
"""
        entities, triples = OntologyExtractor.extract_from_okf(
            "2609.99001", sample_markdown
        )

        entity_types = {e.entity_type for e in entities}
        assert EntityType.PAPER in entity_types
        assert EntityType.PRECONDITION in entity_types
        assert EntityType.POC_ARTIFACT in entity_types
        assert EntityType.DETECTION_RULE in entity_types
        assert EntityType.RESEARCH_GAP in entity_types
        assert EntityType.RESIDUAL_RISK in entity_types
        assert EntityType.PUBLICATION_VENUE in entity_types

        predicate_types = {t.predicate for t in triples}
        assert Predicate.REQUIRES_PRECONDITION in predicate_types
        assert Predicate.HAS_POC in predicate_types
        assert Predicate.GENERATES_RULE in predicate_types
        assert Predicate.IDENTIFIES_GAP in predicate_types
        assert Predicate.LEAVES_UNADDRESSED in predicate_types
        assert Predicate.PRESENTED_AT in predicate_types

        # Verify venue resolution
        venue_triples = [t for t in triples if t.predicate == Predicate.PRESENTED_AT]
        assert len(venue_triples) == 1
        assert venue_triples[0].object_id == "Venue:USENIXSEC"

        # Verify PoC extraction
        pocs = [e for e in entities if isinstance(e, PoCArtifactEntity)]
        assert len(pocs) == 1
        assert pocs[0].repo_url == "https://github.com/sec-research/edr-bypass-poc"

    def test_property_graph_ingestion(self) -> None:
        """Verifies ingestion of full-spectrum entities into PropertyGraphEngine."""
        engine = PropertyGraphEngine(workspace_dir="/tmp/test_full_spectrum_graph")
        sample_markdown = """---
title: "Memory Safety in Rust Firmware"
description: "組み込みファームウェアにおけるRustメモリ安全性の実証と脆弱性検証"
tags:
  - firmware-security
  - memory-safety
---

Our attack requires physical access.
We release our tool at https://github.com/firmware-lab/mem-test.
We provide semgrep rules for continuous integration.
Presented at IEEE S&P 2026.
"""
        ent_count, trip_count = OntologyExtractor.ingest_paper_to_graph(
            "2609.88888", sample_markdown, engine
        )
        assert ent_count >= 5
        assert trip_count >= 4

        # Verify vertices in engine
        paper_v = engine.get_vertex("Paper:2609.88888")
        assert paper_v is not None
        assert paper_v.label == "Paper"

        venue_v = engine.get_vertex("Venue:IEEESP")
        assert venue_v is not None
        assert venue_v.properties.get("tier") == "gold"

        poc_v = engine.get_vertex("PoCArtifact:2609.88888")
        assert poc_v is not None
        assert "github.com/firmware-lab/mem-test" in poc_v.properties.get(
            "repo_url", ""
        )

    def test_owl_inverse_of_incident_coupling_and_standards(self) -> None:
        """Verifies Issue #184: owl:inverseOf, Incident coupling, and Dublin Core / CiTO alignment."""
        doc = build_full_spectrum_security_ontology()
        ttl = doc.serialize()

        # 1. Verify standard prefixes
        assert "@prefix dcterms: <http://purl.org/dc/terms/>" in ttl
        assert "@prefix cito:  <http://purl.org/spar/cito/>" in ttl
        assert "@prefix stix:  <http://docs.oasis-open.org/cti/ns/stix#>" in ttl

        # 2. Verify owl:inverseOf bidirectional relations
        assert "owl:inverseOf sec:mitigatedBy" in ttl
        assert "owl:inverseOf sec:mitigates" in ttl
        assert "owl:inverseOf sec:exploitedBy" in ttl
        assert "owl:inverseOf sec:exploits" in ttl
        assert "owl:inverseOf sec:proposedIn" in ttl
        assert "owl:inverseOf sec:proposes" in ttl
        assert "owl:inverseOf sec:blockedBy" in ttl
        assert "owl:inverseOf sec:blocks" in ttl
        assert "owl:inverseOf sec:ruleGeneratedBy" in ttl
        assert "owl:inverseOf sec:generatesRule" in ttl
        assert "owl:inverseOf sec:preconditionRequiredBy" in ttl
        assert "owl:inverseOf sec:requiresPrecondition" in ttl
        assert "owl:inverseOf sec:cveVerifiedBy" in ttl
        assert "owl:inverseOf sec:verifiesCVE" in ttl
        assert "owl:inverseOf sec:pocOfPaper" in ttl
        assert "owl:inverseOf sec:hasPoC" in ttl

        # 3. Verify Incident coupling properties (no isolated class)
        assert "sec:exploitedIn rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:incidentObservedTechnique" in ttl
        assert "sec:leveragedVulnerability rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:vulnerabilityLeveragedIn" in ttl
        assert "sec:attributedToActor rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:actorAttributedIncident" in ttl
        assert "sec:targetsAsset rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:assetTargetedInIncident" in ttl

        # 4. Verify Dublin Core and CiTO alignment
        assert "rdfs:subPropertyOf dcterms:title" in ttl
        assert "rdfs:subPropertyOf dcterms:date" in ttl
        assert "rdfs:subPropertyOf cito:cites" in ttl

    def test_threat_model_causality_and_impact(self) -> None:
        """Verifies Issue #185: Impact class, strideCategory, and precondition neutralization causality."""
        doc = build_full_spectrum_security_ontology()
        ttl = doc.serialize()

        # 1. Verify sec:Impact class
        assert "sec:Impact rdf:type owl:Class" in ttl
        assert 'rdfs:label "被害影響・影響度"@ja' in ttl

        # 2. Verify causality object properties & inverseOf
        assert "sec:hasImpact rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:impactCausedBy" in ttl
        assert "sec:impactCausedBy rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:hasImpact" in ttl

        assert "sec:neutralizesPrecondition rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:preconditionNeutralizedBy" in ttl
        assert "sec:preconditionNeutralizedBy rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:neutralizesPrecondition" in ttl

        # 3. Verify datatype properties
        assert "sec:strideCategory rdf:type owl:DatatypeProperty" in ttl
        assert "sec:impactSeverity rdf:type owl:DatatypeProperty" in ttl

    def test_claim_evidence_reification_and_datatypes(self) -> None:
        """Verifies Issue #186: Claim, EvaluationResult, reified properties, and regex datatypes."""
        doc = build_full_spectrum_security_ontology()
        ttl = doc.serialize()

        # 1. Verify reification classes
        assert "sec:Claim rdf:type owl:Class" in ttl
        assert "sec:EvaluationResult rdf:type owl:Class" in ttl

        # 2. Verify reification object properties & inverseOf
        assert "sec:assertsClaim rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:claimAssertedBy" in ttl
        assert "sec:claimAssertedBy rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:assertsClaim" in ttl

        assert "sec:evaluatesClaim rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:claimEvaluatedIn" in ttl
        assert "sec:claimEvaluatedIn rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:evaluatesClaim" in ttl

        assert "sec:evaluatesTechnique rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:techniqueEvaluatedIn" in ttl
        assert "sec:techniqueEvaluatedIn rdf:type owl:ObjectProperty" in ttl
        assert "owl:inverseOf sec:evaluatesTechnique" in ttl

        # 3. Verify reification edge attributes
        assert "sec:successRate rdf:type owl:DatatypeProperty" in ttl
        assert "sec:targetEnvironment rdf:type owl:DatatypeProperty" in ttl
        assert "sec:empiricalEvidenceLevel rdf:type owl:DatatypeProperty" in ttl

        # 4. Verify custom Datatype definitions with regex restrictions
        assert "sec:CVEIdentifier rdf:type rdfs:Datatype" in ttl
        assert "owl:onDatatype xsd:string" in ttl
        assert 'xsd:pattern "[cC][vV][eE]-[0-9]{4}-[0-9]{4,}"' in ttl

        assert "sec:CWEIdentifier rdf:type rdfs:Datatype" in ttl
        assert 'xsd:pattern "[cC][wW][eE]-[0-9]+"' in ttl

        assert "sec:AttackTechniqueIdentifier rdf:type rdfs:Datatype" in ttl
        assert 'xsd:pattern "T[0-9]{4}(\\.[0-9]{3})?"' in ttl
