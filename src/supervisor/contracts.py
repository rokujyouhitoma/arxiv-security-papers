#!/usr/bin/env python3
"""
Contracts, interfaces, and protocol definitions for the generalized Process Supervisor.
Decouples process orchestration from specific domain workloads (web, database, queue, or custom).
"""

from __future__ import annotations

import abc
import enum
from typing import Any, Callable, Dict, Optional

from core.hsm import StateNode, TransitionRule


class ServiceRole(enum.Enum):
    """Archetype classifying the operational model of a managed unit."""

    STATELESS_POOL = "STATELESS_POOL"
    STATEFUL_SERVICE = "STATEFUL_SERVICE"
    ONESHOT_TASK = "ONESHOT_TASK"


_STATE_HIERARCHY_MAP = {
    "READY": "OPERATIONAL.READY",
    "ACTIVE": "OPERATIONAL.ACTIVE.IDLE",
    "DRAINING": "TRANSITIONING.DRAINING",
    "STOPPED": "TERMINATED.STOPPED",
    "FAILED": "TERMINATED.FAILED",
    "COMPLETED": "TERMINATED.COMPLETED",
    "OPERATIONAL": "OPERATIONAL",
    "TRANSITIONING": "TRANSITIONING",
    "TERMINATED": "TERMINATED",
    "INITIALIZING": "INITIALIZING",
}


class ServiceState(enum.Enum):
    """Lifecycle status of a managed process or subsystem."""

    INITIALIZING = "INITIALIZING"
    READY = "READY"
    ACTIVE = "ACTIVE"
    DRAINING = "DRAINING"
    STOPPED = "STOPPED"
    FAILED = "FAILED"
    COMPLETED = "COMPLETED"
    OPERATIONAL = "OPERATIONAL"
    TRANSITIONING = "TRANSITIONING"
    TERMINATED = "TERMINATED"

    @property
    def super_state(self) -> str:
        """Returns the composite super-state name according to DSN-23."""
        if self in (
            ServiceState.READY,
            ServiceState.ACTIVE,
            ServiceState.OPERATIONAL,
        ):
            return "OPERATIONAL"
        if self in (ServiceState.DRAINING, ServiceState.TRANSITIONING):
            return "TRANSITIONING"
        if self in (
            ServiceState.STOPPED,
            ServiceState.FAILED,
            ServiceState.COMPLETED,
            ServiceState.TERMINATED,
        ):
            return "TERMINATED"
        return "INITIALIZING"

    @property
    def hierarchical_path(self) -> str:
        """Returns dotted Statecharts path, e.g., 'OPERATIONAL.ACTIVE.IDLE'."""
        return _STATE_HIERARCHY_MAP.get(self.value, self.value)


def _build_operational_substates(op: StateNode) -> None:
    ready = op.add_child(StateNode("READY"))
    active = op.add_child(StateNode("ACTIVE", initial_child="IDLE"))
    idle = active.add_child(StateNode("IDLE"))
    proc = active.add_child(StateNode("PROCESSING"))
    paused = active.add_child(StateNode("PAUSED"))

    ready.add_transition(TransitionRule("READY", "START", "ACTIVE"))
    idle.add_transition(TransitionRule("IDLE", "DISPATCH", "PROCESSING"))
    proc.add_transition(TransitionRule("PROCESSING", "FINISH", "IDLE"))
    proc.add_transition(TransitionRule("PROCESSING", "PAUSE", "PAUSED"))
    paused.add_transition(TransitionRule("PAUSED", "RESUME", "IDLE"))


def _build_transitioning_substates(trans: StateNode) -> None:
    draining = trans.add_child(StateNode("DRAINING", initial_child="CLOSING_LISTENERS"))
    closing = draining.add_child(StateNode("CLOSING_LISTENERS"))
    waiting = draining.add_child(StateNode("WAITING_INFLIGHT"))
    flushing = draining.add_child(StateNode("FLUSHING_BUFFERS"))
    trans.add_child(StateNode("ROTATING"))

    closing.add_transition(
        TransitionRule("CLOSING_LISTENERS", "LISTENERS_CLOSED", "WAITING_INFLIGHT")
    )
    waiting.add_transition(
        TransitionRule("WAITING_INFLIGHT", "INFLIGHT_DRAINED", "FLUSHING_BUFFERS")
    )
    flushing.add_transition(
        TransitionRule("FLUSHING_BUFFERS", "BUFFERS_FLUSHED", "TERMINATED.STOPPED")
    )


def _build_terminated_substates(term: StateNode) -> None:
    term.add_child(StateNode("STOPPED"))
    term.add_child(StateNode("FAILED"))
    term.add_child(StateNode("COMPLETED"))
    recovering = term.add_child(StateNode("RECOVERING"))
    recovering.add_transition(
        TransitionRule("RECOVERING", "RECOVERED", "OPERATIONAL.READY")
    )


