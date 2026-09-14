#!/usr/bin/env python3
"""
Unit tests verifying objective extraction of Claims and Empirical Evidence
with accountable evaluation functions and audit provenance (Issue 295).
"""

from ontology.extended_extractor import ExtendedExtractor
from ontology.schema import EntityType, EvaluationResultEntity, Predicate


def test_no_fallback_on_clean_text() -> None:
    """Verifies that text without empirical metrics returns None, avoiding placeholder fallbacks."""
    abstract = (
        "We present a novel theoretical security model for decentralized ledgers."
    )
    val, metric_type, snippet = ExtendedExtractor._extract_metric_details(abstract)
    env = ExtendedExtractor._extract_eval_environment(abstract.lower())

    assert val is None
    assert metric_type == "EmpiricalObservation"
    assert snippet == ""
    assert env is None

    entities, triples = ExtendedExtractor.extract_claims_and_evidence(
        clean_id="2501.00001",
        text=abstract,
        meta={"title": "Theoretical Model"},
        paper_id="Paper:2501.00001",
        tech_entities=[],
    )

    # Must contain ClaimEntity, but MUST NOT fabricate EvaluationResultEntity
    assert len(entities) == 1
    assert entities[0].entity_type == EntityType.CLAIM
    eval_entities = [
        e for e in entities if e.entity_type == EntityType.EVALUATION_RESULT
    ]
    assert len(eval_entities) == 0

    # No YIELDS_EVALUATION triple
    yields_triples = [t for t in triples if t.predicate == Predicate.YIELDS_EVALUATION]
    assert len(yields_triples) == 0


def test_empirical_evidence_extracted_with_audit_provenance() -> None:
    """Verifies that genuine metrics, classification, snippets, and confidence rationale are extracted."""
    abstract = "Our defense mechanism achieves 98.5% detection accuracy on Linux Kernel firmware."
    val, metric_type, snippet = ExtendedExtractor._extract_metric_details(abstract)
    env = ExtendedExtractor._extract_eval_environment(abstract.lower())

    assert val == 98.5
    assert metric_type == "DetectionRate"
    assert "98.5% detection accuracy" in snippet
    assert env in ("Linux Kernel", "Embedded/IoT Firmware")

    # Verify confidence evaluation function
    conf, rationale = ExtendedExtractor._compute_confidence_score(
        metric_type=metric_type, has_env=True, text_lower=abstract.lower()
    )
    # w_metric=1.0, w_env=1.0, w_syntax=1.0 ("achieve") -> 1.0 * 0.4 + 1.0 * 0.3 + 1.0 * 0.3 = 1.0
    assert conf == 1.0
    assert "DetectionRate" in rationale
    assert "f_conf=1.00" in rationale

    entities, triples = ExtendedExtractor.extract_claims_and_evidence(
        clean_id="2501.00002",
        text=abstract,
        meta={"title": "Empirical Defense"},
        paper_id="Paper:2501.00002",
        tech_entities=[],
    )

    eval_entities = [e for e in entities if isinstance(e, EvaluationResultEntity)]
    assert len(eval_entities) == 1
    ev = eval_entities[0]
    assert ev.success_rate == 98.5
    assert ev.value == 98.5
    assert ev.metric_type == "DetectionRate"
    assert ev.confidence_score == 1.0
    assert "98.5%" in ev.name
    assert "DetectionRate" in ev.name
    assert "98.5% detection accuracy" in ev.evidence_snippet
    assert "f_conf=" in ev.confidence_rationale

    # Triples must carry the calculated confidence score
    yields_triples = [t for t in triples if t.predicate == Predicate.YIELDS_EVALUATION]
    assert len(yields_triples) == 1
    assert yields_triples[0].weight == 1.0
