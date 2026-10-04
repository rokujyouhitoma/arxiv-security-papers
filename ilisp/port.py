"""R7RS Input and Output Ports System for ILISP.

This module provides standard textual ports, string ports, file ports,
dynamic current ports management, and port predicates conforming to R7RS-small.
"""

from __future__ import annotations

import io
import sys
from contextvars import ContextVar
from typing import Any, BinaryIO, Callable, Optional, TextIO, Union

from ilisp.types import EOF, Bytevector, EOFType, is_eof_object


class Port:
    """Abstract base class for all ILISP ports."""

    __slots__ = ("name", "is_input", "is_output", "is_textual", "is_binary", "is_open")

    def __init__(
        self,
        name: str = "<port>",
        is_input: bool = False,
        is_output: bool = False,
        is_textual: bool = True,
        is_binary: bool = False,
    ) -> None:
        self.name: str = name
        self.is_input: bool = is_input
        self.is_output: bool = is_output
        self.is_textual: bool = is_textual
        self.is_binary: bool = is_binary
        self.is_open: bool = True

    def close(self) -> None:
        """Close the port."""
        self.is_open = False

    def __repr__(self) -> str:
        direction = (
            "input" if self.is_input else ("output" if self.is_output else "closed")
        )
        status = "open" if self.is_open else "closed"
        return f"#<{self.__class__.__name__} {self.name} {direction} {status}>"


class TextualInputPort(Port):
    """Abstract base class for textual input ports."""

    def __init__(self, name: str = "<input-port>") -> None:
        super().__init__(name=name, is_input=True, is_output=False, is_textual=True)

    def read_char(self) -> Optional[str]:
        """Read and return next character, or None on EOF."""
        raise NotImplementedError

    def peek_char(self) -> Optional[str]:
        """Peek next character without consuming it, or None on EOF."""
        raise NotImplementedError

    def read_line(self) -> Optional[str]:
        """Read a line (excluding terminating newline), or None on EOF."""
        raise NotImplementedError

    def read_string(self, k: int) -> Optional[str]:
        """Read up to k characters, or None on EOF."""
        raise NotImplementedError

    def char_ready(self) -> bool:
        """Return True if a character is ready to be read without blocking."""
        return self.is_open


class TextualOutputPort(Port):
    """Abstract base class for textual output ports."""

    def __init__(self, name: str = "<output-port>") -> None:
        super().__init__(name=name, is_input=False, is_output=True, is_textual=True)

    def write_char(self, ch: str) -> None:
        """Write a single character to the port."""
        raise NotImplementedError

    def write_string(self, s: str) -> None:
        """Write a string to the port."""
        raise NotImplementedError

    def flush(self) -> None:
        """Flush any pending buffered output."""
        pass


class StringInputPort(TextualInputPort):
    """Textual input port reading from an in-memory string."""

    __slots__ = ("text", "pos")

    def __init__(self, text: str, name: str = "<string-input>") -> None:
        super().__init__(name=name)
        self.text: str = text
        self.pos: int = 0

    def read_char(self) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self.pos < len(self.text):
            ch = self.text[self.pos]
            self.pos += 1
            return ch
        return None

    def peek_char(self) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self.pos < len(self.text):
            return self.text[self.pos]
        return None

    def read_line(self) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self.pos >= len(self.text):
            return None
        newline_idx = self.text.find("\n", self.pos)
        if newline_idx == -1:
            line = self.text[self.pos :]
            self.pos = len(self.text)
            return line
        line = self.text[self.pos : newline_idx]
        self.pos = newline_idx + 1
        if line.endswith("\r"):
            line = line[:-1]
        return line

    def read_string(self, k: int) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self.pos >= len(self.text):
            return None
        end_pos = min(self.pos + k, len(self.text))
        result = self.text[self.pos : end_pos]
        self.pos = end_pos
        return result


class StringOutputPort(TextualOutputPort):
    """Textual output port writing to an in-memory string buffer."""

    __slots__ = ("_buf",)

    def __init__(self, name: str = "<string-output>") -> None:
        super().__init__(name=name)
        self._buf: io.StringIO = io.StringIO()

    def write_char(self, ch: str) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        self._buf.write(ch)

    def write_string(self, s: str) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        self._buf.write(s)

    def get_string(self) -> str:
        """Return accumulated string content."""
        return self._buf.getvalue()

    def flush(self) -> None:
        pass

    def close(self) -> None:
        super().close()


