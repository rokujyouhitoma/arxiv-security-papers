#!/usr/bin/env python3
"""
Contracts, interfaces, and protocol definitions for the generalized Process Supervisor.
Decouples process orchestration from specific domain workloads (web, database, queue, or custom).
"""

from __future__ import annotations

import abc
import enum
from typing import Any, Callable, Dict, Optional


class ServiceRole(enum.Enum):
    """Archetype classifying the operational model of a managed unit."""

    STATELESS_POOL = "STATELESS_POOL"
    STATEFUL_SERVICE = "STATEFUL_SERVICE"
    ONESHOT_TASK = "ONESHOT_TASK"


class ServiceState(enum.Enum):
    """Lifecycle status of a managed process or subsystem."""

    INITIALIZING = "INITIALIZING"
    READY = "READY"
    ACTIVE = "ACTIVE"
    DRAINING = "DRAINING"
    STOPPED = "STOPPED"
    FAILED = "FAILED"


class LifecycleHook(abc.ABC):
    """
    Contract for stateful or managed services to define custom startup,
    health evaluation, background flushing, and graceful teardown actions.
    """

    @abc.abstractmethod
    def setup(self) -> bool:
        """Executes one-time initialization. Returns True if successful."""
        raise NotImplementedError

    @abc.abstractmethod
    def health_check(self) -> bool:
        """Evaluates health and readiness. Returns True if healthy."""
        raise NotImplementedError

    def on_flush(self) -> None:
        """Invoked periodically or before shutdown to flush dirty state to disk."""
        pass

    @abc.abstractmethod
    def teardown(self) -> None:
        """Executes clean shutdown and resource release."""
        raise NotImplementedError


class DefaultLifecycleHook(LifecycleHook):
    """Generic fallback lifecycle hook suitable for arbitrary background services."""

    def __init__(
        self,
        setup_fn: Optional[Callable[[], bool]] = None,
        health_fn: Optional[Callable[[], bool]] = None,
        flush_fn: Optional[Callable[[], None]] = None,
        teardown_fn: Optional[Callable[[], None]] = None,
    ) -> None:
        self._setup_fn = setup_fn or (lambda: True)
        self._health_fn = health_fn or (lambda: True)
        self._flush_fn = flush_fn or (lambda: None)
        self._teardown_fn = teardown_fn or (lambda: None)

    def setup(self) -> bool:
        return bool(self._setup_fn())

    def health_check(self) -> bool:
        return bool(self._health_fn())

    def on_flush(self) -> None:
        self._flush_fn()

    def teardown(self) -> None:
        self._teardown_fn()


class WorkerSpec:
    """
    Declarative specification defining an isolated worker process pool or service unit.
    Decouples Arbiter process orchestration from specific domain workloads.
    """

    def __init__(
        self,
        name: str,
        target_count: int = 1,
        worker_class: Optional[str] = "sync",
        app_target: Optional[Callable[..., Any]] = None,
        server_socket: Optional[Any] = None,
        hook: Optional[LifecycleHook] = None,
        role: ServiceRole = ServiceRole.STATELESS_POOL,
        sync_interval: float = 2.0,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.name = name
        self.target_count = max(0, target_count)
        self.worker_class = worker_class or "sync"
        self.app_target = app_target
        self.server_socket = server_socket
        self.hook = hook
        self.role = role
        self.sync_interval = sync_interval
        self.metadata = metadata or {}

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "target_count": self.target_count,
            "worker_class": self.worker_class,
            "role": self.role.value,
            "sync_interval": self.sync_interval,
            "metadata": self.metadata,
        }
