#!/usr/bin/env python3
"""
Phi Accrual Failure Detector (Hayashibara et al.).
Outputs a continuous suspicion level (Phi) based on heartbeat arrival history
fitted to a normal distribution, avoiding rigid binary timeouts.
"""

import collections
import math
import time
from typing import Deque, Optional


class PhiAccrualDetector:
    """
    Adaptive failure detector based on the Phi Accrual algorithm.
    """

    def __init__(
        self,
        threshold: float = 8.0,
        window_size: int = 1000,
        min_std_dev: float = 0.05,
    ) -> None:
        self.threshold = threshold
        self.window_size = window_size
        self.min_std_dev = min_std_dev
        self.intervals: Deque[float] = collections.deque(maxlen=window_size)
        self.last_heartbeat_time: Optional[float] = None

    def heartbeat(self, timestamp: Optional[float] = None) -> None:
        """Records the arrival of a heartbeat."""
        now = timestamp if timestamp is not None else time.time()
        if self.last_heartbeat_time is not None:
            interval = max(0.001, now - self.last_heartbeat_time)
            self.intervals.append(interval)
        self.last_heartbeat_time = now

    def _mean_and_std_dev(self) -> tuple[float, float]:
        """Calculates sample mean and standard deviation of heartbeat intervals."""
        if not self.intervals:
            return 1.0, self.min_std_dev

        mean = sum(self.intervals) / len(self.intervals)
        variance = sum((x - mean) ** 2 for x in self.intervals) / len(self.intervals)
        std_dev = max(self.min_std_dev, math.sqrt(variance))
        return mean, std_dev

    def phi(self, current_time: Optional[float] = None) -> float:
        """
        Calculates the suspicion level Phi = -log10(P_later(t)).
        Higher values indicate a higher probability that the node has crashed.
        """
        if self.last_heartbeat_time is None:
            return 0.0

        now = current_time if current_time is not None else time.time()
        elapsed = max(0.0, now - self.last_heartbeat_time)

        mean, std_dev = self._mean_and_std_dev()

        # y = (elapsed - mean) / (std_dev * sqrt(2))
        y = (elapsed - mean) / (std_dev * math.sqrt(2.0))

        if y > 10.0:
            # Asymptotic approximation for large y to avoid math.erfc underflow to 0.0
            # erfc(y) ~ exp(-y^2) / (y * sqrt(pi))
            # P_later = 0.5 * erfc(y)
            # -log10(P_later) = -log10(0.5) + (y^2 * log10(e)) + log10(y * sqrt(pi))
            log10_e = 0.4342944819032518
            phi_val = (
                -math.log10(0.5)
                + (y * y * log10_e)
                + math.log10(y * math.sqrt(math.pi))
            )
            return max(0.0, phi_val)

        p_later = 0.5 * math.erfc(y)
        if p_later <= 1e-15:
            return 16.0

        return max(0.0, -math.log10(p_later))

    def is_available(self, current_time: Optional[float] = None) -> bool:
        """Returns True if the node is considered healthy (Phi < threshold)."""
        return self.phi(current_time) < self.threshold

    def is_dead(
        self,
        current_time: Optional[float] = None,
        dead_threshold: float = 12.0,
    ) -> bool:
        """Returns True if the node is definitively dead (Phi >= dead_threshold)."""
        return self.phi(current_time) >= dead_threshold
