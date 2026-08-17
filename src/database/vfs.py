#!/usr/bin/env python3
"""
OS Abstraction Layer (VFS: Virtual File System).
Provides platform-independent, pluggable file I/O, atomic sync, and lock management
for persistent storage, memory-mapped buffers, and testing harnesses.
"""

import abc
import io
import os
import threading
from typing import Dict, Optional


class VFSFile(abc.ABC):
    """Abstract interface for a VFS file handle."""

    @abc.abstractmethod
    def read(self, offset: int, size: int) -> bytes:
        pass

    @abc.abstractmethod
    def write(self, offset: int, data: bytes) -> int:
        pass

    @abc.abstractmethod
    def truncate(self, size: int) -> None:
        pass

    @abc.abstractmethod
    def sync(self) -> None:
        pass

    @abc.abstractmethod
    def file_size(self) -> int:
        pass

    @abc.abstractmethod
    def close(self) -> None:
        pass


class PosixVFSFile(VFSFile):
    """POSIX file handle wrapper."""

    def __init__(self, path: str, mode: str = "r+b") -> None:
        self.path = path
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        if not os.path.exists(path):
            with open(path, "wb") as f:
                pass
        self._f = open(path, mode if "b" in mode else mode + "b")
        self._lock = threading.RLock()

    def read(self, offset: int, size: int) -> bytes:
        with self._lock:
            self._f.seek(offset)
            data = self._f.read(size)
            return bytes(data) if isinstance(data, (bytes, bytearray)) else b""

    def write(self, offset: int, data: bytes) -> int:
        with self._lock:
            self._f.seek(offset)
            written = self._f.write(data)
            self._f.flush()
            return int(written)

    def truncate(self, size: int) -> None:
        with self._lock:
            self._f.truncate(size)
            self._f.flush()

    def sync(self) -> None:
        with self._lock:
            self._f.flush()
            os.fsync(self._f.fileno())

    def file_size(self) -> int:
        with self._lock:
            self._f.seek(0, os.SEEK_END)
            return self._f.tell()

    def close(self) -> None:
        with self._lock:
            if not self._f.closed:
                self._f.close()


class MemoryVFSFile(VFSFile):
    """In-memory file handle backed by byte buffers."""

    def __init__(self, name: str) -> None:
        self.name = name
        self._buffer = io.BytesIO()
        self._lock = threading.RLock()

    def read(self, offset: int, size: int) -> bytes:
        with self._lock:
            self._buffer.seek(offset)
            return self._buffer.read(size)

    def write(self, offset: int, data: bytes) -> int:
        with self._lock:
            self._buffer.seek(offset)
            written = self._buffer.write(data)
            return written

    def truncate(self, size: int) -> None:
        with self._lock:
            self._buffer.truncate(size)

    def sync(self) -> None:
        pass

    def file_size(self) -> int:
        with self._lock:
            return len(self._buffer.getvalue())

    def close(self) -> None:
        pass


class VFS(abc.ABC):
    """Abstract Virtual File System provider."""

    @abc.abstractmethod
    def open(self, path: str, mode: str = "r+b") -> VFSFile:
        pass

    @abc.abstractmethod
    def delete(self, path: str) -> bool:
        pass

    @abc.abstractmethod
    def exists(self, path: str) -> bool:
        pass


class PosixVFS(VFS):
    """Standard OS filesystem implementation."""

    def open(self, path: str, mode: str = "r+b") -> VFSFile:
        return PosixVFSFile(path, mode=mode)

    def delete(self, path: str) -> bool:
        if os.path.exists(path):
            os.remove(path)
            return True
        return False

    def exists(self, path: str) -> bool:
        return os.path.exists(path)


class MemoryVFS(VFS):
    """In-memory virtual filesystem for fast caching and testing."""

    def __init__(self) -> None:
        self._files: Dict[str, MemoryVFSFile] = {}
        self._lock = threading.RLock()

    def open(self, path: str, mode: str = "r+b") -> VFSFile:
        with self._lock:
            if path not in self._files:
                self._files[path] = MemoryVFSFile(path)
            return self._files[path]

    def delete(self, path: str) -> bool:
        with self._lock:
            if path in self._files:
                del self._files[path]
                return True
            return False

    def exists(self, path: str) -> bool:
        with self._lock:
            return path in self._files


# Global VFS Registry
_VFS_REGISTRY: Dict[str, VFS] = {
    "posix": PosixVFS(),
    "memory": MemoryVFS(),
}
_DEFAULT_VFS: str = "posix"


def get_vfs(name: Optional[str] = None) -> VFS:
    """Returns registered VFS implementation (default: 'posix')."""
    vfs_name = name or _DEFAULT_VFS
    if vfs_name not in _VFS_REGISTRY:
        raise ValueError(f"Unknown VFS implementation: '{vfs_name}'")
    return _VFS_REGISTRY[vfs_name]


def register_vfs(name: str, vfs: VFS, make_default: bool = False) -> None:
    """Registers a new VFS implementation."""
    global _DEFAULT_VFS
    _VFS_REGISTRY[name] = vfs
    if make_default:
        _DEFAULT_VFS = name
