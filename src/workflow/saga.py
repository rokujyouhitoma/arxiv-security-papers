"""Saga Transaction Coordinator with Reverse Compensation."""

from dataclasses import dataclass
from typing import Any, List, Protocol, runtime_checkable


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


class SagaCoordinator:
    """Orchestrates multi-phase forward execution and reverse compensation."""

    def __init__(self) -> None:
        self.executed_steps: List[SagaStep] = []

    def _get_step_name(self, phase_executor: PhaseProtocol) -> str:
        step_name = getattr(
            phase_executor, "phase_type", phase_executor.__class__.__name__
        )
        return str(step_name.value) if hasattr(step_name, "value") else str(step_name)

    def _record_execution_error(
        self, context: Any, step_name: str, exc: Exception
    ) -> None:
        if hasattr(context, "errors") and isinstance(context.errors, list):
            context.errors.append({"step": step_name, "error": str(exc)})
        self.compensate_all(context)

    def execute_phase_safely(self, phase_executor: PhaseProtocol, context: Any) -> Any:
        """Executes a single phase, recording it for compensation if failures occur."""
        step_name = self._get_step_name(phase_executor)
        try:
            context = phase_executor.execute(context)
            self.executed_steps.append(
                SagaStep(step_name=step_name, phase_executor=phase_executor)
            )
            if getattr(context, "errors", None):
                self.compensate_all(context)
            return context
        except Exception as e:
            self._record_execution_error(context, step_name, e)
            return context

    def compensate_all(self, context: Any) -> None:
        """Executes reverse compensation in LIFO order across all completed steps."""
        while self.executed_steps:
            step = self.executed_steps.pop()
            try:
                step.phase_executor.compensate(context)
            except Exception as e:
                if hasattr(context, "errors") and isinstance(context.errors, list):
                    context.errors.append(
                        {
                            "step": step.step_name,
                            "compensation_error": str(e),
                        }
                    )
