#!/usr/bin/env python3
"""src/cli/stream.py

Universal JSON Lines (JSONL) standard I/O stream handler for management CLI.
Conforms to DSN-01 Section 5.2 and REQ-FR-09 (Unix Composition Protocol).
Pure Python, zero external dependencies.
"""

from __future__ import annotations

import enum
import json
import sys
from typing import Any, Dict, Iterator, Optional, TextIO


class StreamErrorPolicy(str, enum.Enum):
    """Policy for handling invalid JSON or malformed records in stream input."""

    SKIP = "skip"
    ABORT = "abort"


class DiagnosticLogger:
    """Diagnostic logger that guarantees output strictly to stderr.

    Conforms to Unix Rule of Silence and Rule of Separation.
    """

    def __init__(self, stream: Optional[TextIO] = None) -> None:
        self._stream: TextIO = stream if stream is not None else sys.stderr

    def info(self, msg: str) -> None:
        """Writes an info-level diagnostic line to stderr."""
        self._stream.write(f"[INFO] {msg}\n")
        self._stream.flush()

    def warn(self, msg: str) -> None:
        """Writes a warning diagnostic line to stderr."""
        self._stream.write(f"[WARN] {msg}\n")
        self._stream.flush()

    def error(self, msg: str) -> None:
        """Writes an error diagnostic line to stderr."""
        self._stream.write(f"[ERROR] {msg}\n")
        self._stream.flush()

    def banner(self, banner_text: str) -> None:
        """Writes multi-line banner or header text strictly to stderr."""
        self._stream.write(f"{banner_text}\n")
        self._stream.flush()

    def progress(
        self, current: int, total: Optional[int] = None, prefix: str = ""
    ) -> None:
        """Renders an inline progress counter strictly on stderr."""
        if total is not None and total > 0:
            pct = (current / total) * 100.0
            msg = f"{prefix} [{current}/{total}] ({pct:.1f}%)\r"
        else:
            msg = f"{prefix} [{current} records]\r"
        self._stream.write(msg)
        self._stream.flush()


class StreamReader:
    """Line-by-line JSONL streaming reader from stdin or any text stream."""

    def __init__(
        self,
        stream: Optional[TextIO] = None,
        on_error: StreamErrorPolicy = StreamErrorPolicy.ABORT,
        logger: Optional[DiagnosticLogger] = None,
    ) -> None:
        self._stream: TextIO = stream if stream is not None else sys.stdin
        self._on_error: StreamErrorPolicy = on_error
        self._logger: DiagnosticLogger = (
            logger if logger is not None else DiagnosticLogger()
        )
        self._read_count: int = 0
        self._error_count: int = 0

    @property
    def is_piped(self) -> bool:
        """Returns True if the underlying stream is connected to a pipe or file."""
        return not self._stream.isatty()

    @property
    def read_count(self) -> int:
        """Number of successfully decoded JSON records read so far."""
        return self._read_count

    @property
    def error_count(self) -> int:
        """Number of malformed or skipped lines encountered."""
        return self._error_count

    def _handle_error(self, line_num: int, err: Exception) -> None:
        """Handles record parsing error according to policy."""
        self._error_count += 1
        if self._on_error == StreamErrorPolicy.ABORT:
            self._logger.error(f"Stream decode error at line {line_num}: {err}")
            raise ValueError(f"Stream decode error at line {line_num}: {err}") from err
        self._logger.warn(f"Skipping malformed stream line {line_num}: {err}")

    def _parse_line(self, line_num: int, clean: str) -> Optional[Dict[str, Any]]:
        """Parses a single JSON line into a dict, delegating error handling."""
        try:
            record = json.loads(clean)
            if not isinstance(record, dict):
                raise ValueError(
                    f"Line {line_num}: JSON record must be a dict (got {type(record).__name__})"
                )
            self._read_count += 1
            return record
        except Exception as err:
            self._handle_error(line_num, err)
            return None

    def iter_records(self) -> Iterator[Dict[str, Any]]:
        """Yields parsed JSON dictionary records line by line."""
        line_num = 0
        for line in self._stream:
            line_num += 1
            clean = line.strip()
            if not clean:
                continue
            record = self._parse_line(line_num, clean)
            if record is not None:
                yield record

    def __iter__(self) -> Iterator[Dict[str, Any]]:
        return self.iter_records()


class StreamWriter:
    """Line-by-line JSONL streaming writer to stdout or any text stream with flush."""

    def __init__(self, stream: Optional[TextIO] = None) -> None:
        self._stream: TextIO = stream if stream is not None else sys.stdout
        self._written_count: int = 0

    @property
    def written_count(self) -> int:
        """Number of JSON records flushed to stdout."""
        return self._written_count

    def write_record(self, record: Dict[str, Any]) -> None:
        """Serializes and flushes a single JSON dictionary record followed by a newline."""
        serialized = json.dumps(record, ensure_ascii=False)
        self._stream.write(f"{serialized}\n")
        self._stream.flush()
        self._written_count += 1

    def write_raw(self, text: str) -> None:
        """Writes raw string and flushes (useful for Markdown stream or end summaries)."""
        self._stream.write(text)
        self._stream.flush()
