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

    def enqueue(self, request: Request) -> bool:
        """Enqueue a request if not already visited (unless dont_filter=True)."""
        if not request.dont_filter:
            if not self.bloom.add(request.url):
                return False

        self._counter += 1
        heapq.heappush(self._heap, (-request.priority, self._counter, request))
        return True

    def next_request(self) -> Optional[Request]:
        """Pulls the next highest priority request respecting per-domain rate limits."""
        if not self._heap:
            return None

        # Re-queue check for domain politeness
        now = time.perf_counter()
        skipped: List[Tuple[int, int, Request]] = []
        chosen: Optional[Request] = None

        while self._heap:
            neg_prio, cnt, req = heapq.heappop(self._heap)
            domain = _extract_domain(req.url)
            last = self._last_access.get(domain, 0.0)
            delay = req.meta.get("download_delay", self.default_delay)

            if now - last >= delay:
                chosen = req
                self._last_access[domain] = now
                break
            else:
                skipped.append((neg_prio, cnt, req))

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
