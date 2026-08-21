"""Tests for Phase 2 HarvestCoordinator."""

from orchestrator.contracts import (
    IntelligenceDirective,
    IntelligencePhase,
    PhaseContext,
    PhaseStatus,
)
from orchestrator.harvest.coordinator import HarvestCoordinator


def test_harvest_coordinator_standalone_fallback() -> None:
    coord = HarvestCoordinator()
    directive = IntelligenceDirective(
        directive_id="dir_test",
        target_topics=["topic_x", "topic_y"],
        topic_weights={"topic_x": 0.5, "topic_y": 0.5},
        crawl_quotas={"topic_x": 3, "topic_y": 2},
    )
    ctx = PhaseContext(cycle_id="c_1", workspace_dir="/tmp", directive=directive)

    ctx = coord.execute(ctx)
    assert ctx.phase_statuses[IntelligencePhase.COLLECTION] == PhaseStatus.COMPLETED
    assert len(ctx.raw_records) == 5  # 3 for topic_x + 2 for topic_y


def test_harvest_coordinator_custom_harvester() -> None:
    coord = HarvestCoordinator()

    def mock_harvester(topic: str, quota: int) -> list:
        return [
            {"id": f"custom_{topic}_{i}", "title": f"Custom {topic}", "topic": topic}
            for i in range(quota)
        ]

    coord.register_harvester("mock_src", mock_harvester)

    directive = IntelligenceDirective(
        directive_id="dir_cust",
        target_topics=["ai_safety"],
        topic_weights={"ai_safety": 1.0},
        crawl_quotas={"ai_safety": 4},
    )
    ctx = PhaseContext(cycle_id="c_2", workspace_dir="/tmp", directive=directive)

    ctx = coord.execute(ctx)
    assert ctx.phase_statuses[IntelligencePhase.COLLECTION] == PhaseStatus.COMPLETED
    assert len(ctx.raw_records) == 4
    assert ctx.raw_records[0]["id"] == "custom_ai_safety_0"


def test_harvest_coordinator_missing_directive_error() -> None:
    coord = HarvestCoordinator()
    ctx = PhaseContext(cycle_id="c_err", workspace_dir="/tmp", directive=None)
    ctx = coord.execute(ctx)
    assert ctx.phase_statuses[IntelligencePhase.COLLECTION] == PhaseStatus.FAILED
    assert len(ctx.errors) == 1


def test_harvest_coordinator_compensation() -> None:
    coord = HarvestCoordinator()
    ctx = PhaseContext(
        cycle_id="c_comp",
        workspace_dir="/tmp",
        raw_records=[{"id": "rec_1"}],
    )
    coord.compensate(ctx)
    assert ctx.phase_statuses[IntelligencePhase.COLLECTION] == PhaseStatus.COMPENSATED
    assert len(ctx.raw_records) == 0
