#!/usr/bin/env python3
"""
Circuit Breaker Module for Fail-Fast & Cascade Failure Prevention.
Maintains CLOSED, OPEN, and HALF_OPEN states to gracefully handle upstream outages
and rate limit rejections (e.g. arXiv API HTTP 429).
Zero external runtime dependencies.
"""

import threading
import time
from enum import Enum
from typing import Any, Callable, Literal, Optional, TypeVar

T = TypeVar("T")


class CircuitState(str, Enum):
    """Lifecycle states of the Circuit Breaker."""

    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


class CircuitBreakerOpenError(RuntimeError):
    """Raised when an operation is rejected immediately because the circuit is OPEN."""

    pass


class CircuitBreaker:
    """
    Thread-safe three-state Circuit Breaker.
    Transitions to OPEN after failure_threshold consecutive errors.
    Transitions to HALF_OPEN after recovery_timeout seconds.
    Recovers to CLOSED after half_open_success_threshold successful probes.
    """

    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 30.0,
        half_open_success_threshold: int = 2,
    ) -> None:
        if (
            failure_threshold <= 0
            or recovery_timeout <= 0
            or half_open_success_threshold <= 0
        ):
            raise ValueError("Thresholds and timeout must be positive")
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.half_open_success_threshold = half_open_success_threshold

        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._success_count = 0
        self._last_failure_time = 0.0
        self._lock = threading.Lock()

    @property
    def state(self) -> CircuitState:
        """Returns the current state, evaluating automatic OPEN -> HALF_OPEN transitions."""
        with self._lock:
            self._evaluate_recovery_timeout(time.monotonic())
            return self._state

    def _evaluate_recovery_timeout(self, now: float) -> None:
        """Transitions from OPEN to HALF_OPEN if recovery timeout has elapsed."""
        if self._state == CircuitState.OPEN:
            if now - self._last_failure_time >= self.recovery_timeout:
                self._state = CircuitState.HALF_OPEN
                self._success_count = 0

    def record_success(self) -> None:
        """Records a successful operation, potentially closing a HALF_OPEN circuit."""
        with self._lock:
            if self._state == CircuitState.HALF_OPEN:
                self._success_count += 1
                if self._success_count >= self.half_open_success_threshold:
                    self._state = CircuitState.CLOSED
                    self._failure_count = 0
                    self._success_count = 0
            elif self._state == CircuitState.CLOSED:
                self._failure_count = 0

    def record_failure(self) -> None:
        """Records a failed operation, potentially opening the circuit."""
        with self._lock:
            now = time.monotonic()
            self._last_failure_time = now
            if self._state == CircuitState.HALF_OPEN:
                self._state = CircuitState.OPEN
            elif self._state == CircuitState.CLOSED:
                self._failure_count += 1
                if self._failure_count >= self.failure_threshold:
                    self._state = CircuitState.OPEN

    def call(self, func: Callable[..., T], *args: Any, **kwargs: Any) -> T:
        """Executes func wrapped by the circuit breaker logic."""
        with self:
            return func(*args, **kwargs)

    def __enter__(self) -> "CircuitBreaker":
        """Checks circuit state upon entry, raising CircuitBreakerOpenError if OPEN."""
        with self._lock:
            self._evaluate_recovery_timeout(time.monotonic())
            if self._state == CircuitState.OPEN:
                raise CircuitBreakerOpenError(
                    f"Circuit breaker is OPEN (recovery timeout: {self.recovery_timeout}s)"
                )
        return self

    def __exit__(
        self,
        exc_type: Optional[type[BaseException]],
        exc_val: Optional[BaseException],
        exc_tb: Optional[Any],
    ) -> Literal[False]:
        """Records success if no unhandled exception occurred, or failure otherwise."""
        if exc_type is not None:
            if not issubclass(exc_type, CircuitBreakerOpenError):
                self.record_failure()
            return False

        self.record_success()
        return False
