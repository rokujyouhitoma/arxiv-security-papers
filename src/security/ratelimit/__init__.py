#!/usr/bin/env python3
"""
Rate Limiting, DoS Protection & Circuit Breaker Package.
Provides Token Bucket, Sliding Window rate limiters, and a 3-state Circuit Breaker.
Zero external runtime dependencies.
"""

from .circuit_breaker import CircuitBreaker, CircuitBreakerOpenError, CircuitState
from .limiter import (
    RateLimitExceededError,
    SlidingWindowRateLimiter,
    TokenBucketRateLimiter,
)

__all__ = [
    "CircuitBreaker",
    "CircuitBreakerOpenError",
    "CircuitState",
    "RateLimitExceededError",
    "SlidingWindowRateLimiter",
    "TokenBucketRateLimiter",
]
