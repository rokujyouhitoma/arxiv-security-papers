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
        max_requests: int = 0,
        max_requests_jitter: int = 0,
        max_worker_lifetime: float = 0.0,
        max_worker_lifetime_jitter: float = 0.0,
    ) -> None:
        self.worker_id = worker_id
        self.config = config
        self.server_socket = server_socket
        self.app_target = app_target
        self.pulse_callback = pulse_callback

        self.max_requests = max(0, max_requests)
        self.max_requests_jitter = max(0, max_requests_jitter)
        self.max_worker_lifetime = max(0.0, float(max_worker_lifetime))
        self.max_worker_lifetime_jitter = max(0.0, float(max_worker_lifetime_jitter))

        self.pid = os.getpid()
        self.alive = True
        self.requests_handled = 0
        self.boot_time = time.time()
        self.last_active_epoch = self.boot_time
        self.effective_max_requests = 0
        self.effective_max_lifetime = 0.0
        self._init_retirement_criteria()

    def _calc_effective_requests(self) -> None:
        import random

        if self.max_requests > 0:
            jitter = (
                random.randint(-self.max_requests_jitter, self.max_requests_jitter)
                if self.max_requests_jitter > 0
                else 0
            )
            self.effective_max_requests = max(1, self.max_requests + jitter)
        else:
            self.effective_max_requests = 0

    def _calc_effective_lifetime(self) -> None:
        import random

        if self.max_worker_lifetime > 0.0:
            jitter = (
                random.uniform(
                    -self.max_worker_lifetime_jitter, self.max_worker_lifetime_jitter
                )
                if self.max_worker_lifetime_jitter > 0.0
                else 0.0
            )
            self.effective_max_lifetime = max(0.1, self.max_worker_lifetime + jitter)
        else:
            self.effective_max_lifetime = 0.0

    def _init_retirement_criteria(self) -> None:
        """Calculates randomized retirement thresholds based on jitter."""
        self._calc_effective_requests()
        self._calc_effective_lifetime()

    def _is_request_limit_reached(self) -> bool:
        return (
            self.effective_max_requests > 0
            and self.requests_handled >= self.effective_max_requests
        )

    def _is_lifetime_expired(self) -> bool:
        if self.effective_max_lifetime <= 0.0:
            return False
        return (time.time() - self.boot_time) >= self.effective_max_lifetime

    def _should_retire(self) -> bool:
        """Determines if worker has exceeded request count or lifetime thresholds."""
        if not self.alive:
            return True
        return self._is_request_limit_reached() or self._is_lifetime_expired()

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

    def _get_heartbeat_file_path(self) -> str:
        state_dir = os.path.join(self.config.workspace_dir, "outputs", "supervisor")
        os.makedirs(state_dir, exist_ok=True)
        return os.path.join(state_dir, f"heartbeat_{self.pid}.json")

    def _write_heartbeat_file(self, meta: Dict[str, Any]) -> None:
        try:
            import json

            path = self._get_heartbeat_file_path()
            tmp_path = f"{path}.tmp.{self.pid}"
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(meta, f)
            os.replace(tmp_path, path)
        except Exception:
            pass

    def _cleanup_heartbeat_file(self) -> None:
        try:
            path = self._get_heartbeat_file_path()
            if os.path.exists(path):
                os.remove(path)
        except Exception:
            pass

    def pulse(self, metadata: Optional[Dict[str, Any]] = None) -> None:
        """Emits a liveness pulse with metrics to the Arbiter."""
        self.pid = os.getpid()
        meta = {
            "pid": self.pid,
            "worker_id": self.worker_id,
            "requests_handled": self.requests_handled,
            "uptime": round(time.time() - self.boot_time, 2),
            "last_seen_epoch": time.time(),
            "last_active_epoch": self.last_active_epoch,
            "is_handling_request": False,
        }
        if metadata:
            meta.update(metadata)

        if self.pulse_callback:
            try:
                self.pulse_callback(self.pid, meta)
            except Exception:
                pass
        self._write_heartbeat_file(meta)

    @abc.abstractmethod
    def run(self) -> None:
        """Main worker execution loop to be implemented by concrete worker types."""
        raise NotImplementedError

    def close(self) -> None:
        """Cleans up resources upon worker exit."""
        self.alive = False
        self._cleanup_heartbeat_file()
        if self.server_socket:
            try:
                self.server_socket.close()
            except OSError:
                pass
