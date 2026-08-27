"""Unit tests for Workflow Circuit Breaker State Machine."""

from workflow.circuit import CircuitBreaker, CircuitState


def test_circuit_breaker_initial_state() -> None:
    cb = CircuitBreaker(failure_threshold=3, cooldown_seconds=10.0)
    assert cb.state == CircuitState.CLOSED
    assert cb.can_execute(current_time=0.0) is True


def test_circuit_breaker_trips_to_open() -> None:
    cb = CircuitBreaker(failure_threshold=2, cooldown_seconds=10.0)
    cb.record_failure(current_time=1.0)
    assert cb.state == CircuitState.CLOSED

    cb.record_failure(current_time=2.0)
    assert cb.state == CircuitState.OPEN
    assert cb.can_execute(current_time=5.0) is False


def test_circuit_breaker_half_open_recovery() -> None:
    cb = CircuitBreaker(failure_threshold=1, cooldown_seconds=10.0)
    cb.record_failure(current_time=1.0)
    assert cb.state == CircuitState.OPEN

    # After cooldown -> HALF_OPEN
    assert cb.can_execute(current_time=12.0) is True
    assert cb.state == CircuitState.HALF_OPEN

    # Success -> CLOSED
    cb.record_success()
    assert cb.state == CircuitState.CLOSED
    assert cb.consecutive_failures == 0