class FileInputPort(TextualInputPort):
    """Textual input port reading from a filesystem file."""

    __slots__ = ("_file", "_peek_buf")

    def __init__(self, filepath: str, encoding: str = "utf-8") -> None:
        super().__init__(name=filepath)
        self._file: TextIO = open(filepath, "r", encoding=encoding)
        self._peek_buf: Optional[str] = None

    def read_char(self) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self._peek_buf is not None:
            ch = self._peek_buf
            self._peek_buf = None
            return ch
        ch = self._file.read(1)
        return ch if ch else None

    def peek_char(self) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self._peek_buf is not None:
            return self._peek_buf
        ch = self._file.read(1)
        if ch:
            self._peek_buf = ch
            return ch
        return None

    def read_line(self) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        chars: list[str] = []
        if self._peek_buf is not None:
            ch = self._peek_buf
            self._peek_buf = None
            if ch == "\n":
                return ""
            if ch != "\r":
                chars.append(ch)

        line = self._file.readline()
        if not line and not chars:
            return None
        line = "".join(chars) + line
        if line.endswith("\n"):
            line = line[:-1]
        if line.endswith("\r"):
            line = line[:-1]
        return line

    def read_string(self, k: int) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        chars: list[str] = []
        remaining = k
        if self._peek_buf is not None:
            chars.append(self._peek_buf)
            self._peek_buf = None
            remaining -= 1
        if remaining > 0:
            part = self._file.read(remaining)
            if part:
                chars.append(part)
        if not chars:
            return None
        return "".join(chars)

    def close(self) -> None:
        if self.is_open:
            self._file.close()
            super().close()


class FileOutputPort(TextualOutputPort):
    """Textual output port writing to a filesystem file."""

    __slots__ = ("_file",)

    def __init__(self, filepath: str, encoding: str = "utf-8") -> None:
        super().__init__(name=filepath)
        self._file: TextIO = open(filepath, "w", encoding=encoding)

    def write_char(self, ch: str) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        self._file.write(ch)

    def write_string(self, s: str) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        self._file.write(s)

    def flush(self) -> None:
        if self.is_open:
            self._file.flush()

    def close(self) -> None:
        if self.is_open:
            self.flush()
            self._file.close()
            super().close()


class StandardInputPort(TextualInputPort):
    """Textual input port wrapping sys.stdin."""

    __slots__ = ("_peek_buf",)

    def __init__(self) -> None:
        super().__init__(name="<stdin>")
        self._peek_buf: Optional[str] = None

    def read_char(self) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self._peek_buf is not None:
            ch = self._peek_buf
            self._peek_buf = None
            return ch
        ch = sys.stdin.read(1)
        return ch if ch else None

    def peek_char(self) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self._peek_buf is not None:
            return self._peek_buf
        ch = sys.stdin.read(1)
        if ch:
            self._peek_buf = ch
            return ch
        return None

    def read_line(self) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        chars: list[str] = []
        if self._peek_buf is not None:
            ch = self._peek_buf
            self._peek_buf = None
            if ch == "\n":
                return ""
            if ch != "\r":
                chars.append(ch)

        line = sys.stdin.readline()
        if not line and not chars:
            return None
        line = "".join(chars) + line
        if line.endswith("\n"):
            line = line[:-1]
        if line.endswith("\r"):
            line = line[:-1]
        return line

    def read_string(self, k: int) -> Optional[str]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        chars: list[str] = []
        remaining = k
        if self._peek_buf is not None:
            chars.append(self._peek_buf)
            self._peek_buf = None
            remaining -= 1
        if remaining > 0:
            part = sys.stdin.read(remaining)
            if part:
                chars.append(part)
        if not chars:
            return None
        return "".join(chars)

    def close(self) -> None:
        self.is_open = False


class StandardOutputPort(TextualOutputPort):
    """Textual output port wrapping sys.stdout."""

    def __init__(self) -> None:
        super().__init__(name="<stdout>")

    def write_char(self, ch: str) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        sys.stdout.write(ch)

    def write_string(self, s: str) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        sys.stdout.write(s)

    def flush(self) -> None:
        if self.is_open:
            sys.stdout.flush()

    def close(self) -> None:
        self.is_open = False


class StandardErrorPort(TextualOutputPort):
    """Textual output port wrapping sys.stderr."""

    def __init__(self) -> None:
        super().__init__(name="<stderr>")

    def write_char(self, ch: str) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        sys.stderr.write(ch)

    def write_string(self, s: str) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        sys.stderr.write(s)

    def flush(self) -> None:
        if self.is_open:
            sys.stderr.flush()

    def close(self) -> None:
        self.is_open = False


# Default ports
DEFAULT_STDIN: TextualInputPort = StandardInputPort()
DEFAULT_STDOUT: TextualOutputPort = StandardOutputPort()
DEFAULT_STDERR: TextualOutputPort = StandardErrorPort()