def _attach_supervisor_rules(op: StateNode, trans: StateNode, term: StateNode) -> None:
    op.add_transition(TransitionRule("OPERATIONAL", "SIGTERM", "TERMINATED.STOPPED"))
    op.add_transition(
        TransitionRule("OPERATIONAL", "SIGQUIT", "TRANSITIONING.DRAINING")
    )
    op.add_transition(TransitionRule("OPERATIONAL", "FAIL", "TERMINATED.FAILED"))
    op.add_transition(
        TransitionRule("OPERATIONAL", "ONESHOT_COMPLETE", "TERMINATED.COMPLETED")
    )
    trans.add_transition(
        TransitionRule("TRANSITIONING", "DRAIN_TIMEOUT", "TERMINATED.FAILED")
    )
    trans.add_transition(
        TransitionRule("TRANSITIONING", "SIGTERM", "TERMINATED.STOPPED")
    )


def build_supervisor_state_tree(pool_name: str = "supervisor") -> StateNode:
    """
    Constructs a DSN-23 compliant 3-tier hierarchical state tree for supervisor orchestration.
    """
    root = StateNode("ROOT", initial_child="OPERATIONAL")
    op = root.add_child(StateNode("OPERATIONAL", initial_child="READY"))
    trans = root.add_child(StateNode("TRANSITIONING", initial_child="DRAINING"))
    term = root.add_child(StateNode("TERMINATED", initial_child="STOPPED"))

    _build_operational_substates(op)
    _build_transitioning_substates(trans)
    _build_terminated_substates(term)
    _attach_supervisor_rules(op, trans, term)
    return root


class LifecycleHook(abc.ABC):
    """
    Contract for stateful or managed services to define custom startup,
    health evaluation, background flushing, and graceful teardown actions.
    """

    def bind_worker(self, worker_id: str) -> None:
        """Notifies hook of the assigned unique worker identifier."""
        pass

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

    def get_metrics(self) -> Dict[str, Any]:
        """Returns structured runtime metrics (e.g. requests_handled) for worker telemetry."""
        return {}


def _default_true() -> bool:
    return True


def _default_none() -> None:
    pass


def _default_dict() -> Dict[str, Any]:
    return {}


def _resolve_fn(fn: Any, default: Any) -> Any:
    return default if fn is None else fn


class DefaultLifecycleHook(LifecycleHook):
    """Generic fallback lifecycle hook suitable for arbitrary background services."""

    def __init__(
        self,
        setup_fn: Optional[Callable[[], bool]] = None,
        health_fn: Optional[Callable[[], bool]] = None,
        flush_fn: Optional[Callable[[], None]] = None,
        teardown_fn: Optional[Callable[[], None]] = None,
        metrics_fn: Optional[Callable[[], Dict[str, Any]]] = None,
    ) -> None:
        self._setup_fn = _resolve_fn(setup_fn, _default_true)
        self._health_fn = _resolve_fn(health_fn, _default_true)
        self._flush_fn = _resolve_fn(flush_fn, _default_none)
        self._teardown_fn = _resolve_fn(teardown_fn, _default_none)
        self._metrics_fn = _resolve_fn(metrics_fn, _default_dict)

    def setup(self) -> bool:
        return bool(self._setup_fn())

    def health_check(self) -> bool:
        return bool(self._health_fn())

    def on_flush(self) -> None:
        self._flush_fn()

    def teardown(self) -> None:
        self._teardown_fn()

    def get_metrics(self) -> Dict[str, Any]:
        return dict(self._metrics_fn())


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
        dependencies: Optional[list[str]] = None,
        max_retries: int = 0,
        max_requests: int = 0,
        max_requests_jitter: int = 0,
        max_worker_lifetime: float = 0.0,
        max_worker_lifetime_jitter: float = 0.0,
        max_worker_memory_mb: float = 0.0,
        graceful_timeout: float = 30.0,
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
        self.dependencies = list(dependencies or [])
        self.max_retries = max_retries
        self.retry_count = 0
        self.max_requests = max_requests
        self.max_requests_jitter = max_requests_jitter
        self.max_worker_lifetime = max_worker_lifetime
        self.max_worker_lifetime_jitter = max_worker_lifetime_jitter
        self.max_worker_memory_mb = max(0.0, float(max_worker_memory_mb))
        self.graceful_timeout = graceful_timeout
        self.metadata = metadata or {}

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "target_count": self.target_count,
            "worker_class": self.worker_class,
            "role": self.role.value,
            "sync_interval": self.sync_interval,
            "dependencies": self.dependencies,
            "max_retries": self.max_retries,
            "max_requests": self.max_requests,
            "max_requests_jitter": self.max_requests_jitter,
            "max_worker_lifetime": self.max_worker_lifetime,
            "max_worker_lifetime_jitter": self.max_worker_lifetime_jitter,
            "max_worker_memory_mb": self.max_worker_memory_mb,
            "graceful_timeout": self.graceful_timeout,
            "metadata": self.metadata,
        }
