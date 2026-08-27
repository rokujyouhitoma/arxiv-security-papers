"""Test suite for Event Sourcing Write-Ahead Log (WAL) & Crash Recovery Engine."""

import os

from orchestrator.cli import main
from orchestrator.contracts import (
    IntelligenceDirective,
    IntelligencePhase,
    PhaseContext,
    PhaseStatus,
)
from orchestrator.engine import UniversalIntelligenceOrchestrator
from orchestrator.wal import EventType, OrchestratorWAL


def test_wal_append_and_read_events(tmp_path) -> None:
    wal = OrchestratorWAL(wal_dir=str(tmp_path / "wal"))
    cid = "cycle_test_01"

    ev1 = wal.append_event(cid, EventType.CYCLE_STARTED, {"topics": ["cryptography"]})
    ev2 = wal.append_event(cid, EventType.PHASE_STARTED, {"phase": "planning"})
    ev3 = wal.append_event(cid, EventType.PHASE_COMPLETED, {"phase": "planning"})

    events = wal.read_events(cid)
    assert len(events) == 3
    assert events[0].event_type == EventType.CYCLE_STARTED
    assert events[1].event_type == EventType.PHASE_STARTED
    assert events[2].event_type == EventType.PHASE_COMPLETED
    assert events[0].event_id == ev1.event_id
    assert events[1].event_id == ev2.event_id
    assert events[2].event_id == ev3.event_id


def test_wal_create_checkpoint_and_restore(tmp_path) -> None:
    wal = OrchestratorWAL(wal_dir=str(tmp_path / "wal"))
    cid = "cycle_test_02"

    ctx = PhaseContext(cycle_id=cid, workspace_dir=str(tmp_path))
    ctx.phase_statuses[IntelligencePhase.PLANNING] = PhaseStatus.COMPLETED
    ctx.directive = IntelligenceDirective(
        directive_id="dir_01",
        target_topics=["zero-trust"],
        topic_weights={"zero-trust": 1.0},
        crawl_quotas={"zero-trust": 10},
    )
    ctx.raw_records = [{"id": "rec_01", "title": "Zero Trust Paper"}]

    cp_path = wal.create_checkpoint(ctx)
    assert os.path.isfile(cp_path)

    replayed_ctx = wal.replay_cycle(cid, workspace_dir=str(tmp_path))
    assert replayed_ctx is not None
    assert replayed_ctx.cycle_id == cid
    assert (
        replayed_ctx.phase_statuses[IntelligencePhase.PLANNING] == PhaseStatus.COMPLETED
    )
    assert replayed_ctx.directive is not None
    assert replayed_ctx.directive.directive_id == "dir_01"
    assert len(replayed_ctx.raw_records) == 1


def test_wal_state_replay_with_events(tmp_path) -> None:
    wal = OrchestratorWAL(wal_dir=str(tmp_path / "wal"))
    cid = "cycle_test_03"

    wal.append_event(cid, EventType.CYCLE_STARTED)
    wal.append_event(cid, EventType.PHASE_STARTED, {"phase": "planning"})
    wal.append_event(cid, EventType.PHASE_COMPLETED, {"phase": "planning"})
    wal.append_event(
        cid, EventType.RECORD_HARVESTED, {"records": [{"id": "r1"}, {"id": "r2"}]}
    )
    wal.append_event(
        cid, EventType.RECORD_PROCESSED, {"records": [{"id": "r1", "clean": True}]}
    )

    replayed = wal.replay_cycle(cid, workspace_dir=str(tmp_path))
    assert replayed is not None
    assert replayed.phase_statuses[IntelligencePhase.PLANNING] == PhaseStatus.COMPLETED
    assert len(replayed.raw_records) == 2
    assert len(replayed.processed_records) == 1


