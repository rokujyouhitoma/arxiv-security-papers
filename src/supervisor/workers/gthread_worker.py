#!/usr/bin/env python3
"""
Multi-Threaded Worker (GthreadWorker) implementation.
Handles connections concurrently using a bounded ThreadPoolExecutor with Keep-Alive support.
"""

from __future__ import annotations

import concurrent.futures
import socket
import threading
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
        self._active_requests = 0
        self._req_lock = threading.Lock()

    def handle_client(self, client_sock: socket.socket) -> None:
        """Processes client request and updates active request count."""
        with self._req_lock:
            self._active_requests += 1
            is_active = self._active_requests > 0
        self.pulse(
            {"is_handling_request": is_active, "active_requests": self._active_requests}
        )
        try:
            super().handle_client(client_sock)
        finally:
            with self._req_lock:
                self._active_requests = max(0, self._active_requests - 1)
                is_active = self._active_requests > 0
            self.pulse(
                {
                    "is_handling_request": is_active,
                    "active_requests": self._active_requests,
                }
            )

    def _accept_gthread_client(self) -> Optional[socket.socket]:
        try:
            client_sock, _ = self.server_socket.accept()
            return client_sock
        except (socket.timeout, BlockingIOError):
            return None
        except OSError:
            return None

    def _pulse_active_state(self) -> None:
        with self._req_lock:
            is_active = self._active_requests > 0
        self.pulse(
            {
                "active_threads": self.num_threads,
                "is_handling_request": is_active,
                "active_requests": self._active_requests,
            }
        )

    def _dispatch_one(self) -> bool:
        """Accept one connection and submit to thread pool. Returns False to break."""
        if not self.server_socket:
            time.sleep(0.1)
            return True
        client_sock = self._accept_gthread_client()
        if client_sock is None:
            return self.alive
        self._executor.submit(self.handle_client, client_sock)
        return True

    def run(self) -> None:
        """Main execution loop dispatching incoming sockets to thread pool."""
        self.init_signals()
        if self.server_socket:
            self.server_socket.settimeout(1.0)

        self._executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=self.num_threads, thread_name_prefix=f"gthread-{self.worker_id}"
        )

        while self.alive:
            self._pulse_active_state()
            if not self._dispatch_one():
                break

        if self._executor:
            self._executor.shutdown(wait=True, cancel_futures=False)
        self.close()
