#!/usr/bin/env python3
"""
Thread-safe Event Broadcaster for Pipeline Telemetry and Progress Streaming.
Provides in-memory pub-sub queues for SSE gateways and real-time observers.
"""

from __future__ import annotations

import queue
import threading
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional


class PipelineEventBroadcaster:
    """Thread-safe singleton event broadcaster for pipeline execution lifecycle."""

    _instance: Optional[PipelineEventBroadcaster] = None
    _lock: threading.Lock = threading.Lock()

    def __init__(self) -> None:
        self._subscribers: List[queue.Queue[Dict[str, Any]]] = []
        self._sub_lock = threading.Lock()
        self._last_event: Optional[Dict[str, Any]] = None

    @classmethod
    def get_instance(cls) -> PipelineEventBroadcaster:
        """Returns singleton instance with double-checked locking."""
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = cls()
        return cls._instance

    def subscribe(self, maxsize: int = 100) -> queue.Queue[Dict[str, Any]]:
        """Subscribes a new consumer queue for streaming events."""
        q: queue.Queue[Dict[str, Any]] = queue.Queue(maxsize=maxsize)
        with self._sub_lock:
            self._subscribers.append(q)
        return q

    def unsubscribe(self, q: queue.Queue[Dict[str, Any]]) -> None:
        """Unregisters consumer queue to prevent memory leak."""
        with self._sub_lock:
            if q in self._subscribers:
                self._subscribers.remove(q)

    def emit(self, event_type: str, payload: Dict[str, Any]) -> None:
        """Emits an event payload to all registered subscribers."""
        event: Dict[str, Any] = {
            "type": event_type,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "data": payload,
        }
        with self._sub_lock:
            self._last_event = event
            for q in list(self._subscribers):
                try:
                    q.put_nowait(event)
                except queue.Full:
                    # Drop oldest or skip if full to protect memory
                    pass

    def get_last_event(self) -> Optional[Dict[str, Any]]:
        """Returns the most recent emitted event for initial SSE handshake."""
        with self._sub_lock:
            return self._last_event

    def reset(self) -> None:
        """Resets all subscribers and cached state (primarily for tests)."""
        with self._sub_lock:
            self._subscribers.clear()
            self._last_event = None
