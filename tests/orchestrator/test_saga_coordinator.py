"""Tests for SagaCoordinator reverse compensation rollback."""

from orchestrator.contracts import (
    IntelligencePhase,
    IntelligencePhaseProtocol,
    PhaseContext,
)
from orchestrator.workflow.saga import SagaCoordinator


class MockPhase(IntelligencePhaseProtocol):

    def __init__(self, p_type: IntelligencePhase, fail: bool = False) -> None:
        self._p_type = p_type
        self.fail = fail
        self.executed = False
        self.compensated = False

    @property
    def phase_type(self) -> IntelligencePhase:
        return self._p_type

    def execute(self, context: PhaseContext) -> PhaseContext:
        if self.fail:
            raise RuntimeError(f"Error in {self._p_type.value}")
        self.executed = True
        return context

    def compensate(self, context: PhaseContext) -> None:
        self.compensated = True


def test_saga_coordinator_success_flow() -> None:
    saga = SagaCoordinator()
    p1 = MockPhase(IntelligencePhase.PLANNING)
    p2 = MockPhase(IntelligencePhase.COLLECTION)

    ctx = PhaseContext(cycle_id="c_saga_ok", workspace_dir="/tmp")
    ctx = saga.execute_phase_safely(p1, ctx)
    ctx = saga.execute_phase_safely(p2, ctx)

    assert p1.executed is True
    assert p2.executed is True
    assert p1.compensated is False
    assert p2.compensated is False
    assert len(ctx.errors) == 0


def test_saga_coordinator_reverse_compensation_on_failure() -> None:
    saga = SagaCoordinator()
    p1 = MockPhase(IntelligencePhase.PLANNING)
    p2 = MockPhase(IntelligencePhase.COLLECTION)
    p3 = MockPhase(IntelligencePhase.PROCESSING, fail=True)

    ctx = PhaseContext(cycle_id="c_saga_fail", workspace_dir="/tmp")
    ctx = saga.execute_phase_safely(p1, ctx)
    ctx = saga.execute_phase_safely(p2, ctx)
    ctx = saga.execute_phase_safely(p3, ctx)

    assert p1.executed is True
    assert p2.executed is True
    assert p3.executed is False

    # p1 and p2 must be compensated in reverse order
    assert p2.compensated is True
    assert p1.compensated is True
    assert len(ctx.errors) == 1
    assert "Error in processing" in ctx.errors[0]["error"]
