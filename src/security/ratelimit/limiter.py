#!/usr/bin/env python3
"""
Rate Limiter & Resource Quotas Module.
Provides Token Bucket and Sliding Window rate limiting algorithms to prevent DoS,
brute force, and API quota exhaustion (e.g. arXiv API HTTP 429).
Zero external runtime dependencies.
"""

import threading
import time
from collections import deque
from typing import Deque, Dict, Optional


class RateLimitExceededError(ValueError):
    """Raised when request rate exceeds configured thresholds."""

    pass


class TokenBucketRateLimiter:
    """
    Thread-safe Token Bucket Rate Limiter.
    Allows bursts up to capacity while constraining long-term rate to fill_rate tokens/sec.
    """

    def __init__(self, capacity: float = 10.0, fill_rate: float = 1.0) -> None:
        if capacity <= 0 or fill_rate <= 0:
            raise ValueError("Capacity and fill_rate must be positive")
        self.capacity = float(capacity)
        self.fill_rate = float(fill_rate)
        self._tokens = float(capacity)
        self._last_update = time.monotonic()
        self._lock = threading.Lock()

    def _refill(self, now: float) -> None:
        """Refills tokens accrued since the last update timestamp."""
        elapsed = now - self._last_update
        if elapsed > 0:
            self._tokens = min(self.capacity, self._tokens + elapsed * self.fill_rate)
            self._last_update = now

    def acquire(self, tokens: float = 1.0) -> bool:
        """Attempts to immediately acquire tokens. Returns True if granted."""
        if tokens <= 0:
            return True
        with self._lock:
            now = time.monotonic()
            self._refill(now)
            if self._tokens >= tokens:
                self._tokens -= tokens
                return True
            return False

    def wait_and_acquire(self, tokens: float = 1.0, timeout: float = 5.0) -> bool:
        """Blocks until tokens are available or timeout expires."""
        deadline = time.monotonic() + timeout
        while time.monotonic() <= deadline:
            if self.acquire(tokens):
                return True
            sleep_time = min(0.05, max(0.005, (tokens - self._tokens) / self.fill_rate))
            time.sleep(sleep_time)
        return False

    @property
    def current_tokens(self) -> float:
        """Returns current token estimate without consuming."""
        with self._lock:
            self._refill(time.monotonic())
            return self._tokens


class SlidingWindowRateLimiter:
    """
    Thread-safe Sliding Window Counter Rate Limiter.
    Enforces maximum request quota over a rolling window_seconds per key (e.g. IP/user).
    """

    def __init__(self) -> None:
        self._windows: Dict[str, Deque[float]] = {}
        self._lock = threading.Lock()

    def _prune(self, queue: Deque[float], cutoff: float) -> None:
        """Removes expired request timestamps from the deque."""
        while queue and queue[0] < cutoff:
            queue.popleft()

    def is_allowed(
        self,
        key: str,
        max_requests: int = 60,
        window_seconds: float = 60.0,
    ) -> bool:
        """Checks if key is within quota without recording a new request."""
        with self._lock:
            now = time.monotonic()
            cutoff = now - window_seconds
            queue = self._windows.get(key)
            if queue is None:
                return True
            self._prune(queue, cutoff)
            return len(queue) < max_requests

    def acquire(
        self,
        key: str,
        max_requests: int = 60,
        window_seconds: float = 60.0,
    ) -> bool:
        """Attempts to acquire a request slot for key. Returns True if accepted."""
        with self._lock:
            now = time.monotonic()
            cutoff = now - window_seconds
            if key not in self._windows:
                self._windows[key] = deque()
            queue = self._windows[key]
            self._prune(queue, cutoff)
            if len(queue) < max_requests:
                queue.append(now)
                return True
            return False

    def reset(self, key: Optional[str] = None) -> None:
        """Clears sliding window entries for a specific key or all keys."""
        with self._lock:
            if key is not None:
                self._windows.pop(key, None)
            else:
                self._windows.clear()