def test_orchestrator_run_cycle_creates_wal_and_checkpoints(tmp_path) -> None:
    orch = UniversalIntelligenceOrchestrator(workspace_dir=str(tmp_path))
    ctx = orch.run_cycle(cycle_id="cycle_wal_full")

    assert ctx.phase_statuses[IntelligencePhase.EVALUATION] == PhaseStatus.COMPLETED

    wal_events = orch.wal.read_events("cycle_wal_full")
    assert (
        len(wal_events) >= 12
    )  # started + completed for all 6 phases + cycle started/completed + checkpoints

    event_types = [e.event_type for e in wal_events]
    assert EventType.CYCLE_STARTED in event_types
    assert EventType.CYCLE_COMPLETED in event_types
    assert EventType.CHECKPOINT_CREATED in event_types


def test_orchestrator_crash_and_resume_recovery(tmp_path) -> None:
    orch = UniversalIntelligenceOrchestrator(workspace_dir=str(tmp_path))
    cid = "crashed_cycle_01"

    # Simulate partial execution (only Planning & Collection completed before crash)
    ctx = PhaseContext(cycle_id=cid, workspace_dir=str(tmp_path))
    ctx = orch.pir_manager.execute(ctx)
    orch.wal.append_event(cid, EventType.CYCLE_STARTED)
    orch.wal.append_event(cid, EventType.PHASE_STARTED, {"phase": "planning"})
    orch.wal.append_event(cid, EventType.PHASE_COMPLETED, {"phase": "planning"})

    ctx = orch.harvest_coordinator.execute(ctx)
    orch.wal.append_event(cid, EventType.PHASE_STARTED, {"phase": "collection"})
    orch.wal.append_event(cid, EventType.PHASE_COMPLETED, {"phase": "collection"})
    orch.wal.create_checkpoint(ctx)

    # State is interrupted after Collection (Processing, Analysis, Dissemination, Evaluation pending)
    assert ctx.phase_statuses[IntelligencePhase.COLLECTION] == PhaseStatus.COMPLETED
    assert IntelligencePhase.PROCESSING not in ctx.phase_statuses

    # Resume cycle via Orchestrator WAL
    resumed_ctx = orch.resume_cycle(cid)

    # Verify all remaining phases completed successfully
    assert (
        resumed_ctx.phase_statuses[IntelligencePhase.PROCESSING]
        == PhaseStatus.COMPLETED
    )
    assert (
        resumed_ctx.phase_statuses[IntelligencePhase.ANALYSIS] == PhaseStatus.COMPLETED
    )
    assert (
        resumed_ctx.phase_statuses[IntelligencePhase.DISSEMINATION]
        == PhaseStatus.COMPLETED
    )
    assert (
        resumed_ctx.phase_statuses[IntelligencePhase.EVALUATION]
        == PhaseStatus.COMPLETED
    )
    assert len(resumed_ctx.processed_records) > 0


def test_wal_list_and_purge_active_cycles(tmp_path) -> None:
    wal = OrchestratorWAL(wal_dir=str(tmp_path / "wal"))
    wal.append_event("c1", EventType.CYCLE_STARTED)
    wal.append_event("c1", EventType.CYCLE_COMPLETED)

    wal.append_event("c2", EventType.CYCLE_STARTED)
    wal.append_event("c2", EventType.PHASE_STARTED, {"phase": "planning"})

    active = wal.list_active_cycles()
    assert len(active) == 2
    c1_stat = next(c for c in active if c["cycle_id"] == "c1")
    c2_stat = next(c for c in active if c["cycle_id"] == "c2")

    assert c1_stat["status"] == "completed"
    assert c2_stat["status"] == "in_progress"

    wal.purge_cycle_wal("c1")
    assert len(wal.read_events("c1")) == 0


def test_cli_recover_commands(tmp_path, capsys) -> None:
    # 1. Run a cycle to create WAL
    orch = UniversalIntelligenceOrchestrator(workspace_dir=str(tmp_path))
    orch.run_cycle(cycle_id="cli_rec_01")

    # 2. Test recover --list
    code_list = main(["--workdir", str(tmp_path), "recover", "--list"])
    assert code_list == 0
    captured_list = capsys.readouterr()
    assert "cli_rec_01" in captured_list.out

    # 3. Test recover --cycle-id
    code_rec = main(["--workdir", str(tmp_path), "recover", "--cycle-id", "cli_rec_01"])
    assert code_rec == 0
    captured_rec = capsys.readouterr()
    assert "Recovery complete!" in captured_rec.out
