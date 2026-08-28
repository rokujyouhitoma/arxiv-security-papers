#!/usr/bin/env python3
"""Backward-compatibility shim for database.transaction.lock_manager."""

from .transaction.lock_manager import (
    DeadlockError,
    LockGrant,
    LockManager,
    LockMode,
    WaitForGraph,
    is_compatible,
)

__all__ = [
    "DeadlockError",
    "LockGrant",
    "LockManager",
    "LockMode",
    "WaitForGraph",
    "is_compatible",
]
