#!/usr/bin/env python3
"""
Managed Service Worker for stateful singletons and background subsystems.
Integrates generic LifecycleHook protocol for ordered setup, periodic health checks,
background buffer flushes, and graceful teardown.
"""

from __future__ import annotations

import time
from typing import Any, Callable, Dict, Optional

from ..config import SupervisorConfig
from ..contracts import DefaultLifecycleHook, LifecycleHook, ServiceState
from .base import BaseWorker


class ManagedServiceWorker(BaseWorker):
    """
    Dedicated worker executing a stateful managed service via LifecycleHook.
    """

    def __init__(
        self,
        worker_id: str,
        config: SupervisorConfig,
        service_name: str = "default_service",
        hook: Optional[LifecycleHook] = None,
        sync_interval: float = 2.0,
        pulse_callback: Optional[
            Callable[[int, Optional[Dict[str, Any]]], None]
        ] = None,
        max_requests: int = 0,
        max_requests_jitter: int = 0,
        max_worker_lifetime: float = 0.0,
        max_worker_lifetime_jitter: float = 0.0,
    ) -> None:
        super().__init__(
            worker_id=worker_id,
            config=config,
            server_socket=None,
            app_target=hook,
            pulse_callback=pulse_callback,
            max_requests=max_requests,
            max_requests_jitter=max_requests_jitter,
            max_worker_lifetime=max_worker_lifetime,
            max_worker_lifetime_jitter=max_worker_lifetime_jitter,
        )
        self.service_name = service_name
        self.hook: LifecycleHook = hook or DefaultLifecycleHook()
        self.sync_interval = sync_interval
        self.state: ServiceState = ServiceState.INITIALIZING
        self.last_sync = 0.0
        self.flushes_completed = 0

    def _init_hook_if_needed(self) -> None:
        if self.hook is None:
            self.hook = DefaultLifecycleHook()

    def _setup_service(self) -> bool:
        try:
            self.hook.bind_worker(self.worker_id)
            ok = self.hook.setup()
            self.state = ServiceState.READY if ok else ServiceState.FAILED
        except Exception:
            self.state = ServiceState.FAILED
        return self.state != ServiceState.FAILED

    def _check_service_health(self) -> bool:
        try:
            return self.hook.health_check()
        except Exception:
            return False

    def _flush_if_due(self) -> None:
        now = time.time()
        if now - self.last_sync >= self.sync_interval:
            try:
                self.hook.on_flush()
                self.flushes_completed += 1
            except Exception:
                pass
            self.last_sync = now

    def _sync_hook_metrics(self) -> None:
        try:
            metrics = self.hook.get_metrics()
            if isinstance(metrics, dict) and "requests_handled" in metrics:
                new_req = int(metrics["requests_handled"])
                if new_req > self.requests_handled:
                    self.last_active_epoch = time.time()
                self.requests_handled = new_req
        except Exception:
            pass

    def run(self) -> None:
        """Main service lifecycle execution loop."""
        self.init_signals()
        self._init_hook_if_needed()

        if not self._setup_service():
            self.pulse({"service": self.service_name, "state": self.state.value})
            self.close()
            return

        self.state = ServiceState.ACTIVE
        while self.alive:
            self._sync_hook_metrics()
            if self._should_retire():
                self.alive = False
                break
            healthy = self._check_service_health()
            self.pulse(
                {
                    "service": self.service_name,
                    "state": self.state.value,
                    "is_healthy": healthy,
                    "flushes": self.flushes_completed,
                    "last_sync_epoch": self.last_sync,
                }
            )
            self._flush_if_due()
            time.sleep(max(0.05, min(self.sync_interval, 0.5)))

        self.state = ServiceState.DRAINING
        try:
            self.hook.on_flush()
            self.hook.teardown()
        except Exception:
            pass
        self.state = ServiceState.STOPPED
        self.close()
