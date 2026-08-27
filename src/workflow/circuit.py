"""Circuit Breaker Pattern implementation for fault-tolerant workflow routing."""

import time
from enum import Enum
from typing import Optional


class CircuitState(str, Enum):
    """Operational state of a route circuit breaker."""

    CLOSED = "closed"  # Normal healthy operation
    OPEN = "open"  # Fault detected, traffic deflected to fallbacks
    HALF_OPEN = "half_open"  # Probing recovery with limited traffic


class CircuitBreaker:
    """Monitors failures and controls traffic gating for a specific execution route."""

    def __init__(
        self,
        failure_threshold: int = 3,
        cooldown_seconds: float = 30.0,
    ) -> None:
        self.failure_threshold = max(1, failure_threshold)
        self.cooldown_seconds = cooldown_seconds
        self.state = CircuitState.CLOSED
        self.consecutive_failures: int = 0
        self.last_failure_time: float = 0.0

    def can_execute(self, current_time: Optional[float] = None) -> bool:
        """Determines if the route can accept execution attempts."""
        now = current_time if current_time is not None else time.time()
        if self.state == CircuitState.CLOSED:
            return True
        elif self.state == CircuitState.OPEN:
            if now - self.last_failure_time >= self.cooldown_seconds:
                self.state = CircuitState.HALF_OPEN
                return True
            return False
        elif self.state == CircuitState.HALF_OPEN:
            return True
        return False

    def record_success(self) -> None:
        """Records a successful execution and restores CLOSED state."""
        self.consecutive_failures = 0
        self.state = CircuitState.CLOSED

    def record_failure(self, current_time: Optional[float] = None) -> None:
        """Records a failed attempt and trips circuit to OPEN if threshold reached."""
        now = current_time if current_time is not None else time.time()
        self.consecutive_failures += 1
        self.last_failure_time = now
        if (
            self.consecutive_failures >= self.failure_threshold
            or self.state == CircuitState.HALF_OPEN
        ):
            self.state = CircuitState.OPEN