# Dynamic current ports (context-local)
_cv_current_input: ContextVar[TextualInputPort] = ContextVar(
    "current_input_port", default=DEFAULT_STDIN
)
_cv_current_output: ContextVar[TextualOutputPort] = ContextVar(
    "current_output_port", default=DEFAULT_STDOUT
)
_cv_current_error: ContextVar[TextualOutputPort] = ContextVar(
    "current_error_port", default=DEFAULT_STDERR
)


def get_current_input_port() -> TextualInputPort:
    """Return current input port."""
    return _cv_current_input.get()


def set_current_input_port(port: TextualInputPort) -> None:
    """Set current input port."""
    if not isinstance(port, TextualInputPort):
        raise TypeError(f"Expected TextualInputPort, got {type(port).__name__}")
    _cv_current_input.set(port)


def get_current_output_port() -> TextualOutputPort:
    """Return current output port."""
    return _cv_current_output.get()


def set_current_output_port(port: TextualOutputPort) -> None:
    """Set current output port."""
    if not isinstance(port, TextualOutputPort):
        raise TypeError(f"Expected TextualOutputPort, got {type(port).__name__}")
    _cv_current_output.set(port)


def get_current_error_port() -> TextualOutputPort:
    """Return current error port."""
    return _cv_current_error.get()


def set_current_error_port(port: TextualOutputPort) -> None:
    """Set current error port."""
    if not isinstance(port, TextualOutputPort):
        raise TypeError(f"Expected TextualOutputPort, got {type(port).__name__}")
    _cv_current_error.set(port)


# --- Port Predicates and Operations ---


def port_p(obj: Any) -> bool:
    """Return True if obj is a Port."""
    return isinstance(obj, Port)


def input_port_p(obj: Any) -> bool:
    """Return True if obj is an input port."""
    return isinstance(obj, Port) and obj.is_input


def output_port_p(obj: Any) -> bool:
    """Return True if obj is an output port."""
    return isinstance(obj, Port) and obj.is_output


def textual_port_p(obj: Any) -> bool:
    """Return True if obj is a textual port."""
    return isinstance(obj, Port) and obj.is_textual


def binary_port_p(obj: Any) -> bool:
    """Return True if obj is a binary port."""
    return isinstance(obj, Port) and obj.is_binary


def port_open_p(obj: Any) -> bool:
    """Return True if obj is an open port."""
    return isinstance(obj, Port) and obj.is_open


def input_port_open_p(obj: Any) -> bool:
    """Return True if obj is an open input port."""
    return input_port_p(obj) and obj.is_open


def output_port_open_p(obj: Any) -> bool:
    """Return True if obj is an open output port."""
    return output_port_p(obj) and obj.is_open


def close_port(port: Port) -> None:
    """Close the specified port."""
    if not isinstance(port, Port):
        raise TypeError(f"close-port: expected Port, got {type(port).__name__}")
    port.close()


def close_input_port(port: Port) -> None:
    """Close the specified input port."""
    if not input_port_p(port):
        raise TypeError(
            f"close-input-port: expected input port, got {type(port).__name__}"
        )
    port.close()


def close_output_port(port: Port) -> None:
    """Close the specified output port."""
    if not output_port_p(port):
        raise TypeError(
            f"close-output-port: expected output port, got {type(port).__name__}"
        )
    port.close()


# --- String Port Operations ---


def open_input_string(text: Any) -> StringInputPort:
    """Create and return a new input port reading from string."""
    from ilisp.types import MutableString

    if isinstance(text, (str, MutableString)):
        return StringInputPort(str(text))
    raise TypeError(f"open-input-string: expected str, got {type(text).__name__}")


def open_output_string() -> StringOutputPort:
    """Create and return a new output port writing to string."""
    return StringOutputPort()


def get_output_string(port: StringOutputPort) -> str:
    """Return the characters accumulated in a string output port."""
    if not isinstance(port, StringOutputPort):
        raise TypeError(
            f"get-output-string: expected StringOutputPort, got {type(port).__name__}"
        )
    return port.get_string()


# --- File Port Operations ---


def open_input_file(filepath: str) -> FileInputPort:
    """Open and return a textual input port for the given file."""
    if not isinstance(filepath, str):
        raise TypeError(
            f"open-input-file: expected str filepath, got {type(filepath).__name__}"
        )
    return FileInputPort(filepath)


def open_output_file(filepath: str) -> FileOutputPort:
    """Open and return a textual output port for the given file."""
    if not isinstance(filepath, str):
        raise TypeError(
            f"open-output-file: expected str filepath, got {type(filepath).__name__}"
        )
    return FileOutputPort(filepath)


