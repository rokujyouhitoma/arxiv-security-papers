#!/usr/bin/env python3
"""
Multi-Threaded Worker (GthreadWorker) implementation.
Handles connections concurrently using a bounded ThreadPoolExecutor with Keep-Alive support.
"""

from __future__ import annotations

import concurrent.futures
import socket
import time
from typing import Any, Callable, Dict, Optional

from ..config import SupervisorConfig
from .sync_worker import SyncWorker


class GthreadWorker(SyncWorker):
    """
    Combines process-level fault isolation with thread-level concurrency.
    """

    def __init__(
        self,
        worker_id: str,
        config: SupervisorConfig,
        server_socket: Optional[socket.socket] = None,
        app_target: Optional[Callable[..., Any]] = None,
        wsgi_app: Optional[Callable[..., Any]] = None,
        pulse_callback: Optional[
            Callable[[int, Optional[Dict[str, Any]]], None]
        ] = None,
    ) -> None:
        target = app_target if app_target is not None else wsgi_app
        super().__init__(
            worker_id=worker_id,
            config=config,
            server_socket=server_socket,
            app_target=target,
            pulse_callback=pulse_callback,
        )
        self.num_threads = max(1, config.threads)
        self._executor: Optional[concurrent.futures.ThreadPoolExecutor] = None

    def run(self) -> None:
        """Main execution loop dispatching incoming sockets to thread pool."""
        self.init_signals()
        if self.server_socket:
            self.server_socket.settimeout(1.0)

        self._executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=self.num_threads, thread_name_prefix=f"gthread-{self.worker_id}"
        )

        while self.alive:
            self.pulse({"active_threads": self.num_threads})
            if not self.server_socket:
                time.sleep(0.1)
                continue

            try:
                client_sock, _ = self.server_socket.accept()
            except (socket.timeout, BlockingIOError):
                continue
            except OSError:
                if not self.alive:
                    break
                continue

            self._executor.submit(self.handle_client, client_sock)

        if self._executor:
            self._executor.shutdown(wait=True, cancel_futures=False)
        self.close()
