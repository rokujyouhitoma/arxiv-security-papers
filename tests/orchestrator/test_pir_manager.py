"""Tests for Phase 1 PIRManager and mathematical weight adaptation."""

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