def call_with_port(port: Port, proc: Callable[[Port], Any]) -> Any:
    """Call proc with port and ensure port is closed when proc returns or raises."""
    if not isinstance(port, Port):
        raise TypeError(f"call-with-port: expected Port, got {type(port).__name__}")
    try:
        return proc(port)
    finally:
        port.close()


def call_with_input_file(filepath: str, proc: Callable[[FileInputPort], Any]) -> Any:
    """Open file for input, call proc with port, and close file."""
    port = open_input_file(filepath)
    try:
        return proc(port)
    finally:
        port.close()


def call_with_output_file(filepath: str, proc: Callable[[FileOutputPort], Any]) -> Any:
    """Open file for output, call proc with port, and close file."""
    port = open_output_file(filepath)
    try:
        return proc(port)
    finally:
        port.close()


def with_input_from_file(filepath: str, thunk: Callable[[], Any]) -> Any:
    """Temporarily set current input port to file port and execute thunk."""
    port = open_input_file(filepath)
    prev = get_current_input_port()
    set_current_input_port(port)
    try:
        return thunk()
    finally:
        set_current_input_port(prev)
        port.close()


def with_output_to_file(filepath: str, thunk: Callable[[], Any]) -> Any:
    """Temporarily set current output port to file port and execute thunk."""
    port = open_output_file(filepath)
    prev = get_current_output_port()
    set_current_output_port(port)
    try:
        return thunk()
    finally:
        set_current_output_port(prev)
        port.close()


# --- EOF Object and Predicate ---


def eof_object() -> EOFType:
    """Return the EOF object."""
    return EOF


def eof_object_p(obj: Any) -> bool:
    """Return True if obj is an EOF object."""
    return is_eof_object(obj)


# --- Character and Line I/O Operations ---


def read_char(port: Optional[TextualInputPort] = None) -> Any:
    """Read next character from port (default: current input port)."""
    p = port if port is not None else get_current_input_port()
    ch = p.read_char()
    if ch is None:
        return EOF
    from ilisp.types import Char

    return Char(ch)


def peek_char(port: Optional[TextualInputPort] = None) -> Any:
    """Peek next character from port (default: current input port)."""
    p = port if port is not None else get_current_input_port()
    ch = p.peek_char()
    if ch is None:
        return EOF
    from ilisp.types import Char

    return Char(ch)


def read_line(port: Optional[TextualInputPort] = None) -> Any:
    """Read a line from port (default: current input port)."""
    p = port if port is not None else get_current_input_port()
    line = p.read_line()
    return EOF if line is None else line


def read_string(k: int, port: Optional[TextualInputPort] = None) -> Any:
    """Read up to k characters from port (default: current input port)."""
    p = port if port is not None else get_current_input_port()
    res = p.read_string(k)
    return EOF if res is None else res


def char_ready_p(port: Optional[TextualInputPort] = None) -> bool:
    """Return True if port is ready for reading."""
    p = port if port is not None else get_current_input_port()
    return p.char_ready()


def write_char(ch: Any, port: Optional[TextualOutputPort] = None) -> None:
    """Write a character to port (default: current output port)."""
    p = port if port is not None else get_current_output_port()
    val = ch.val if hasattr(ch, "val") else str(ch)
    p.write_char(val)


def write_string(
    s: Any,
    port: Optional[TextualOutputPort] = None,
    start: int = 0,
    end: Optional[int] = None,
) -> None:
    """Write string to port with optional slice [start:end] (default: current output port)."""
    p = port if port is not None else get_current_output_port()
    from ilisp.types import string_val

    val = string_val(s) if hasattr(s, "val") else str(s)
    end_idx = len(val) if end is None else end
    if not (0 <= start <= end_idx <= len(val)):
        raise IndexError(
            f"write-string: invalid range [{start}:{end_idx}] for string of length {len(val)}"
        )
    p.write_string(val[start:end_idx])


def newline(port: Optional[TextualOutputPort] = None) -> None:
    """Write a newline to port (default: current output port)."""
    p = port if port is not None else get_current_output_port()
    p.write_char("\n")
    p.flush()


def flush_output_port(port: Optional[TextualOutputPort] = None) -> None:
    """Flush pending output in port (default: current output port)."""
    p = port if port is not None else get_current_output_port()
    p.flush()


