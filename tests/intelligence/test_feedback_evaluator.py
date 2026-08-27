"""Tests for Phase 6 FeedbackEvaluator and knowledge gap computation."""

import pytest

from intelligence.contracts import IntelligencePhase, PhaseContext, PhaseStatus
from intelligence.feedback.evaluator import FeedbackEvaluator


def test_feedback_evaluator_knowledge_gap_and_drift() -> None:
    evaluator = FeedbackEvaluator()

    # Log queries: 'quantum' has low NDCG (0.2) and zero hits
    evaluator.record_query_event(
        query="quantum factoring algorithm",
        topic="quantum",
        ndcg_score=0.2,
        hits_count=0,
    )
    evaluator.record_query_event(
        query="lattice crypto attack", topic="quantum", ndcg_score=0.4, hits_count=1
    )

    # 'zero-trust' has high NDCG (0.9) and high hits
    evaluator.record_query_event(
        query="zero trust mesh", topic="zero-trust", ndcg_score=0.9, hits_count=15
    )

    telem = evaluator.evaluate_telemetry(telemetry_id="telem_01")
    assert telem.ndcg_at_k == pytest.approx(0.5, 0.05)
    assert "quantum factoring algorithm" in telem.zero_hit_queries
    assert telem.frequent_topics["quantum"] == 2
    assert telem.frequent_topics["zero-trust"] == 1

    # Quantum gap should be significantly higher than zero-trust gap
    assert telem.knowledge_gaps["quantum"] > telem.knowledge_gaps["zero-trust"]


def test_feedback_evaluator_phase_execution_and_compensation() -> None:
    evaluator = FeedbackEvaluator()
    ctx = PhaseContext(cycle_id="c_fb", workspace_dir="/tmp")
    ctx = evaluator.execute(ctx)
    assert ctx.phase_statuses[IntelligencePhase.EVALUATION] == PhaseStatus.COMPLETED
    assert ctx.telemetry is not None

    evaluator.compensate(ctx)
    assert ctx.phase_statuses[IntelligencePhase.EVALUATION] == PhaseStatus.COMPENSATED
    assert ctx.telemetry is None
