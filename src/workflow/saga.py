"""Saga Transaction Coordinator with Reverse Compensation and HSM Governance."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, List, Protocol, runtime_checkable

from core.hsm import HierarchicalStateMachine

from .contracts import (
    EVENT_ABORT,
    EVENT_COMMIT_ALL,
    EVENT_COMPENSATE,
    EVENT_EXECUTE,
    EVENT_ROLLBACK_DONE,
    EVENT_ROLLBACK_FAIL,
    EVENT_STEP_OK,
    build_saga_state_tree,
)


@runtime_checkable
class PhaseProtocol(Protocol):
    """Protocol for transactional workflow steps supporting compensation."""

    def execute(self, context: Any) -> Any:
        """Executes forward step action."""
        ...

    def compensate(self, context: Any) -> None:
        """Rolls back step effects upon downstream failure."""
        ...


@dataclass
class SagaStep:
    """Execution step registered in the Saga transaction log."""

    step_name: str
    phase_executor: PhaseProtocol


def _context_has_errors(context: Any) -> bool:
    """Checks whether execution context contains errors (dict or object)."""
    if isinstance(context, dict):
        return bool(context.get("errors"))
    return bool(getattr(context, "errors", None))


def _append_error_record(context: Any, record: dict[str, str]) -> None:
    """Appends an error record to context errors list if present."""
    if isinstance(context, dict):
        context.setdefault("errors", []).append(record)
    elif hasattr(context, "errors") and isinstance(context.errors, list):
        context.errors.append(record)


class SagaCoordinator:
    """Orchestrates multi-phase forward execution and reverse compensation with HSM."""

    def __init__(self) -> None:
        self.executed_steps: List[SagaStep] = []
        self.hsm: HierarchicalStateMachine = build_saga_state_tree()

    def _get_step_name(self, phase_executor: PhaseProtocol) -> str:
        step_name = getattr(
            phase_executor, "phase_type", phase_executor.__class__.__name__
        )
        return str(step_name.value) if hasattr(step_name, "value") else str(step_name)

    def _record_execution_error(
        self, context: Any, step_name: str, exc: Exception
    ) -> None:
        _append_error_record(context, {"step": step_name, "error": str(exc)})
        self.compensate_all(context)

    def execute_phase_safely(self, phase_executor: PhaseProtocol, context: Any) -> Any:
        """Executes a single phase, recording it for compensation if failures occur."""
        step_name = self._get_step_name(phase_executor)
        self.hsm.send_event(EVENT_EXECUTE, {"step": step_name})
        try:
            context = phase_executor.execute(context)
            self.executed_steps.append(
                SagaStep(step_name=step_name, phase_executor=phase_executor)
            )
            self.hsm.send_event(EVENT_STEP_OK, {"step": step_name})
            if _context_has_errors(context):
                self.compensate_all(context)
            return context
        except Exception as exc:
            self._record_execution_error(context, step_name, exc)
            return context

    def _compensate_single_step(self, step: SagaStep, context: Any) -> bool:
        """Compensates a single step, returning True if successful."""
        try:
            step.phase_executor.compensate(context)
            return True
        except Exception as exc:
            _append_error_record(
                context,
                {"step": step.step_name, "compensation_error": str(exc)},
            )
            return False

    def _finalize_compensation(self, has_failures: bool) -> None:
        """Transitions HSM state based on compensation outcome."""
        if has_failures:
            self.hsm.send_event(EVENT_ROLLBACK_FAIL)
        else:
            self.hsm.send_event(EVENT_ROLLBACK_DONE)
        self.hsm.send_event(EVENT_ABORT)

    def compensate_all(self, context: Any) -> None:
        """Executes reverse compensation in LIFO order across all completed steps."""
        self.hsm.send_event(
            EVENT_COMPENSATE, {"remaining_steps": len(self.executed_steps)}
        )
        has_failures = False
        while self.executed_steps:
            step = self.executed_steps.pop()
            if not self._compensate_single_step(step, context):
                has_failures = True
        self._finalize_compensation(has_failures)

    def commit_all(self) -> None:
        """Marks the entire Saga transaction as committed."""
        self.hsm.send_event(EVENT_COMMIT_ALL)