def format_datum(obj: Any, mode: str = "write") -> str:
    """Format Scheme datum into string representation.

    Modes:
      - 'display': Human-readable (unquoted strings, raw characters).
      - 'simple': Machine-readable, directly recursive without datum labels.
      - 'shared': Machine-readable with datum labels for all shared/cyclic structures (#n=, #n#).
      - 'write': Machine-readable with datum labels only for cyclic structures (#n=, #n#).
    """
    from ilisp.types import (
        Bytevector,
        Char,
        Cons,
        ErrorObject,
        MutableString,
        Record,
        Symbol,
        Vector,
        is_null,
        is_pair,
        string_val,
    )

    if mode == "display":
        if isinstance(obj, (str, MutableString)):
            return string_val(obj)
        elif isinstance(obj, Char):
            return obj.val

    # Pass 1: Label allocation for compound structures
    labels: dict[int, int] = {}
    if mode in ("shared", "write"):
        counts: dict[int, int] = {}
        cycles: set[int] = set()
        visiting: set[int] = set()

        def scan(node: Any) -> None:
            if not isinstance(node, (Cons, Vector, Record)):
                return
            nid = id(node)
            if nid in visiting:
                cycles.add(nid)
                counts[nid] = counts.get(nid, 0) + 1
                return
            counts[nid] = counts.get(nid, 0) + 1
            if counts[nid] > 1:
                return  # visited already

            visiting.add(nid)
            if isinstance(node, Cons):
                scan(node.car)
                scan(node.cdr)
            elif isinstance(node, Vector):
                for elem in node.elements:
                    scan(elem)
            elif isinstance(node, Record):
                for slot in node.slots:
                    scan(slot)
            visiting.remove(nid)

        scan(obj)

        target_ids = (
            cycles if mode == "write" else {nid for nid, c in counts.items() if c >= 2}
        )
        label_counter = 1
        assigned_ids: set[int] = set()

        def assign_labels(node: Any) -> None:
            nonlocal label_counter
            if not isinstance(node, (Cons, Vector, Record)):
                return
            nid = id(node)
            if nid in target_ids and nid not in labels:
                labels[nid] = label_counter
                label_counter += 1
            if nid in assigned_ids:
                return
            assigned_ids.add(nid)
            if isinstance(node, Cons):
                assign_labels(node.car)
                assign_labels(node.cdr)
            elif isinstance(node, Vector):
                for elem in node.elements:
                    assign_labels(elem)
            elif isinstance(node, Record):
                for slot in node.slots:
                    assign_labels(slot)

        assign_labels(obj)

    # Pass 2: Output generation
    seen_labels: set[int] = set()

    def format_node(node: Any) -> str:
        if isinstance(node, Symbol):
            if mode == "display":
                return node.name
            name = node.name
            needs_pipe = False
            if len(name) == 0:
                needs_pipe = True
            elif name in (".", "+inf.0", "-inf.0", "+nan.0", "-nan.0"):
                needs_pipe = True
            elif name.lower() in (
                "+nan.0abc",
                "+nan.0",
                "-nan.0",
                "+inf.0",
                "-inf.0",
                "+i",
                "-i",
            ):
                needs_pipe = True
            elif (
                name.startswith(("+", "-", "."))
                and len(name) > 1
                and (name[1].isdigit() or name[1] in (".", "i"))
            ):
                needs_pipe = True
            else:
                try:
                    int(name)
                    needs_pipe = True
                except ValueError:
                    pass
                if not needs_pipe:
                    try:
                        float(name)
                        needs_pipe = True
                    except ValueError:
                        pass
                if not needs_pipe:
                    for ch in name:
                        if ch in " \t\r\n();\"'`|\\#[]{}":
                            needs_pipe = True
                            break
            if needs_pipe:
                escaped = name.replace("\\", "\\\\").replace("|", "\\|")
                return f"|{escaped}|"
            return name
        elif isinstance(node, bool):
            return "#t" if node else "#f"
        elif isinstance(node, int):
            return str(node)
        elif isinstance(node, float):
            import math

            if math.isnan(node):
                return "+nan.0"
            elif math.isinf(node):
                return "+inf.0" if node > 0 else "-inf.0"
            return str(node)
        elif isinstance(node, Char):
            if mode == "display":
                return node.val
            return repr(node)
        elif isinstance(node, (str, MutableString)):
            val = string_val(node)
            if mode == "display":
                return val
            escaped = val.replace("\\", "\\\\").replace('"', '\\"')
            return f'"{escaped}"'
        elif is_null(node):
            return "()"
        elif isinstance(node, Bytevector):
            bytes_str = " ".join(str(b) for b in node.data)
            return f"#u8({bytes_str})"
        elif isinstance(node, ErrorObject):
            return repr(node)

        # Compound objects with potential datum labels
        nid = id(node)
        prefix = ""
        if nid in labels:
            if nid in seen_labels:
                return f"#{labels[nid]}#"
            seen_labels.add(nid)
            prefix = f"#{labels[nid]}="

        if isinstance(node, Vector):
            elems = " ".join(format_node(el) for el in node.elements)
            return f"{prefix}#({elems})"
        elif isinstance(node, Record):
            slots = " ".join(format_node(sl) for sl in node.slots)
            return f"{prefix}#({node.record_type.name} {slots})"
        elif isinstance(node, Cons):
            parts: list[str] = []
            curr: Any = node
            first = True
            visited_in_list: set[int] = set()
            while is_pair(curr):
                curr_id = id(curr)
                if not first and curr_id in labels:
                    parts.append(".")
                    parts.append(format_node(curr))
                    curr = None
                    break
                if curr_id in visited_in_list:
                    # Unlabeled cycle safeguard
                    parts.append(".")
                    parts.append("...")
                    curr = None
                    break
                visited_in_list.add(curr_id)
                first = False
                parts.append(format_node(curr.car))
                curr = curr.cdr
            if curr is not None and not is_null(curr):
                parts.append(".")
                parts.append(format_node(curr))
            return f"{prefix}({' '.join(parts)})"

        return repr(node)

    return format_node(obj)


