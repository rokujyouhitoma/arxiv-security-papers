"""Crawl Frontier and Politeness Scheduler with priority queue and Bloom filter deduplication."""

from __future__ import annotations

import heapq
import time
import urllib.parse
from collections import defaultdict, deque
from typing import DefaultDict, Deque, Dict, List, Optional, Tuple

from .bloom import ScalableBloomFilter
from .downloader import Request


class Scheduler:
    """Manages crawl frontier with priority queues and per-domain polite rate limiting."""

    def __init__(self, bloom_capacity: int = 50000, default_delay: float = 0.5) -> None:
        self.default_delay: float = default_delay
        self.bloom: ScalableBloomFilter = ScalableBloomFilter(
            initial_capacity=bloom_capacity
        )
        self._heap: List[Tuple[int, int, Request]] = []  # (-priority, counter, request)
        self._counter: int = 0
        self._domain_queues: DefaultDict[str, Deque[Request]] = defaultdict(deque)
        self._last_access: Dict[str, float] = {}

    def __bool__(self) -> bool:
        """Ensures scheduler instance is always truthy even when empty."""
        return True

    def enqueue(self, request: Request) -> bool:
        """Enqueue a request if not already visited (unless dont_filter=True)."""
        if not request.dont_filter and not self.bloom.add(request.url):
            return False

        self._counter += 1
        heapq.heappush(self._heap, (-request.priority, self._counter, request))
        return True

    def _is_request_ready(self, req: Request, now: float) -> bool:
        domain = _extract_domain(req.url)
        last = self._last_access.get(domain, 0.0)
        delay = float(req.meta.get("download_delay", self.default_delay))
        return bool((now - last) >= delay)

    def _mark_domain_accessed(self, req: Request, now: float) -> None:
        domain = _extract_domain(req.url)
        self._last_access[domain] = now

    def _pop_ready_request(
        self, now: float
    ) -> Tuple[Optional[Request], List[Tuple[int, int, Request]]]:
        skipped: List[Tuple[int, int, Request]] = []
        while self._heap:
            neg_prio, cnt, req = heapq.heappop(self._heap)
            if self._is_request_ready(req, now):
                self._mark_domain_accessed(req, now)
                return req, skipped
            skipped.append((neg_prio, cnt, req))
        return None, skipped

    def next_request(self) -> Optional[Request]:
        """Pulls the next highest priority request respecting per-domain rate limits."""
        if not self._heap:
            return None

        now = time.perf_counter()
        chosen, skipped = self._pop_ready_request(now)
        for item in skipped:
            heapq.heappush(self._heap, item)
        return chosen

    def has_pending_requests(self) -> bool:
        return len(self._heap) > 0

    def __len__(self) -> int:
        return len(self._heap)


def _extract_domain(url: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    return (parsed.hostname or "localhost").lower()
