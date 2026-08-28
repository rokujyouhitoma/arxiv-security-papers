#!/usr/bin/env python3
"""Backward-compatibility shim for database.ipc.driver."""

from .ipc.driver import Connection, Cursor, DatabaseError, connect

__all__ = ["Connection", "Cursor", "DatabaseError", "connect"]
