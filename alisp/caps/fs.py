"""ALisp FileSystem Capability (fs-cap).

Implements capability-based file system access control, strict path prefix
whitelisting, permission attenuation, and loopback virtualization.
"""

from __future__ import annotations

import os
from typing import Any, List, Optional, Sequence

from alisp.caps.base import AccessDeniedException, Capability
from alisp.caps.port import (
    make_loopback_binary_port,
    make_loopback_textual_port,
    wrap_managed_port,
)
from ilisp.evaluator import _apply_procedure
from ilisp.port import (
    BinaryFileInputPort,
    BinaryFileOutputPort,
    FileInputPort,
    FileOutputPort,
    Port,
    close_port,
)
from ilisp.types import Procedure


def normalize_path(path: str) -> str:
    """Resolve and normalize path to an absolute canonical path."""
    return os.path.abspath(os.path.expanduser(path))


def is_subpath(target: str, base: str) -> bool:
    """Check if target path is identical to or within the directory base."""
    target = os.path.normpath(target)
    base = os.path.normpath(base)
    if target == base:
        return True
    base_prefix = base if base.endswith(os.sep) else base + os.sep
    return target.startswith(base_prefix)


class FileSystemCapability(Capability):
    """Capability governing file system read and write authority."""

    name = "fs-cap"

    def __init__(
        self,
        allowed_read_paths: Optional[Sequence[str]] = None,
        allowed_write_paths: Optional[Sequence[str]] = None,
        loopback_unauthorized_writes: bool = True,
        byte_budget: int = 1024 * 1024,
    ) -> None:
        self.allowed_read_paths: List[str] = [
            normalize_path(p) for p in (allowed_read_paths or [])
        ]
        self.allowed_write_paths: List[str] = [
            normalize_path(p) for p in (allowed_write_paths or [])
        ]
        self.loopback_unauthorized_writes = loopback_unauthorized_writes
        self.byte_budget = byte_budget
        self.created_ports: List[Port] = []

    def is_read_allowed(self, path: str) -> bool:
        """Return True if path is permitted for read access under this capability."""
        norm = normalize_path(path)
        return any(is_subpath(norm, base) for base in self.allowed_read_paths)

    def is_write_allowed(self, path: str) -> bool:
        """Return True if path is permitted for physical write access."""
        norm = normalize_path(path)
        return any(is_subpath(norm, base) for base in self.allowed_write_paths)

    def check_read(self, path: str) -> str:
        """Assert read permission for path, returning normalized path or raising exception."""
        norm = normalize_path(path)
        if not self.is_read_allowed(norm):
            raise AccessDeniedException(
                f"Read access denied for path: '{path}' under fs-cap "
                f"(allowed: {self.allowed_read_paths})"
            )
        return norm

    def check_write(self, path: str) -> str:
        """Assert write permission for path, returning normalized path or raising exception."""
        norm = normalize_path(path)
        if not self.is_write_allowed(norm):
            raise AccessDeniedException(
                f"Write access denied for path: '{path}' under fs-cap "
                f"(allowed: {self.allowed_write_paths})"
            )
        return norm

    def attenuate(
        self,
        allowed_read_paths: Optional[Sequence[str]] = None,
        allowed_write_paths: Optional[Sequence[str]] = None,
        loopback_unauthorized_writes: Optional[bool] = None,
        byte_budget: Optional[int] = None,
    ) -> FileSystemCapability:
        """Derive an attenuated child FileSystemCapability with equal or narrower scope."""
        # Validate read paths: all child read paths must be covered by parent
        if allowed_read_paths is not None:
            norm_read = [normalize_path(p) for p in allowed_read_paths]
            for p in norm_read:
                if not any(
                    is_subpath(p, parent_p) for parent_p in self.allowed_read_paths
                ):
                    raise AccessDeniedException(
                        f"Cannot attenuate fs-cap: read path '{p}' is not permitted by parent"
                    )
            new_read = norm_read
        else:
            new_read = list(self.allowed_read_paths)

        # Validate write paths: all child write paths must be covered by parent
        if allowed_write_paths is not None:
            norm_write = [normalize_path(p) for p in allowed_write_paths]
            for p in norm_write:
                if not any(
                    is_subpath(p, parent_p) for parent_p in self.allowed_write_paths
                ):
                    raise AccessDeniedException(
                        f"Cannot attenuate fs-cap: write path '{p}' is not permitted by parent"
                    )
            new_write = norm_write
        else:
            new_write = list(self.allowed_write_paths)

        # Byte budget attenuation: child budget <= parent budget
        new_budget = (
            min(self.byte_budget, byte_budget)
            if byte_budget is not None
            else self.byte_budget
        )

        # Loopback cannot be enabled if parent strictly disabled it
        if loopback_unauthorized_writes is not None:
            if not self.loopback_unauthorized_writes and loopback_unauthorized_writes:
                raise AccessDeniedException(
                    "Cannot enable loopback_unauthorized_writes when parent capability forbids it"
                )
            new_loopback = loopback_unauthorized_writes
        else:
            new_loopback = self.loopback_unauthorized_writes

        return FileSystemCapability(
            allowed_read_paths=new_read,
            allowed_write_paths=new_write,
            loopback_unauthorized_writes=new_loopback,
            byte_budget=new_budget,
        )

    def open_input_file(self, path: str) -> Port:
        """Open textual input file with managed byte budget."""
        norm = self.check_read(path)
        inner = FileInputPort(norm)
        port = wrap_managed_port(inner, byte_budget=self.byte_budget, virtual_path=path)
        self.created_ports.append(port)
        return port

    def open_output_file(self, path: str) -> Port:
        """Open textual output file, redirecting to loopback port if unauthorized."""
        norm = normalize_path(path)
        if self.is_write_allowed(norm):
            inner = FileOutputPort(norm)
            port = wrap_managed_port(
                inner, byte_budget=self.byte_budget, virtual_path=path
            )
            self.created_ports.append(port)
            return port
        elif self.loopback_unauthorized_writes:
            port = make_loopback_textual_port(
                virtual_path=path, byte_budget=self.byte_budget
            )
            self.created_ports.append(port)
            return port
        else:
            raise AccessDeniedException(
                f"Write access denied for path: '{path}' under fs-cap "
                f"(allowed: {self.allowed_write_paths})"
            )

    def open_binary_input_file(self, path: str) -> Port:
        """Open binary input file with managed byte budget."""
        norm = self.check_read(path)
        inner = BinaryFileInputPort(norm)
        port = wrap_managed_port(inner, byte_budget=self.byte_budget, virtual_path=path)
        self.created_ports.append(port)
        return port

    def open_binary_output_file(self, path: str) -> Port:
        """Open binary output file, redirecting to loopback port if unauthorized."""
        norm = normalize_path(path)
        if self.is_write_allowed(norm):
            inner = BinaryFileOutputPort(norm)
            port = wrap_managed_port(
                inner, byte_budget=self.byte_budget, virtual_path=path
            )
            self.created_ports.append(port)
            return port
        elif self.loopback_unauthorized_writes:
            port = make_loopback_binary_port(
                virtual_path=path, byte_budget=self.byte_budget
            )
            self.created_ports.append(port)
            return port
        else:
            raise AccessDeniedException(
                f"Binary write access denied for path: '{path}' under fs-cap "
                f"(allowed: {self.allowed_write_paths})"
            )

    def file_exists(self, path: str) -> bool:
        """Check if file exists within allowed read bounds."""
        norm = self.check_read(path)
        return os.path.exists(norm)

    def delete_file(self, path: str) -> None:
        """Delete physical file within allowed write bounds."""
        norm = self.check_write(path)
        if not os.path.exists(norm):
            raise FileNotFoundError(f"File not found: {path}")
        os.remove(norm)

    def call_with_input_file(self, path: str, proc: Any) -> Any:
        port = self.open_input_file(path)
        try:
            if isinstance(proc, Procedure):
                return _apply_procedure(proc, [port])
            elif callable(proc):
                return proc(port)
            else:
                raise TypeError(f"Expected procedure, got {proc!r}")
        finally:
            close_port(port)

    def call_with_output_file(self, path: str, proc: Any) -> Any:
        port = self.open_output_file(path)
        try:
            if isinstance(proc, Procedure):
                return _apply_procedure(proc, [port])
            elif callable(proc):
                return proc(port)
            else:
                raise TypeError(f"Expected procedure, got {proc!r}")
        finally:
            close_port(port)

    def __repr__(self) -> str:
        return (
            f"#<fs-cap read={len(self.allowed_read_paths)} "
            f"write={len(self.allowed_write_paths)} "
            f"loopback={self.loopback_unauthorized_writes}>"
        )