def display(x: Any, port: Optional[TextualOutputPort] = None) -> None:
    """Display x in human-readable form to port (default: current output port)."""
    p = port if port is not None else get_current_output_port()
    p.write_string(format_datum(x, mode="display"))
    p.flush()


def write_val(x: Any, port: Optional[TextualOutputPort] = None) -> None:
    """Write x in machine-readable form to port with cycle protection (default: current output port)."""
    p = port if port is not None else get_current_output_port()
    p.write_string(format_datum(x, mode="write"))
    p.flush()


def write_simple(x: Any, port: Optional[TextualOutputPort] = None) -> None:
    """Write x without datum labels (default: current output port)."""
    p = port if port is not None else get_current_output_port()
    p.write_string(format_datum(x, mode="simple"))
    p.flush()


def write_shared(x: Any, port: Optional[TextualOutputPort] = None) -> None:
    """Write x with datum labels for all shared or cyclic structures (default: current output port)."""
    p = port if port is not None else get_current_output_port()
    p.write_string(format_datum(x, mode="shared"))
    p.flush()


def read_datum(port: Optional[TextualInputPort] = None) -> Any:
    """Read next S-expression datum from port (default: current input port)."""
    from ilisp.reader import Reader

    p = port if port is not None else get_current_input_port()
    reader = Reader(p)
    return reader.read()


# --- Binary Ports (R7RS 6.13) ---


class BinaryInputPort(Port):
    """Abstract base class for binary input ports."""

    def __init__(self, name: str = "<binary-input-port>") -> None:
        super().__init__(
            name=name,
            is_input=True,
            is_output=False,
            is_textual=False,
            is_binary=True,
        )

    def read_u8(self) -> Optional[int]:
        """Read and return next byte (0-255), or None on EOF."""
        raise NotImplementedError

    def peek_u8(self) -> Optional[int]:
        """Peek next byte without consuming it, or None on EOF."""
        raise NotImplementedError

    def read_bytevector(self, k: int) -> Optional[Bytevector]:
        """Read up to k bytes into a newly allocated Bytevector, or None on EOF."""
        raise NotImplementedError

    def read_bytevector_bang(
        self, bv: Bytevector, start: int = 0, end: Optional[int] = None
    ) -> int:
        """Read bytes directly into existing Bytevector slice."""
        raise NotImplementedError

    def u8_ready(self) -> bool:
        """Return True if an octet is ready for reading."""
        return self.is_open


class BinaryOutputPort(Port):
    """Abstract base class for binary output ports."""

    def __init__(self, name: str = "<binary-output-port>") -> None:
        super().__init__(
            name=name,
            is_input=False,
            is_output=True,
            is_textual=False,
            is_binary=True,
        )

    def write_u8(self, byte: int) -> None:
        """Write a single octet (0-255) to the port."""
        raise NotImplementedError

    def write_bytevector(
        self, bv: Bytevector, start: int = 0, end: Optional[int] = None
    ) -> None:
        """Write bytes from Bytevector to the port."""
        raise NotImplementedError

    def flush(self) -> None:
        """Flush pending buffered binary output."""
        pass


