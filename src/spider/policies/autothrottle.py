"""AutoThrottle dynamic politeness rate-limiting based on download latency EMA."""

from __future__ import annotations

from typing import Any, Dict

from ..core.downloader import Request, Response


class AutoThrottlePolicy:
    """Dynamically adjusts download delay per domain based on response latency."""

    def __init__(
        self,
        min_delay: float = 0.2,
        max_delay: float = 30.0,
        target_concurrency: float = 1.0,
        alpha: float = 5.0,
        beta: float = 0.85,
    ) -> None:
        self.min_delay: float = min_delay
        self.max_delay: float = max_delay
        self.target_concurrency: float = target_concurrency
        self.alpha: float = alpha
        self.beta: float = beta
        self._latencies: Dict[str, float] = {}
        self._delays: Dict[str, float] = {}

    def get_delay(self, domain: str) -> float:
        """Gets current calculated delay for domain."""
        return self._delays.get(domain, self.min_delay)

    async def process_response(
        self, request: Request, response: Response, spider: Any
    ) -> Response:
        """Updates latency EMA and recalculates delay on response."""
        domain = _extract_host(response.url)
        latency = max(0.001, response.download_latency)
        prev_latency = self._latencies.get(domain, latency)

        # Exponential Moving Average: EMA = beta * prev + (1 - beta) * curr
        new_latency = (self.beta * prev_latency) + ((1.0 - self.beta) * latency)
        self._latencies[domain] = new_latency

        calculated_delay = max(
            self.min_delay,
            min(self.max_delay, self.alpha * new_latency / self.target_concurrency),
        )
        self._delays[domain] = calculated_delay
        return response


def _extract_host(url: str) -> str:
    import urllib.parse

    parsed = urllib.parse.urlsplit(url)
    return (parsed.hostname or "localhost").lower()
