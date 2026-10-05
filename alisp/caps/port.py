"""ALisp Managed Port Implementation.

Provides ManagedPort with Byte Budget quotas and in-memory bytevector/string
loopback isolation for sandboxed execution without altering physical disk files.
"""

from __future__ import annotations

from typing import List, Optional, Union

from alisp.caps.base import CapabilityError
from ilisp.port import (
    BinaryInputPort,
    BinaryOutputPort,
    BytesOutputPort,
    Port,
    StringOutputPort,
    TextualInputPort,
    TextualOutputPort,
)
from ilisp.types import Bytevector


class PortQuotaExceededException(CapabilityError):
    """Raised when a ManagedPort exceeds its maximum allocated byte budget."""

    def __init__(
        self,
        message: str = "ManagedPort byte budget quota exceeded",
        transferred: int = 0,
        budget: int = 0,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.transferred = transferred
        self.budget = budget

    def __str__(self) -> str:
        return self.message


class ManagedPortMixin:
    """Mixin tracking byte budgets and in-memory loopback state for ManagedPorts."""

    def __init__(
        self,
        byte_budget: int = 1024 * 1024,
        is_loopback: bool = False,
        virtual_path: Optional[str] = None,
    ) -> None:
        self.byte_budget = byte_budget
        self.bytes_transferred = 0
        self.is_loopback = is_loopback
        self.virtual_path = virtual_path
        self._write_chunks: List[Union[str, bytes]] = []

    def _consume_budget(self, num_bytes: int) -> None:
        if self.bytes_transferred + num_bytes > self.byte_budget:
            raise PortQuotaExceededException(
                f"ManagedPort byte budget exceeded: allowed {self.byte_budget} bytes, "
                f"requested {self.bytes_transferred + num_bytes} bytes",
                transferred=self.bytes_transferred + num_bytes,
                budget=self.byte_budget,
            )
        self.bytes_transferred += num_bytes

    def rollback(self) -> None:
        """Rollback written state during transaction recovery."""
        self._write_chunks.clear()
        self.bytes_transferred = 0


class ManagedTextualOutputPort(TextualOutputPort, ManagedPortMixin):
    """Sandboxed textual output port enforcing byte quotas and loopback isolation."""

    def __init__(
        self,
        inner_port: Optional[TextualOutputPort] = None,
        name: str = "<managed-textual-output-port>",
        byte_budget: int = 1024 * 1024,
        is_loopback: bool = False,
        virtual_path: Optional[str] = None,
    ) -> None:
        TextualOutputPort.__init__(self, name=name)
        ManagedPortMixin.__init__(
            self,
            byte_budget=byte_budget,
            is_loopback=is_loopback,
            virtual_path=virtual_path,
        )
        self.inner_port: Optional[TextualOutputPort] = inner_port

    def write_char(self, ch: str) -> None:
        encoded_len = len(ch.encode("utf-8"))
        self._consume_budget(encoded_len)
        self._write_chunks.append(ch)
        if self.inner_port is not None:
            self.inner_port.write_char(ch)

    def write_string(self, s: str) -> None:
        encoded_len = len(s.encode("utf-8"))
        self._consume_budget(encoded_len)
        self._write_chunks.append(s)
        if self.inner_port is not None:
            self.inner_port.write_string(s)

    def flush(self) -> None:
        if self.inner_port is not None:
            self.inner_port.flush()

    def close(self) -> None:
        super().close()
        if self.inner_port is not None:
            self.inner_port.close()

    def get_content(self) -> str:
        """Retrieve total accumulated string written to the port."""
        if self.inner_port is not None and isinstance(
            self.inner_port, StringOutputPort
        ):
            return self.inner_port.get_string()
        return "".join(self._write_chunks)

    def rollback(self) -> None:
        super().rollback()
        if self.inner_port is not None and isinstance(
            self.inner_port, StringOutputPort
        ):
            self.inner_port._buffer.clear()


class ManagedTextualInputPort(TextualInputPort, ManagedPortMixin):
    """Sandboxed textual input port enforcing read byte budget quotas."""

    def __init__(
        self,
        inner_port: TextualInputPort,
        name: str = "<managed-textual-input-port>",
        byte_budget: int = 1024 * 1024,
        virtual_path: Optional[str] = None,
    ) -> None:
        TextualInputPort.__init__(self, name=name)
        ManagedPortMixin.__init__(
            self,
            byte_budget=byte_budget,
            is_loopback=False,
            virtual_path=virtual_path,
        )
        self.inner_port: TextualInputPort = inner_port

    def read_char(self) -> Optional[str]:
        ch = self.inner_port.read_char()
        if ch is not None:
            self._consume_budget(len(ch.encode("utf-8")))
        return ch

    def peek_char(self) -> Optional[str]:
        return self.inner_port.peek_char()

    def read_line(self) -> Optional[str]:
        line = self.inner_port.read_line()
        if line is not None:
            self._consume_budget(len((line + "\n").encode("utf-8")))
        return line

    def read_string(self, k: int) -> Optional[str]:
        s = self.inner_port.read_string(k)
        if s is not None:
            self._consume_budget(len(s.encode("utf-8")))
        return s

    def char_ready(self) -> bool:
        return self.inner_port.char_ready()

    def close(self) -> None:
        super().close()
        self.inner_port.close()


class ManagedBinaryOutputPort(BinaryOutputPort, ManagedPortMixin):
    """Sandboxed binary output port enforcing byte quotas and loopback isolation."""

    def __init__(
        self,
        inner_port: Optional[BinaryOutputPort] = None,
        name: str = "<managed-binary-output-port>",
        byte_budget: int = 1024 * 1024,
        is_loopback: bool = False,
        virtual_path: Optional[str] = None,
    ) -> None:
        BinaryOutputPort.__init__(self, name=name)
        ManagedPortMixin.__init__(
            self,
            byte_budget=byte_budget,
            is_loopback=is_loopback,
            virtual_path=virtual_path,
        )
        self.inner_port: Optional[BinaryOutputPort] = inner_port

    def write_u8(self, byte: int) -> None:
        self._consume_budget(1)
        self._write_chunks.append(bytes([byte]))
        if self.inner_port is not None:
            self.inner_port.write_u8(byte)

    def write_bytevector(
        self, bv: Bytevector, start: int = 0, end: Optional[int] = None
    ) -> None:
        actual_end = end if end is not None else len(bv.data)
        slice_len = max(0, actual_end - start)
        self._consume_budget(slice_len)
        self._write_chunks.append(bytes(bv.data[start:actual_end]))
        if self.inner_port is not None:
            self.inner_port.write_bytevector(bv, start, end)

    def flush(self) -> None:
        if self.inner_port is not None:
            self.inner_port.flush()

    def close(self) -> None:
        super().close()
        if self.inner_port is not None:
            self.inner_port.close()

    def get_content(self) -> bytes:
        """Retrieve total accumulated bytes written to the port."""
        if self.inner_port is not None and isinstance(self.inner_port, BytesOutputPort):
            return bytes(self.inner_port.get_bytevector().data)
        return b"".join(
            c.encode("utf-8") if isinstance(c, str) else c for c in self._write_chunks
        )

    def rollback(self) -> None:
        super().rollback()
        if self.inner_port is not None and isinstance(self.inner_port, BytesOutputPort):
            self.inner_port._buffer.clear()


class ManagedBinaryInputPort(BinaryInputPort, ManagedPortMixin):
    """Sandboxed binary input port enforcing read byte budget quotas."""

    def __init__(
        self,
        inner_port: BinaryInputPort,
        name: str = "<managed-binary-input-port>",
        byte_budget: int = 1024 * 1024,
        virtual_path: Optional[str] = None,
    ) -> None:
        BinaryInputPort.__init__(self, name=name)
        ManagedPortMixin.__init__(
            self,
            byte_budget=byte_budget,
            is_loopback=False,
            virtual_path=virtual_path,
        )
        self.inner_port: BinaryInputPort = inner_port

    def read_u8(self) -> Optional[int]:
        b = self.inner_port.read_u8()
        if b is not None:
            self._consume_budget(1)
        return b

    def peek_u8(self) -> Optional[int]:
        return self.inner_port.peek_u8()

    def read_bytevector(self, k: int) -> Optional[Bytevector]:
        bv = self.inner_port.read_bytevector(k)
        if bv is not None:
            self._consume_budget(len(bv.data))
        return bv

    def read_bytevector_bang(
        self, bv: Bytevector, start: int = 0, end: Optional[int] = None
    ) -> int:
        read_bytes = self.inner_port.read_bytevector_bang(bv, start, end)
        self._consume_budget(read_bytes)
        return read_bytes

    def u8_ready(self) -> bool:
        return self.inner_port.u8_ready()

    def close(self) -> None:
        super().close()
        self.inner_port.close()


def wrap_managed_port(
    port: Port,
    byte_budget: int = 1024 * 1024,
    is_loopback: bool = False,
    virtual_path: Optional[str] = None,
) -> Port:
    """Wrap an existing ILISP Port into a ManagedPort with byte quota management."""
    if isinstance(port, ManagedPortMixin):
        return port

    if isinstance(port, TextualOutputPort):
        return ManagedTextualOutputPort(
            inner_port=port,
            name=port.name,
            byte_budget=byte_budget,
            is_loopback=is_loopback,
            virtual_path=virtual_path,
        )
    elif isinstance(port, TextualInputPort):
        return ManagedTextualInputPort(
            inner_port=port,
            name=port.name,
            byte_budget=byte_budget,
            virtual_path=virtual_path,
        )
    elif isinstance(port, BinaryOutputPort):
        return ManagedBinaryOutputPort(
            inner_port=port,
            name=port.name,
            byte_budget=byte_budget,
            is_loopback=is_loopback,
            virtual_path=virtual_path,
        )
    elif isinstance(port, BinaryInputPort):
        return ManagedBinaryInputPort(
            inner_port=port,
            name=port.name,
            byte_budget=byte_budget,
            virtual_path=virtual_path,
        )
    return port


def make_loopback_textual_port(
    virtual_path: Optional[str] = None,
    byte_budget: int = 1024 * 1024,
) -> ManagedTextualOutputPort:
    """Create an in-memory loopback textual output port that prevents disk changes."""
    string_port = StringOutputPort(name=f"<loopback-text:{virtual_path or 'mem'}>")
    return ManagedTextualOutputPort(
        inner_port=string_port,
        name=string_port.name,
        byte_budget=byte_budget,
        is_loopback=True,
        virtual_path=virtual_path,
    )


def make_loopback_binary_port(
    virtual_path: Optional[str] = None,
    byte_budget: int = 1024 * 1024,
) -> ManagedBinaryOutputPort:
    """Create an in-memory loopback binary output port that prevents disk changes."""
    bytes_port = BytesOutputPort(name=f"<loopback-binary:{virtual_path or 'mem'}>")
    return ManagedBinaryOutputPort(
        inner_port=bytes_port,
        name=bytes_port.name,
        byte_budget=byte_budget,
        is_loopback=True,
        virtual_path=virtual_path,
    )