class BytesInputPort(BinaryInputPort):
    """Binary input port reading from in-memory Bytevector or bytes."""

    __slots__ = ("data", "pos")

    def __init__(
        self, data: Union[Bytevector, bytes, bytearray], name: str = "<bytes-input>"
    ) -> None:
        super().__init__(name=name)
        if isinstance(data, Bytevector):
            self.data: bytearray = data.data
        else:
            self.data = bytearray(data)
        self.pos: int = 0

    def read_u8(self) -> Optional[int]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self.pos < len(self.data):
            b = self.data[self.pos]
            self.pos += 1
            return b
        return None

    def peek_u8(self) -> Optional[int]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self.pos < len(self.data):
            return self.data[self.pos]
        return None

    def read_bytevector(self, k: int) -> Optional[Bytevector]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self.pos >= len(self.data):
            return None
        end_pos = min(self.pos + k, len(self.data))
        sub = self.data[self.pos : end_pos]
        self.pos = end_pos
        return Bytevector(sub)

    def read_bytevector_bang(
        self, bv: Bytevector, start: int = 0, end: Optional[int] = None
    ) -> int:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self.pos >= len(self.data):
            return 0
        target_end = len(bv) if end is None else end
        avail = len(self.data) - self.pos
        count = min(target_end - start, avail)
        if count <= 0:
            return 0
        bv.data[start : start + count] = self.data[self.pos : self.pos + count]
        self.pos += count
        return count


class BytesOutputPort(BinaryOutputPort):
    """Binary output port writing to in-memory byte buffer."""

    __slots__ = ("_buf",)

    def __init__(self, name: str = "<bytes-output>") -> None:
        super().__init__(name=name)
        self._buf: io.BytesIO = io.BytesIO()

    def write_u8(self, byte: int) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if not (0 <= byte <= 255):
            raise ValueError(f"write-u8: byte out of range 0..255: {byte}")
        self._buf.write(bytes([byte]))

    def write_bytevector(
        self, bv: Bytevector, start: int = 0, end: Optional[int] = None
    ) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if not isinstance(bv, Bytevector):
            raise TypeError(
                f"write-bytevector: expected Bytevector, got {type(bv).__name__}"
            )
        sub = bv.data[start:end]
        self._buf.write(sub)

    def get_bytevector(self) -> Bytevector:
        """Return accumulated bytes as a Bytevector."""
        return Bytevector(self._buf.getvalue())


class BinaryFileInputPort(BinaryInputPort):
    """Binary input port reading from filesystem file."""

    __slots__ = ("_file", "_peek_buf")

    def __init__(self, filepath: str) -> None:
        super().__init__(name=filepath)
        self._file: BinaryIO = open(filepath, "rb")
        self._peek_buf: Optional[int] = None

    def read_u8(self) -> Optional[int]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self._peek_buf is not None:
            b = self._peek_buf
            self._peek_buf = None
            return b
        data = self._file.read(1)
        return data[0] if data else None

    def peek_u8(self) -> Optional[int]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if self._peek_buf is not None:
            return self._peek_buf
        data = self._file.read(1)
        if data:
            self._peek_buf = data[0]
            return data[0]
        return None

    def read_bytevector(self, k: int) -> Optional[Bytevector]:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        chunks = bytearray()
        rem = k
        if self._peek_buf is not None:
            chunks.append(self._peek_buf)
            self._peek_buf = None
            rem -= 1
        if rem > 0:
            part = self._file.read(rem)
            if part:
                chunks.extend(part)
        if not chunks:
            return None
        return Bytevector(chunks)

    def read_bytevector_bang(
        self, bv: Bytevector, start: int = 0, end: Optional[int] = None
    ) -> int:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        target_end = len(bv) if end is None else end
        needed = target_end - start
        if needed <= 0:
            return 0
        written = 0
        if self._peek_buf is not None:
            bv.data[start] = self._peek_buf
            self._peek_buf = None
            written += 1
            needed -= 1
        if needed > 0:
            data = self._file.read(needed)
            if data:
                bv.data[start + written : start + written + len(data)] = data
                written += len(data)
        return written

    def close(self) -> None:
        if self.is_open:
            self._file.close()
            super().close()


class BinaryFileOutputPort(BinaryOutputPort):
    """Binary output port writing to filesystem file."""

    __slots__ = ("_file",)

    def __init__(self, filepath: str) -> None:
        super().__init__(name=filepath)
        self._file: BinaryIO = open(filepath, "wb")

    def write_u8(self, byte: int) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if not (0 <= byte <= 255):
            raise ValueError(f"write-u8: byte out of range 0..255: {byte}")
        self._file.write(bytes([byte]))

    def write_bytevector(
        self, bv: Bytevector, start: int = 0, end: Optional[int] = None
    ) -> None:
        if not self.is_open:
            raise ValueError("I/O operation on closed port")
        if not isinstance(bv, Bytevector):
            raise TypeError(
                f"write-bytevector: expected Bytevector, got {type(bv).__name__}"
            )
        sub = bv.data[start:end]
        self._file.write(sub)

    def flush(self) -> None:
        if self.is_open:
            self._file.flush()

    def close(self) -> None:
        if self.is_open:
            self.flush()
            self._file.close()
            super().close()


