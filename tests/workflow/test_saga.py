"""Unit tests for Saga Transaction Coordinator."""

from dataclasses import dataclass, field
from typing import List

from workflow.saga import PhaseProtocol, SagaCoordinator


@dataclass
class MockContext:
    executed: List[str] = field(default_factory=list)
    compensated: List[str] = field(default_factory=list)
    errors: List[dict] = field(default_factory=list)


class MockSuccessStep(PhaseProtocol):
    def __init__(self, name: str) -> None:
        self.name = name

    def execute(self, ctx: MockContext) -> MockContext:
        ctx.executed.append(self.name)
        return ctx

    def compensate(self, ctx: MockContext) -> None:
        ctx.compensated.append(self.name)


class MockFailureStep(PhaseProtocol):
    def __init__(self, name: str) -> None:
        self.name = name

    def execute(self, ctx: MockContext) -> MockContext:
        ctx.errors.append({"step": self.name, "error": "Fatal Step Error"})
        return ctx

    def compensate(self, ctx: MockContext) -> None:
        ctx.compensated.append(self.name)


def test_saga_coordinator_success_flow() -> None:
    saga = SagaCoordinator()
    ctx = MockContext()

    ctx = saga.execute_phase_safely(MockSuccessStep("step1"), ctx)
    ctx = saga.execute_phase_safely(MockSuccessStep("step2"), ctx)

    assert ctx.executed == ["step1", "step2"]
    assert len(ctx.compensated) == 0
    assert len(ctx.errors) == 0


def test_saga_coordinator_reverse_compensation_on_failure() -> None:
    saga = SagaCoordinator()
    ctx = MockContext()

    ctx = saga.execute_phase_safely(MockSuccessStep("step1"), ctx)
    ctx = saga.execute_phase_safely(MockSuccessStep("step2"), ctx)
    ctx = saga.execute_phase_safely(MockFailureStep("step3"), ctx)

    assert ctx.executed == ["step1", "step2"]
    # Reverse order (LIFO): step3 -> step2 -> step1
    assert ctx.compensated == ["step3", "step2", "step1"]
    assert len(ctx.errors) == 1
