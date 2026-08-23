#!/usr/bin/env python3
"""
Base Worker class for Process Supervisor.
Provides unified signal handling, socket inheritance, heartbeat pulses,
and request execution lifecycles across sync, threaded, async, and service workers.
"""

from __future__ import annotations

import abc
import os
import signal
import socket
import time
from typing import Any, Callable, Dict, Optional

from ..config import SupervisorConfig


class BaseWorker(abc.ABC):
    """
    Abstract worker base class defining common execution flow and signal handling.
    """

    def __init__(
        self,
        worker_id: str,
        config: SupervisorConfig,
        server_socket: Optional[socket.socket] = None,
        app_target: Optional[Any] = None,
        pulse_callback: Optional[
            Callable[[int, Optional[Dict[str, Any]]], None]
        ] = None,
    ) -> None:
        self.worker_id = worker_id
        self.config = config
        self.server_socket = server_socket
        self.app_target = app_target
        self.pulse_callback = pulse_callback

        self.pid = os.getpid()
        self.alive = True
        self.requests_handled = 0
        self.boot_time = time.time()

    def init_signals(self) -> None:
        """Sets up worker-specific signal traps safely."""
        try:
            signal.signal(signal.SIGQUIT, self._handle_sigquit)
            signal.signal(signal.SIGTERM, self._handle_sigterm)
            signal.signal(signal.SIGINT, self._handle_sigterm)
            if hasattr(signal, "SIGWINCH"):
                signal.signal(signal.SIGWINCH, signal.SIG_IGN)
        except (ValueError, AttributeError, OSError):
            # Safe ignore if running in a background thread or non-main interpreter
            pass

    def _handle_sigquit(self, _signum: int, _frame: Any) -> None:
        """Handles graceful drain and termination."""
        self.alive = False

    def _handle_sigterm(self, _signum: int, _frame: Any) -> None:
        """Handles immediate graceful termination."""
        self.alive = False

    def pulse(self, metadata: Optional[Dict[str, Any]] = None) -> None:
        """Emits a liveness pulse with metrics to the Arbiter."""
        meta = {
            "worker_id": self.worker_id,
            "requests_handled": self.requests_handled,
            "uptime": round(time.time() - self.boot_time, 2),
        }
        if metadata:
            meta.update(metadata)

        if self.pulse_callback:
            try:
                self.pulse_callback(os.getpid(), meta)
            except Exception:
                pass

    @abc.abstractmethod
    def run(self) -> None:
        """Main worker execution loop to be implemented by concrete worker types."""
        raise NotImplementedError

    def close(self) -> None:
        """Cleans up resources upon worker exit."""
        self.alive = False
        if self.server_socket:
            try:
                self.server_socket.close()
            except OSError:
                pass
