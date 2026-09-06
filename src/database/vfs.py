#!/usr/bin/env python3
"""Backward-compatibility shim for database.storage.vfs."""

from .storage.vfs import (
    VFS,
    ChaosVFS,
    ChaosVFSFile,
    MemoryVFS,
    MemoryVFSFile,
    PosixVFS,
    PosixVFSFile,
    VFSFile,
    get_vfs,
    register_vfs,
)

__all__ = [
    "ChaosVFS",
    "ChaosVFSFile",
    "MemoryVFS",
    "MemoryVFSFile",
    "PosixVFS",
    "PosixVFSFile",
    "VFS",
    "VFSFile",
    "get_vfs",
    "register_vfs",
]
