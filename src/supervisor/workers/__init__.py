#!/usr/bin/env python3
"""
Worker subsystem package for Process Supervisor.
Exports BaseWorker, SyncWorker, GthreadWorker, AsyncWorker, and ManagedServiceWorker.
"""

from typing import Dict, Type, Union

from .async_worker import AsyncWorker
from .base import BaseWorker
from .gthread_worker import GthreadWorker
from .service_worker import ManagedServiceWorker
from .sync_worker import SyncWorker

ConcreteWorkerClass = Type[Union[SyncWorker, GthreadWorker, AsyncWorker]]

WORKER_CLASSES: Dict[str, ConcreteWorkerClass] = {
    "sync": SyncWorker,
    "gthread": GthreadWorker,
    "threaded": GthreadWorker,
    "async": AsyncWorker,
}

__all__ = [
    "BaseWorker",
    "SyncWorker",
    "GthreadWorker",
    "AsyncWorker",
    "ManagedServiceWorker",
    "WORKER_CLASSES",
]
