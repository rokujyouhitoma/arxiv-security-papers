#!/usr/bin/env python3
"""
Unit tests for Rate Limiting and Circuit Breaker DoS Protection.
"""

import time

import pytest

from src.security.ratelimit.circuit_breaker import (
    CircuitBreaker,
    CircuitBreakerOpenError,
    CircuitState,
)
from src.security.ratelimit.limiter import (
    RateLimitExceededError,
    SlidingWindowRateLimiter,
    TokenBucketRateLimiter,
)


def test_rate_limit_exceeded_error() -> None:
    """Tests RateLimitExceededError inheritance."""
    err = RateLimitExceededError("Too many requests")
    assert isinstance(err, ValueError)


def test_token_bucket_acquisition_and_depletion() -> None:
    """Tests acquiring tokens until bucket capacity is exhausted."""
    limiter = TokenBucketRateLimiter(capacity=3.0, fill_rate=1.0)
    assert limiter.acquire(1.0)
    assert limiter.acquire(2.0)
    # Depleted
    assert not limiter.acquire(1.0)
    assert limiter.current_tokens < 1.0


def test_token_bucket_refill_and_wait() -> None:
    """Tests token replenishment over time and wait_and_acquire."""
    limiter = TokenBucketRateLimiter(capacity=2.0, fill_rate=10.0)  # 10 tokens/sec
    assert limiter.acquire(2.0)
    assert not limiter.acquire(1.0)

    # Blocks briefly and acquires
    assert limiter.wait_and_acquire(1.0, timeout=0.5)


def test_token_bucket_invalid_params() -> None:
    """Tests rejection of invalid capacity or fill_rate."""
    with pytest.raises(ValueError, match="must be positive"):
        TokenBucketRateLimiter(capacity=-1.0, fill_rate=1.0)
    with pytest.raises(ValueError, match="must be positive"):
        TokenBucketRateLimiter(capacity=1.0, fill_rate=0.0)


def test_sliding_window_rate_limiter() -> None:
    """Tests rolling window limits per distinct key."""
    limiter = SlidingWindowRateLimiter()
    # Allow 2 requests per 60 seconds
    assert limiter.acquire("user_1", max_requests=2, window_seconds=60.0)
    assert limiter.acquire("user_1", max_requests=2, window_seconds=60.0)
    # 3rd request blocked
    assert not limiter.acquire("user_1", max_requests=2, window_seconds=60.0)
    assert not limiter.is_allowed("user_1", max_requests=2, window_seconds=60.0)

    # Different user is unaffected
    assert limiter.acquire("user_2", max_requests=2, window_seconds=60.0)

    # Reset
    limiter.reset("user_1")
    assert limiter.acquire("user_1", max_requests=2, window_seconds=60.0)


def test_circuit_breaker_state_transitions() -> None:
    """Tests full lifecycle: CLOSED -> OPEN -> HALF_OPEN -> CLOSED."""
    breaker = CircuitBreaker(
        failure_threshold=3,
        recovery_timeout=0.1,  # 100ms for test speed
        half_open_success_threshold=2,
    )
    assert breaker.state == CircuitState.CLOSED

    # 2 failures: still CLOSED
    breaker.record_failure()
    breaker.record_failure()
    assert breaker.state == CircuitState.CLOSED

    # 3rd failure: transitions to OPEN
    breaker.record_failure()
    assert breaker.state == CircuitState.OPEN

    # Fast failure in OPEN
    with pytest.raises(CircuitBreakerOpenError):
        with breaker:
            pass

    # Wait for recovery timeout to transition to HALF_OPEN
    time.sleep(0.12)
    assert breaker.state == CircuitState.HALF_OPEN

    # 1st success in HALF_OPEN: remains HALF_OPEN
    breaker.record_success()
    assert breaker.state == CircuitState.HALF_OPEN

    # 2nd success in HALF_OPEN: recovers to CLOSED
    breaker.record_success()
    assert breaker.state == CircuitState.CLOSED


def test_circuit_breaker_half_open_failure_reopens() -> None:
    """Tests that a single failure in HALF_OPEN immediately reopens circuit."""
    breaker = CircuitBreaker(
        failure_threshold=2,
        recovery_timeout=0.05,
        half_open_success_threshold=2,
    )
    breaker.record_failure()
    breaker.record_failure()
    assert breaker.state == CircuitState.OPEN

    time.sleep(0.06)
    assert breaker.state == CircuitState.HALF_OPEN

    # Failure in HALF_OPEN re-opens
    breaker.record_failure()
    assert breaker.state == CircuitState.OPEN


def test_circuit_breaker_call_wrapper() -> None:
    """Tests call() helper method."""
    breaker = CircuitBreaker(failure_threshold=2, recovery_timeout=1.0)

    def success_op(val: int) -> int:
        return val * 2

    def failing_op() -> None:
        raise ConnectionError("Network down")

    assert breaker.call(success_op, 21) == 42

    with pytest.raises(ConnectionError):
        breaker.call(failing_op)
    with pytest.raises(ConnectionError):
        breaker.call(failing_op)

    # Now open
    assert breaker.state == CircuitState.OPEN
    with pytest.raises(CircuitBreakerOpenError):
        breaker.call(success_op, 5)
