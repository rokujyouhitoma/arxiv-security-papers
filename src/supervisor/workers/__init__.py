#!/usr/bin/env python3
"""
Worker subsystem package for Process Supervisor.
Exports BaseWorker, SyncWorker, GthreadWorker, AsyncWorker, ManagedServiceWorker, and DatabaseWorker.
"""

from typing import Dict, Type, Union

from .async_worker import AsyncWorker
from .base import BaseWorker
from .gthread_worker import GthreadWorker
from .search_worker import SearchWorker
from .service_worker import DatabaseWorker, ManagedServiceWorker
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
    "DatabaseWorker",
    "SearchWorker",
    "WORKER_CLASSES",
]
