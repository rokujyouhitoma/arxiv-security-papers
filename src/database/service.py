#!/usr/bin/env python3
"""Backward-compatibility shim for database.ipc.service."""

from .ipc.service import DatabaseLifecycleHook, DatabaseService

__all__ = ["DatabaseLifecycleHook", "DatabaseService"]
