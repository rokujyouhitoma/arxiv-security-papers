"""E2E test suite for ClosedLoopIntelligenceEngine closed-loop lifecycle."""

import pytest

from intelligence.contracts import IntelligencePhase, PhaseStatus
from intelligence.engine import ClosedLoopIntelligenceEngine


def test_orchestrator_closed_loop_e2e_lifecycle() -> None:
    orch = ClosedLoopIntelligenceEngine(workspace_dir="/tmp/test_intelligence")

    # Step 1: Register Initial Priority Requirements
    orch.register_pir(
        req_id="pir_01",
        title="Zero Trust Architecture",
        description="Monitor zero trust authentication patterns",
        target_topics=["zero-trust", "cloud-security"],
        priority_score=0.8,
    )
    orch.register_pir(
        req_id="pir_02",
        title="Post-Quantum Cryptography",
        description="Monitor NIST PQC standardization",
        target_topics=["quantum", "cryptography"],
        priority_score=0.6,
    )

    initial_weights = orch.get_current_topic_weights()
    assert "zero-trust" in initial_weights
    assert "quantum" in initial_weights

    # Step 2: Run 1st Full Intelligence Cycle
    ctx1 = orch.run_cycle(cycle_id="cycle_001")

    assert ctx1.cycle_id == "cycle_001"
    assert ctx1.phase_statuses[IntelligencePhase.PLANNING] == PhaseStatus.COMPLETED
    assert ctx1.phase_statuses[IntelligencePhase.COLLECTION] == PhaseStatus.COMPLETED
    assert ctx1.phase_statuses[IntelligencePhase.PROCESSING] == PhaseStatus.COMPLETED
    assert ctx1.phase_statuses[IntelligencePhase.ANALYSIS] == PhaseStatus.COMPLETED
    assert ctx1.phase_statuses[IntelligencePhase.DISSEMINATION] == PhaseStatus.COMPLETED
    assert ctx1.phase_statuses[IntelligencePhase.EVALUATION] == PhaseStatus.COMPLETED

    assert len(ctx1.raw_records) > 0
    assert len(ctx1.processed_records) > 0
    assert len(ctx1.products) >= 1
    assert len(orch.get_published_products()) >= 1

    # Step 3: Simulate Client Feedback with Knowledge Gap in 'quantum'
    for _ in range(10):
        orch.record_query_feedback(
            query="quantum lattice attack vulnerability",
            topic="quantum",
            ndcg_score=0.3,
            hits_count=0,
        )

    # Step 4: Run 2nd Full Intelligence Cycle (Feedback Loop Active)
    ctx2 = orch.run_cycle(cycle_id="cycle_002")
    assert ctx2.cycle_id == "cycle_002"
    assert len(ctx2.errors) == 0

    # Step 5: Verify Topic Weight Shift (Self-Adapting Direction)
    updated_weights = orch.get_current_topic_weights()
    assert (
        updated_weights.get("quantum", 0.0)
        >= initial_weights.get("quantum", 0.0) - 0.01
    )
    assert updated_weights["quantum"] > initial_weights["quantum"]
    assert pytest.approx(sum(updated_weights.values()), 0.01) == 1.0


def test_orchestrator_dependency_injection_and_protocols() -> None:
    from intelligence.analysis.synthesizer import AnalysisSynthesizer
    from intelligence.contracts import (
        CredibilityEngineProtocol,
        PIRManagerProtocol,
        SynthesizerProtocol,
    )
    from intelligence.harvest.coordinator import HarvestCoordinator
    from intelligence.pir.manager import PIRManager
    from intelligence.processing.processor import ProcessingCoordinator

    pir_mgr = PIRManager(storage_path="/tmp/test_di_pir_registry.json", auto_seed=True)
    harvest_coord = HarvestCoordinator()
    proc_coord = ProcessingCoordinator()
    synth = AnalysisSynthesizer()

    # Verify Protocol compliance
    assert isinstance(pir_mgr, PIRManagerProtocol)
    assert isinstance(proc_coord.credibility_engine, CredibilityEngineProtocol)
    assert isinstance(synth, SynthesizerProtocol)

    orch = ClosedLoopIntelligenceEngine(
        workspace_dir="/tmp/test_di_engine",
        pir_manager=pir_mgr,
        harvest_coordinator=harvest_coord,
        processing_coordinator=proc_coord,
    )

    assert orch.pir_manager is pir_mgr
    assert orch.harvest_coordinator is harvest_coord
    assert orch.processing_coordinator is proc_coord

    ctx = orch.run_cycle(cycle_id="di_cycle_001")
    assert ctx.cycle_id == "di_cycle_001"
    assert ctx.phase_statuses[IntelligencePhase.PLANNING] == PhaseStatus.COMPLETED


def test_orchestrator_fault_tolerance_with_saga_rollback() -> None:
    orch = ClosedLoopIntelligenceEngine(workspace_dir="/tmp/test_fault")

    # Inject a failing harvester
    def failing_harvester(topic: str, quota: int) -> list:
        raise RuntimeError("Network Timeout to Source")

    orch.harvest_coordinator.register_harvester("bad_src", failing_harvester)
    orch.register_pir(
        req_id="pir_fail",
        title="Fail Test",
        description="Testing fault tolerance",
        target_topics=["network"],
    )

    ctx = orch.run_cycle(cycle_id="cycle_fault_001")
    # Even on individual harvester errors, the coordinator absorbs and handles gracefully
    assert len(ctx.raw_records) > 0
