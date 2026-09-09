#!/usr/bin/env python3
"""
Worker subsystem package for Process Supervisor.
Exports BaseWorker, SyncWorker, GthreadWorker, AsyncWorker, and ManagedServiceWorker.
"""

from typing import Dict, Type

from .async_worker import AsyncWorker
from .base import BaseWorker
from .gthread_worker import GthreadWorker
from .queue_worker import QueueWorker
from .service_worker import ManagedServiceWorker
from .spider_worker import SpiderWorker
from .sync_worker import SyncWorker

ConcreteWorkerClass = Type[BaseWorker]

WORKER_CLASSES: Dict[str, ConcreteWorkerClass] = {
    "sync": SyncWorker,
    "gthread": GthreadWorker,
    "threaded": GthreadWorker,
    "async": AsyncWorker,
    "queue": QueueWorker,
    "spider": SpiderWorker,
}

__all__ = [
    "BaseWorker",
    "SyncWorker",
    "GthreadWorker",
    "AsyncWorker",
    "QueueWorker",
    "SpiderWorker",
    "ManagedServiceWorker",
    "WORKER_CLASSES",
]
