#!/usr/bin/env python3
"""
Generic Message Queue and Event Stream Consumer Worker.
Continuously dequeues items from an abstract queue or callable source,
processes them via a handler, and provides graceful drain upon SIGQUIT.
"""

from __future__ import annotations

import logging
import queue
import time
from typing import Any, Callable, Dict, Optional

from ..config import SupervisorConfig
from .base import BaseWorker

logger = logging.getLogger(__name__)


class QueueWorker(BaseWorker):
    """
    Worker executing continuous background message consumption from a queue or iterable source.
    """

    def __init__(
        self,
        worker_id: str,
        config: SupervisorConfig,
        server_socket: Optional[Any] = None,
        app_target: Optional[Callable[[Any], Any]] = None,
        source_queue: Optional[Any] = None,
        poll_interval: float = 0.1,
        pulse_callback: Optional[
            Callable[[int, Optional[Dict[str, Any]]], None]
        ] = None,
    ) -> None:
        super().__init__(
            worker_id=worker_id,
            config=config,
            server_socket=server_socket,
            app_target=app_target,
            pulse_callback=pulse_callback,
        )
        self.source_queue = source_queue
        self.poll_interval = max(0.01, poll_interval)
        self.is_processing = False

    def _fetch_from_queue(self) -> Optional[Any]:
        try:
            return self.source_queue.get(timeout=self.poll_interval)
        except (queue.Empty, Exception):
            return None

    def _fetch_from_callable(self) -> Optional[Any]:
        try:
            return self.source_queue()
        except Exception as exc:
            logger.error(
                "[QueueWorker %s] Error polling source: %s", self.worker_id, exc
            )
            return None

    def _fetch_item(self) -> Optional[Any]:
        """Safely fetches next item from source queue or callable."""
        if self.source_queue is None:
            return None
        if hasattr(self.source_queue, "get"):
            return self._fetch_from_queue()
        if callable(self.source_queue):
            return self._fetch_from_callable()
        return None

    def _process_item(self, item: Any) -> None:
        """Executes handler against fetched item with heartbeat pulses."""
        self.is_processing = True
        self.pulse({"handling": True, "messages": self.requests_handled})
        try:
            if callable(self.app_target):
                self.app_target(item)
            self.requests_handled += 1
        except Exception as exc:
            logger.error(
                "[QueueWorker %s] Error processing queue item: %s",
                self.worker_id,
                exc,
            )
        finally:
            self.is_processing = False
            self.pulse({"handling": False, "messages": self.requests_handled})

    def run(self) -> None:
        """Main queue consumption execution loop."""
        self.init_signals()
        logger.info(
            "[QueueWorker %s] Starting message consumption loop (PID: %d)",
            self.worker_id,
            self.pid,
        )

        while self.alive:
            item = self._fetch_item()
            if item is not None:
                self._process_item(item)
            else:
                self.pulse({"handling": False, "messages": self.requests_handled})
                time.sleep(self.poll_interval)

        logger.info(
            "[QueueWorker %s] Draining completed. Exiting worker process.",
            self.worker_id,
        )
        self.close()
