#!/usr/bin/env python3
"""
Dedicated Search Service Worker for Process Supervisor.
Hosts the standalone SearchService and VectorEngine within an isolated process lifecycle,
preventing Web workers from ballooning in memory footprint.
"""

from __future__ import annotations

import logging
from typing import Any, Callable, Dict, Optional

from search.server.service import SearchService

from ..config import SupervisorConfig
from ..contracts import LifecycleHook
from .service_worker import ManagedServiceWorker

logger = logging.getLogger(__name__)


class SearchLifecycleHook(LifecycleHook):
    """Lifecycle hook for SearchService."""

    def __init__(self, config: SupervisorConfig) -> None:
        self.config = config
        self.socket_path = config.search_socket or "/tmp/search.sock"
        self.service: Optional[SearchService] = None

    def setup(self) -> bool:
        """Initializes and starts the SearchService IPC listener."""
        try:
            self.service = SearchService(
                socket_path=self.socket_path,
                workspace_dir=self.config.workspace_dir,
            )
            self.service.start()
            return True
        except Exception as e:
            logger.error("Failed to start SearchService: %s", e)
            return False

    def health_check(self) -> bool:
        """Verifies if the SearchService is active and responsive."""
        if not self.service:
            return False
        try:
            res = self.service.handle_command({"cmd": "ping"})
            return res.get("status") == "ok"
        except Exception:
            return False

    def on_flush(self) -> None:
        """Periodic flush or maintenance if needed."""
        pass

    def teardown(self) -> None:
        """Gracefully stops SearchService and cleans up Unix socket."""
        if self.service:
            try:
                self.service.stop()
            except Exception:
                pass
            self.service = None


class SearchWorker(ManagedServiceWorker):
    """
    Dedicated worker managing the Search Engine Service instance.
    """

    def __init__(
        self,
        worker_id: str,
        config: SupervisorConfig,
        pulse_callback: Optional[
            Callable[[int, Optional[Dict[str, Any]]], None]
        ] = None,
    ) -> None:
        super().__init__(
            worker_id=worker_id,
            config=config,
            service_name="search",
            hook=SearchLifecycleHook(config=config),
            sync_interval=5.0,
            pulse_callback=pulse_callback,
        )
