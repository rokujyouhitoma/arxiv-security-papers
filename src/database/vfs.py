#!/usr/bin/env python3
"""Backward-compatibility shim for database.storage.vfs."""

from .storage.vfs import (
    VFS,
    MemoryVFS,
    MemoryVFSFile,
    PosixVFS,
    PosixVFSFile,
    VFSFile,
    get_vfs,
    register_vfs,
)

__all__ = [
    "MemoryVFS",
    "MemoryVFSFile",
    "PosixVFS",
    "PosixVFSFile",
    "VFS",
    "VFSFile",
    "get_vfs",
    "register_vfs",
]