# --- Binary Port Operations ---


def open_binary_input_file(filepath: str) -> BinaryFileInputPort:
    """Open a file as a binary input port."""
    if not isinstance(filepath, str):
        raise TypeError(
            f"open-binary-input-file: expected str, got {type(filepath).__name__}"
        )
    return BinaryFileInputPort(filepath)


def open_binary_output_file(filepath: str) -> BinaryFileOutputPort:
    """Open a file as a binary output port."""
    if not isinstance(filepath, str):
        raise TypeError(
            f"open-binary-output-file: expected str, got {type(filepath).__name__}"
        )
    return BinaryFileOutputPort(filepath)


def open_input_bytevector(bv: Bytevector) -> BytesInputPort:
    """Open an input port reading from a Bytevector."""
    if not isinstance(bv, Bytevector):
        raise TypeError(
            f"open-input-bytevector: expected Bytevector, got {type(bv).__name__}"
        )
    return BytesInputPort(bv)


def open_output_bytevector() -> BytesOutputPort:
    """Open an output port writing to an in-memory byte buffer."""
    return BytesOutputPort()


def get_output_bytevector(port: BytesOutputPort) -> Bytevector:
    """Return the Bytevector accumulated in a BytesOutputPort."""
    if not isinstance(port, BytesOutputPort):
        raise TypeError(
            f"get-output-bytevector: expected BytesOutputPort, got {type(port).__name__}"
        )
    return port.get_bytevector()


def read_u8(port: Optional[BinaryInputPort] = None) -> Any:
    """Read next octet from binary port (default: current input port)."""
    p: Any = port if port is not None else get_current_input_port()
    if not hasattr(p, "read_u8"):
        raise TypeError(f"read-u8: port does not support binary reading: {p!r}")
    res = p.read_u8()
    return EOF if res is None else res


def peek_u8(port: Optional[BinaryInputPort] = None) -> Any:
    """Peek next octet from binary port (default: current input port)."""
    p: Any = port if port is not None else get_current_input_port()
    if not hasattr(p, "peek_u8"):
        raise TypeError(f"peek-u8: port does not support binary reading: {p!r}")
    res = p.peek_u8()
    return EOF if res is None else res


def u8_ready_p(port: Optional[BinaryInputPort] = None) -> bool:
    """Return True if binary port is ready for reading."""
    p: Any = port if port is not None else get_current_input_port()
    if hasattr(p, "u8_ready"):
        return bool(p.u8_ready())
    return False


def write_u8(byte: int, port: Optional[BinaryOutputPort] = None) -> None:
    """Write an octet to binary port (default: current output port)."""
    p: Any = port if port is not None else get_current_output_port()
    if not hasattr(p, "write_u8"):
        raise TypeError(f"write-u8: port does not support binary writing: {p!r}")
    p.write_u8(byte)


def read_bytevector(k: int, port: Optional[BinaryInputPort] = None) -> Any:
    """Read up to k octets from binary port into a Bytevector."""
    p: Any = port if port is not None else get_current_input_port()
    if not hasattr(p, "read_bytevector"):
        raise TypeError(f"read-bytevector: port does not support binary reading: {p!r}")
    res = p.read_bytevector(k)
    return EOF if res is None else res


def read_bytevector_bang(
    bv: Bytevector,
    port: Optional[BinaryInputPort] = None,
    start: int = 0,
    end: Optional[int] = None,
) -> Any:
    """Read octets from binary port directly into existing Bytevector."""
    p: Any = port if port is not None else get_current_input_port()
    if not hasattr(p, "read_bytevector_bang"):
        raise TypeError(
            f"read-bytevector!: port does not support binary reading: {p!r}"
        )
    return p.read_bytevector_bang(bv, start, end)


def write_bytevector(
    bv: Bytevector,
    port: Optional[BinaryOutputPort] = None,
    start: int = 0,
    end: Optional[int] = None,
) -> None:
    """Write Bytevector octets to binary port."""
    p: Any = port if port is not None else get_current_output_port()
    if not hasattr(p, "write_bytevector"):
        raise TypeError(
            f"write-bytevector: port does not support binary writing: {p!r}"
        )
    p.write_bytevector(bv, start, end)
