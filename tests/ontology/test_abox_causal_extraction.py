#!/usr/bin/env python3
"""Tests for Paper ABox Causal & Reified Entity Extraction and Multi-hop Graph Traversal (Issue #188)."""

from graph.engine import PropertyGraphEngine
from ontology.extractor import OntologyExtractor
from ontology.schema import EntityType, Predicate

SAMPLE_SECURITY_PAPER_MD = """---
title: "DeepExploit: Automated Privilege Escalation and Data Exfiltration in Cloud Enclaves"
arxiv_id: "2409.99999"
published: "2026-09-01"
categories:
  - "cs.CR"
primary_category: "cs.CR"
tags:
  - "cloud-security"
  - "privilege-escalation"
---

# DeepExploit: Automated Privilege Escalation and Data Exfiltration in Cloud Enclaves

## Abstract
In this work, we demonstrate how an adversary with local access can perform privilege escalation
and arbitrary code execution, resulting in severe data exfiltration and integrity violation.
Our attack exploits CVE-2024-12345 in cloud container runtimes.
We observed similar tactics in the SolarWinds and Log4Shell incidents.
Furthermore, we present GuardEnclave, a defense mechanism that prevents unauthorized kernel modifications
and neutralizes physical and remote access preconditions.
Our experimental evaluation achieves 98.5% detection accuracy in cloud environments.
Source code and artifacts are available at https://github.com/sec-research/deepexploit-poc.
"""


def test_abox_causal_and_reified_extraction():
    """Verify OntologyExtractor extracts Impact, Claim, EvaluationResult, and Incident entities."""
    entities, triples = OntologyExtractor.extract_from_okf(
        "2409.99999", SAMPLE_SECURITY_PAPER_MD
    )

    entity_types = {e.entity_type for e in entities}
    assert EntityType.PAPER in entity_types
    assert EntityType.IMPACT in entity_types
    assert EntityType.CLAIM in entity_types
    assert EntityType.EVALUATION_RESULT in entity_types
    assert EntityType.INCIDENT in entity_types

    # Check Impact Entities (STRIDE)
    impacts = [e for e in entities if e.entity_type == EntityType.IMPACT]
    stride_cats = {getattr(imp, "stride_category", "") for imp in impacts}
    assert "ElevationOfPrivilege" in stride_cats
    assert "InformationDisclosure" in stride_cats
    assert "Tampering" in stride_cats

    # Check Incidents
    incidents = [e for e in entities if e.entity_type == EntityType.INCIDENT]
    incident_ids = {getattr(inc, "incident_id", "") for inc in incidents}
    assert "SolarWinds" in incident_ids or "Log4Shell" in incident_ids

    # Check Claim and EvaluationResult
    claims = [e for e in entities if e.entity_type == EntityType.CLAIM]
    assert len(claims) >= 1
    evals = [e for e in entities if e.entity_type == EntityType.EVALUATION_RESULT]
    assert len(evals) >= 1
    assert getattr(evals[0], "success_rate", 0.0) == 98.5
    assert "Cloud" in getattr(evals[0], "target_environment", "")


def test_abox_causal_triples():
    """Verify causality and reification relationship triples are generated."""
    _, triples = OntologyExtractor.extract_from_okf(
        "2409.99999", SAMPLE_SECURITY_PAPER_MD
    )

    predicates = {t.predicate for t in triples}
    assert Predicate.ASSERTS_CLAIM in predicates
    assert Predicate.YIELDS_EVALUATION in predicates
    assert Predicate.EVALUATES_CLAIM in predicates
    assert Predicate.HAS_IMPACT in predicates
    assert Predicate.NEUTRALIZES_PRECONDITION in predicates


def test_ingest_paper_to_graph_and_causal_queries(tmp_path):
    """Verify PropertyGraphEngine stores ABox entities and answers multi-hop causal queries."""
    db_path = tmp_path / "test_abox_graph.db"
    engine = PropertyGraphEngine(storage_path=str(db_path))

    ent_count, trip_count = OntologyExtractor.ingest_paper_to_graph(
        "2409.99999", SAMPLE_SECURITY_PAPER_MD, engine
    )
    assert ent_count > 5
    assert trip_count > 5

    # Check stats count
    counts = engine._compute_cti_counts(0)
    assert counts["total_papers"] >= 1
    assert counts["total_impacts"] >= 1
    assert counts["total_claims"] >= 1
    assert counts["total_evaluations"] >= 1
    assert counts["total_incidents"] >= 1

    # Check multi-hop causal chain discovery
    paper_id = "Paper:2409.99999"
    chains = engine.find_causal_chains(paper_id, max_hops=4)
    assert len(chains) > 0

    # Execute causal query via graph query engine
    query_res = engine.execute_graph_query("causal:2409.99999", limit=50)
    assert query_res["query"] == "causal:2409.99999"
    assert len(query_res["nodes"]) > 0
    assert len(query_res["edges"]) > 0

    node_types = {n["label"] for n in query_res["nodes"]}
    assert "Paper" in node_types or "Claim" in node_types or "Impact" in node_types
