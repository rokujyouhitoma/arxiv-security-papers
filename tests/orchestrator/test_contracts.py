"""Tests for orchestrator contracts and data structures."""

from orchestrator.contracts import (
    FeedbackTelemetry,
    IntelligenceDirective,
    IntelligencePhase,
    IntelligenceProduct,
    PhaseContext,
    PhaseStatus,
)


def test_intelligence_phase_enums() -> None:
    assert IntelligencePhase.PLANNING.value == "planning"
    assert IntelligencePhase.COLLECTION.value == "collection"
    assert IntelligencePhase.PROCESSING.value == "processing"
    assert IntelligencePhase.ANALYSIS.value == "analysis"
    assert IntelligencePhase.DISSEMINATION.value == "dissemination"
    assert IntelligencePhase.EVALUATION.value == "evaluation"

    assert PhaseStatus.PENDING.value == "pending"
    assert PhaseStatus.RUNNING.value == "running"
    assert PhaseStatus.COMPLETED.value == "completed"
    assert PhaseStatus.FAILED.value == "failed"
    assert PhaseStatus.COMPENSATED.value == "compensated"


def test_phase_context_initialization() -> None:
    ctx = PhaseContext(cycle_id="test_001", workspace_dir="/tmp/test")
    assert ctx.cycle_id == "test_001"
    assert ctx.workspace_dir == "/tmp/test"
    assert len(ctx.phase_statuses) == 0
    assert ctx.directive is None
    assert len(ctx.raw_records) == 0
    assert len(ctx.processed_records) == 0
    assert len(ctx.products) == 0
    assert ctx.telemetry is None
    assert len(ctx.errors) == 0


def test_intelligence_directive_dataclass() -> None:
    directive = IntelligenceDirective(
        directive_id="dir_1",
        target_topics=["cryptography", "zero-trust"],
        topic_weights={"cryptography": 0.6, "zero-trust": 0.4},
        crawl_quotas={"cryptography": 30, "zero-trust": 20},
    )
    assert directive.directive_id == "dir_1"
    assert len(directive.target_topics) == 2
    assert directive.priority_level == 1
    assert directive.created_at is not None


def test_intelligence_product_dataclass() -> None:
    prod = IntelligenceProduct(
        product_id="prod_1",
        title="Zero Trust Security Synthesis",
        summary="Executive summary on zero trust.",
        tier="01_per_run",
        topic_tags=["zero-trust"],
        source_count=10,
        confidence_score=0.95,
        okf_references=["doc_1", "doc_2"],
    )
    assert prod.product_id == "prod_1"
    assert prod.confidence_score == 0.95
    assert len(prod.okf_references) == 2


def test_feedback_telemetry_dataclass() -> None:
    telem = FeedbackTelemetry(
        telemetry_id="telem_1",
        ndcg_at_k=0.92,
        mean_average_precision=0.88,
        zero_hit_queries=["unknown topic query"],
        frequent_topics={"cryptography": 15},
        topic_drift_scores={"cryptography": 0.5},
        knowledge_gaps={"quantum": 0.7},
    )
    assert telem.ndcg_at_k == 0.92
    assert len(telem.zero_hit_queries) == 1
    assert telem.knowledge_gaps["quantum"] == 0.7
