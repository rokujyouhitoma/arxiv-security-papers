#!/usr/bin/env python3
"""Backward-compatibility shim for database.storage.buffer_pool."""

from .storage.buffer_pool import BufferFrame, BufferPool2Q, BufferPoolError

__all__ = ["BufferFrame", "BufferPool2Q", "BufferPoolError"]
