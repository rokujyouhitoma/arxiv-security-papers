#!/usr/bin/env python3
"""Backward-compatibility shim for database.storage.storage."""

from .storage.storage import VectorStorage, VectorStorageSecurityError

__all__ = ["VectorStorage", "VectorStorageSecurityError"]
