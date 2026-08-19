#!/usr/bin/env python3
"""
Orchestration-based Saga State Machine Implementation.
Coordinates forward step execution (T_i) and backward compensating actions (C_i).
"""

import logging
from typing import Any, Callable, Dict, List, Optional

from .types import SagaStatus, SagaStep

logger = logging.getLogger(__name__)


class SagaOrchestrator:
    """
    State machine orchestrator managing long-running distributed Saga workflows.
    """

    def __init__(self, saga_id: str) -> None:
        self.saga_id = saga_id
        self.steps: List[SagaStep] = []
        self.executed_steps: List[SagaStep] = []
        self.compensated_steps: List[str] = []
        self.context: Dict[str, Any] = {}
        self.status: SagaStatus = SagaStatus.PENDING
        self.error: Optional[str] = None

    def add_step(
        self,
        name: str,
        action: Callable[[Dict[str, Any]], Dict[str, Any]],
        compensate: Optional[Callable[[Dict[str, Any]], None]] = None,
    ) -> "SagaOrchestrator":
        """Appends a new step to the Saga pipeline."""
        self.steps.append(SagaStep(name=name, action=action, compensate=compensate))
        return self

    def _rollback(self) -> None:
        """Executes compensating actions in reverse order of execution."""
        self.status = SagaStatus.COMPENSATING
        for step in reversed(self.executed_steps):
            if step.compensate is not None:
                try:
                    step.compensate(self.context)
                    self.compensated_steps.append(step.name)
                except Exception as comp_err:
                    logger.error(
                        "Compensating action failed for step %s: %s",
                        step.name,
                        comp_err,
                    )
        self.status = SagaStatus.COMPENSATED

    def execute(self, initial_context: Optional[Dict[str, Any]] = None) -> bool:
        """
        Executes all Saga steps in order.
        Triggers backward compensation upon any step failure.
        """
        self.context = dict(initial_context or {})
        self.executed_steps.clear()
        self.compensated_steps.clear()
        self.status = SagaStatus.RUNNING
        self.error = None

        for step in self.steps:
            try:
                result = step.action(self.context)
                if isinstance(result, dict):
                    self.context.update(result)
                self.executed_steps.append(step)
            except Exception as err:
                self.error = str(err)
                self._rollback()
                return False

        self.status = SagaStatus.COMPLETED
        return True
