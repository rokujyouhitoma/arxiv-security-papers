"""Unit tests for Event Sourcing WAL & Crash Recovery Engine."""

from intelligence.contracts import (
    IntelligenceDirective,
    IntelligencePhase,
    PhaseContext,
    PhaseStatus,
)
from workflow.wal import EventType, OrchestratorWAL


def test_wal_append_and_read_events(tmp_path) -> None:
    wal = OrchestratorWAL(wal_dir=str(tmp_path / "wal"))
    cid = "cycle_test_wf_01"

    ev1 = wal.append_event(cid, EventType.CYCLE_STARTED, {"topics": ["cryptography"]})
    ev2 = wal.append_event(cid, EventType.PHASE_STARTED, {"phase": "planning"})

    events = wal.read_events(cid)
    assert len(events) == 2
    assert events[0].event_type == EventType.CYCLE_STARTED
    assert events[1].event_type == EventType.PHASE_STARTED
    assert events[0].event_id == ev1.event_id
    assert events[1].event_id == ev2.event_id


def test_wal_checkpoint_and_replay(tmp_path) -> None:
    wal = OrchestratorWAL(wal_dir=str(tmp_path / "wal"))
    cid = "cycle_test_wf_02"

    ctx = PhaseContext(cycle_id=cid, workspace_dir=str(tmp_path))
    ctx.phase_statuses[IntelligencePhase.PLANNING] = PhaseStatus.COMPLETED
    ctx.directive = IntelligenceDirective(
        directive_id="dir_01",
        target_topics=["zero-trust"],
        topic_weights={"zero-trust": 1.0},
        crawl_quotas={"zero-trust": 5},
    )

    wal.create_checkpoint(ctx)
    replayed = wal.replay_cycle(cid, workspace_dir=str(tmp_path))

    assert replayed is not None
    assert replayed.cycle_id == cid
    assert replayed.phase_statuses[IntelligencePhase.PLANNING] == PhaseStatus.COMPLETED
    assert replayed.directive is not None
    assert replayed.directive.directive_id == "dir_01"
