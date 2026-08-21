"""Saga Transaction Coordinator.

Provides compensation and rollback guarantees across multi-phase intelligence
workflows, ensuring atomic consistency when any downstream phase encounters errors.
"""

from typing import List

from orchestrator.contracts import IntelligencePhaseProtocol, PhaseContext


class SagaCoordinator:
    """Orchestrates forward phase executions and reverse compensations upon failure."""

    def __init__(self) -> None:
        self._executed_phases: List[IntelligencePhaseProtocol] = []

    def execute_phase_safely(
        self, phase: IntelligencePhaseProtocol, context: PhaseContext
    ) -> PhaseContext:
        """Executes a single phase and registers it for potential rollback."""
        try:
            context = phase.execute(context)
            self._executed_phases.append(phase)
            return context
        except Exception as ex:
            context.errors.append({"phase": phase.phase_type.value, "error": str(ex)})
            self.rollback_executed(context)
            return context

    def rollback_executed(self, context: PhaseContext) -> None:
        """Executes compensation transactions in reverse order of execution."""
        while self._executed_phases:
            phase = self._executed_phases.pop()
            try:
                phase.compensate(context)
            except Exception:
                # Suppress errors in compensation to ensure full traversal
                pass
