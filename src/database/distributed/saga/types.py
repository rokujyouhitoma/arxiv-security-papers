#!/usr/bin/env python3
"""
Saga Distributed Transaction Types and Step Definitions.
Defines execution status and callable step wrappers.
"""

import enum
from typing import Any, Callable, Dict, Optional


class SagaStatus(enum.Enum):
    """Lifecycle status of a Saga transaction."""

    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    COMPENSATING = "COMPENSATING"
    COMPENSATED = "COMPENSATED"
    FAILED = "FAILED"


class SagaStep:
    """
    A single forward action (T_i) and its corresponding compensating action (C_i).
    """

    def __init__(
        self,
        name: str,
        action: Callable[[Dict[str, Any]], Dict[str, Any]],
        compensate: Optional[Callable[[Dict[str, Any]], None]] = None,
    ) -> None:
        self.name = name
        self.action = action
        self.compensate = compensate

    def __repr__(self) -> str:
        has_comp = self.compensate is not None
        return f"SagaStep(name={self.name!r}, has_compensate={has_comp})"
