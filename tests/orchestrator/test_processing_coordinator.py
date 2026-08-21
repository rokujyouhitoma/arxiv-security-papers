"""Tests for Phase 3 ProcessingCoordinator."""

from orchestrator.contracts import IntelligencePhase, PhaseContext, PhaseStatus
from orchestrator.processing.processor import ProcessingCoordinator


def test_processing_coordinator_okf_transformation() -> None:
    proc = ProcessingCoordinator()
    raw = {
        "id": "2608.12345",
        "title": "Zero Trust Cloud Authentication and Security",
        "topic": "cloud",
        "raw_text": "Detailed analysis of microservice zero trust models.",
        "source": "arxiv",
    }
    res = proc.process_record(raw)
    assert res["id"] == "2608.12345"
    assert "cloud" in res["tags"]
    assert "zero-trust" in res["tags"]
    assert "security" in res["tags"]
    assert 'type: "intelligence-document"' in res["okf_content"]


def test_processing_coordinator_phase_execution() -> None:
    proc = ProcessingCoordinator()
    ctx = PhaseContext(
        cycle_id="c_proc",
        workspace_dir="/tmp",
        raw_records=[
            {"id": "r1", "title": "Doc 1", "topic": "t1", "raw_text": "Text 1"},
            {"id": "r2", "title": "Doc 2", "topic": "t2", "raw_text": "Text 2"},
        ],
    )
    ctx = proc.execute(ctx)
    assert ctx.phase_statuses[IntelligencePhase.PROCESSING] == PhaseStatus.COMPLETED
    assert len(ctx.processed_records) == 2


def test_processing_coordinator_compensation() -> None:
    proc = ProcessingCoordinator()
    ctx = PhaseContext(
        cycle_id="c_comp",
        workspace_dir="/tmp",
        processed_records=[{"id": "p1"}],
    )
    proc.compensate(ctx)
    assert ctx.phase_statuses[IntelligencePhase.PROCESSING] == PhaseStatus.COMPENSATED
    assert len(ctx.processed_records) == 0
