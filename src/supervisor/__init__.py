#!/usr/bin/env python3
"""
Gunicorn-style Pre-Fork Process Supervisor & Arbiter Engine (DSN-12).
Generalized Process Manager supporting Stateless Worker Pools (Sync/Threaded/Async) and Stateful Managed Services.
"""

from .arbiter import Arbiter, ManagedPool
from .config import PoolConfig, ServiceConfig, SupervisorConfig
from .contracts import (
    DefaultLifecycleHook,
    LifecycleHook,
    ServiceRole,
    ServiceState,
    WorkerSpec,
)
from .control import ControlClient, ControlServer
from .heartbeat import HeartbeatWatchdog
from .top import SupervisorTopViewer, run_top
from .workers import (
    WORKER_CLASSES,
    AsyncWorker,
    BaseWorker,
    GthreadWorker,
    ManagedServiceWorker,
    QueueWorker,
    SyncWorker,
)

__all__ = [
    # Core Arbiter & Engine
    "Arbiter",
    "ManagedPool",
    # Config Models
    "SupervisorConfig",
    "PoolConfig",
    "ServiceConfig",
    # Contracts & Interfaces
    "WorkerSpec",
    "ServiceRole",
    "ServiceState",
    "LifecycleHook",
    "DefaultLifecycleHook",
    # IPC & Monitoring
    "ControlServer",
    "ControlClient",
    "HeartbeatWatchdog",
    "SupervisorTopViewer",
    "run_top",
    # Workers
    "BaseWorker",
    "SyncWorker",
    "GthreadWorker",
    "AsyncWorker",
    "QueueWorker",
    "ManagedServiceWorker",
    "WORKER_CLASSES",
]
