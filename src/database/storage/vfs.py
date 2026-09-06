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
            with open(path, "wb"):
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

    def __del__(self) -> None:
        try:
            if hasattr(self, "_f") and not self._f.closed:
                self._f.close()
        except Exception:
            pass


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
            if "w" in mode or path not in self._files:
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


class ChaosVFSFile(VFSFile):
    """
    Chaos-injected VFS file handle wrapper for power-loss and I/O fault simulation.
    """

    def __init__(self, target_file: VFSFile, vfs: "ChaosVFS") -> None:
        self._target = target_file
        self._vfs = vfs
        self._lock = threading.RLock()

    def read(self, offset: int, size: int) -> bytes:
        with self._lock:
            self._vfs.stats["reads"] += 1
            return self._target.read(offset, size)

    def write(self, offset: int, data: bytes) -> int:
        with self._lock:
            limit = self._vfs._fail_after_writes
            if limit is not None and self._vfs._write_count >= limit:
                self._vfs.stats["write_failures"] += 1
                raise IOError("ChaosVFS: Simulated sudden power cut during disk write")
            self._vfs._write_count += 1
            self._vfs.stats["writes"] += 1
            return self._target.write(offset, data)

    def truncate(self, size: int) -> None:
        with self._lock:
            self._target.truncate(size)

    def sync(self) -> None:
        with self._lock:
            if self._vfs._fail_on_sync:
                self._vfs.stats["sync_failures"] += 1
                raise IOError("ChaosVFS: Simulated power cut during disk flush (fsync)")
            self._vfs.stats["syncs"] += 1
            self._target.sync()

    def file_size(self) -> int:
        with self._lock:
            return self._target.file_size()

    def close(self) -> None:
        with self._lock:
            self._target.close()


class ChaosVFS(VFS):
    """
    Chaos-injected Virtual File System proxy for testing storage crash resilience.
    """

    def __init__(self, underlying_vfs: Optional[VFS] = None) -> None:
        self._underlying = underlying_vfs or PosixVFS()
        self._fail_after_writes: Optional[int] = None
        self._fail_on_sync: bool = False
        self._write_count: int = 0
        self.stats: Dict[str, int] = {
            "reads": 0,
            "writes": 0,
            "syncs": 0,
            "write_failures": 0,
            "sync_failures": 0,
        }
        self._lock = threading.RLock()

    def set_fail_after_writes(self, count: Optional[int]) -> None:
        """Sets the number of successful writes before raising an IOError."""
        with self._lock:
            self._fail_after_writes = count
            self._write_count = 0

    def set_fail_on_sync(self, enable: bool = True) -> None:
        """Enables or disables simulated crash during fsync()."""
        with self._lock:
            self._fail_on_sync = enable

    def reset_stats(self) -> None:
        """Resets all I/O metrics and failure injection flags."""
        with self._lock:
            self._write_count = 0
            self._fail_after_writes = None
            self._fail_on_sync = False
            for k in self.stats:
                self.stats[k] = 0

    def open(self, path: str, mode: str = "r+b") -> VFSFile:
        underlying_file = self._underlying.open(path, mode=mode)
        return ChaosVFSFile(underlying_file, self)

    def delete(self, path: str) -> bool:
        return self._underlying.delete(path)

    def exists(self, path: str) -> bool:
        return self._underlying.exists(path)


# Global VFS Registry
_VFS_REGISTRY: Dict[str, VFS] = {
    "posix": PosixVFS(),
    "memory": MemoryVFS(),
    "chaos": ChaosVFS(),
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
