"""Tests for Phase 1 PIRManager and mathematical weight adaptation."""

from typing import Any

import pytest

from orchestrator.contracts import IntelligencePhase, PhaseContext, PhaseStatus
from orchestrator.pir.manager import PIRManager
from orchestrator.pir.models import PIRRequirement, TopicWeightVector


def test_topic_weight_vector_normalization() -> None:
    vec = TopicWeightVector(weights={"topic_a": 2.0, "topic_b": 2.0})
    vec.normalize()
    assert pytest.approx(vec.weights["topic_a"], 0.01) == 0.5
    assert pytest.approx(vec.weights["topic_b"], 0.01) == 0.5


def test_pir_manager_registration_and_weights() -> None:
    mgr = PIRManager()
    req1 = PIRRequirement(
        req_id="pir_1",
        title="Zero Trust Architecture",
        description="Monitor zero trust evolution.",
        target_topics=["zero-trust", "cloud-security"],
        priority_score=0.8,
    )
    mgr.register_requirement(req1)

    assert mgr.get_requirement("pir_1") is not None
    assert len(mgr.list_active_requirements()) == 1

    weights = mgr.get_weights()
    assert "zero-trust" in weights
    assert "cloud-security" in weights
    assert pytest.approx(sum(weights.values()), 0.01) == 1.0


def test_pir_manager_ema_weight_adaptation() -> None:
    mgr = PIRManager(alpha=0.5, beta=0.5, gamma=0.5, delta=0.0)
    req = PIRRequirement(
        req_id="pir_init",
        title="Initial Topic",
        description="Initial focus",
        target_topics=["topic_a"],
        priority_score=1.0,
    )
    mgr.register_requirement(req)

    # Feedback: topic_b has huge usage and gap
    updated_vec = mgr.update_weights_from_feedback(
        usage_counts={"topic_b": 100},
        knowledge_gaps={"topic_b": 5.0},
        topic_drifts={"topic_b": 1.0},
    )

    weights = updated_vec.weights
    assert "topic_b" in weights
    # topic_b weight should rise substantially
    assert weights["topic_b"] > weights["topic_a"]
    assert pytest.approx(sum(weights.values()), 0.01) == 1.0


def test_pir_manager_phase_execution_and_compensation() -> None:
    mgr = PIRManager()
    req = PIRRequirement(
        req_id="pir_test",
        title="Quantum Cryptanalysis",
        description="Monitor post-quantum attacks",
        target_topics=["quantum", "cryptography"],
    )
    mgr.register_requirement(req)

    ctx = PhaseContext(cycle_id="cycle_001", workspace_dir="/tmp")
    ctx = mgr.execute(ctx)

    assert ctx.phase_statuses[IntelligencePhase.PLANNING] == PhaseStatus.COMPLETED
    assert ctx.directive is not None
    assert ctx.directive.directive_id == "dir_cycle_001"
    assert "quantum" in ctx.directive.target_topics
    assert ctx.directive.crawl_quotas["quantum"] >= 5

    # Test compensation
    mgr.compensate(ctx)
    assert ctx.phase_statuses[IntelligencePhase.PLANNING] == PhaseStatus.COMPENSATED
    assert ctx.directive is None


def test_pir_manager_adapt_queries_from_telemetry() -> None:
    from orchestrator.contracts import FeedbackTelemetry

    mgr = PIRManager()
    telemetry = FeedbackTelemetry(
        telemetry_id="telem_01",
        ndcg_at_k=0.60,
        mean_average_precision=0.55,
        zero_hit_queries=["zero_trust_quantum"],
        frequent_topics={"llm_safety": 10},
        topic_drift_scores={"llm_safety": 0.5},
        knowledge_gaps={"quantum_zero_trust": 0.8},
    )
    vec = mgr.adapt_queries_from_telemetry(telemetry)
    assert "quantum_zero_trust" in vec.weights
    assert any(
        "quantum_zero_trust" in r.target_topics for r in mgr.list_active_requirements()
    )


def test_pir_manager_3_horizon_management_and_filtering() -> None:
    from orchestrator.pir.models import PIRHorizon

    mgr = PIRManager(auto_seed=True)
    tactical_reqs = mgr.get_requirements_by_horizon(PIRHorizon.TACTICAL)
    operational_reqs = mgr.get_requirements_by_horizon(PIRHorizon.OPERATIONAL)
    strategic_reqs = mgr.get_requirements_by_horizon(PIRHorizon.STRATEGIC)

    assert len(tactical_reqs) >= 2  # llm_sec, vuln_fuzz
    assert len(operational_reqs) >= 1  # supply_chain
    assert len(strategic_reqs) >= 1  # crypto_priv

    directive = mgr.create_directive(directive_id="dir_horizon_test")
    assert "horizon_breakdown" in directive.metadata
    assert directive.metadata["horizon_breakdown"]["tactical"] >= 2


def test_pir_manager_dynamic_escalation_triggers(tmp_path: Any) -> None:
    from orchestrator.contracts import FeedbackTelemetry
    from orchestrator.pir.models import PIRHorizon

    storage_file = str(tmp_path / "pir_registry.json")
    mgr = PIRManager(storage_path=storage_file, auto_seed=True)

    # Initial state: crypto_priv is STRATEGIC
    crypto_req = mgr.get_requirement("pir_crypto_priv")
    assert crypto_req is not None
    assert crypto_req.horizon == PIRHorizon.STRATEGIC
    assert crypto_req.escalation_level == 0

    # Manual escalation
    escalated = mgr.escalate_requirement(
        "pir_crypto_priv",
        reason="Breaking Side-Channel Attack against NIST PQC announced",
        target_horizon=PIRHorizon.TACTICAL,
    )
    assert escalated is True
    assert crypto_req.horizon == PIRHorizon.TACTICAL
    assert crypto_req.escalation_level == 1
    assert crypto_req.escalated_at is not None

    # Verify persistence and reload
    mgr2 = PIRManager(storage_path=storage_file)
    reloaded_req = mgr2.get_requirement("pir_crypto_priv")
    assert reloaded_req is not None
    assert reloaded_req.horizon == PIRHorizon.TACTICAL
    assert reloaded_req.escalation_level == 1

    # Telemetry-triggered auto-escalation
    # supply_chain is OPERATIONAL, inject high knowledge gap
    telemetry = FeedbackTelemetry(
        telemetry_id="telem_gap",
        ndcg_at_k=0.5,
        mean_average_precision=0.4,
        frequent_topics={},
        topic_drift_scores={},
        knowledge_gaps={"サプライチェーンセキュリティ": 0.9},
    )
    mgr2.adapt_queries_from_telemetry(telemetry)
    supply_req = mgr2.get_requirement("pir_supply_chain")
    assert supply_req is not None
    assert supply_req.horizon == PIRHorizon.TACTICAL
    assert supply_req.escalation_level == 1
