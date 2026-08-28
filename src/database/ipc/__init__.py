#!/usr/bin/env python3
"""IPC and Client Interface Subpackage."""

from .client import DatabaseClient, VectorDBClient
from .driver import Connection, Cursor, DatabaseError, connect
from .protocol import VectorDBProtocolError, VectorDBProtocolHandler
from .service import DatabaseLifecycleHook, DatabaseService

__all__ = [
    "Connection",
    "Cursor",
    "DatabaseClient",
    "DatabaseError",
    "DatabaseLifecycleHook",
    "DatabaseService",
    "VectorDBClient",
    "VectorDBProtocolError",
    "VectorDBProtocolHandler",
    "connect",
]
