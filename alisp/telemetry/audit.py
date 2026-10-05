"""ALisp Audit Telemetry Subsystem.

Provides W3C TraceContext propagation and structured JSON Lines audit logging
to outputs/database/alisp_events.jsonl for security auditing, provenance tracking,
and execution metrics.
"""

from __future__ import annotations

import datetime
import enum
import json
import secrets
import threading
from contextlib import contextmanager
from contextvars import ContextVar
from pathlib import Path
from typing import Any, Callable, Dict, Iterator, List, Optional, Union


class AuditEventType(str, enum.Enum):
    """Standardized event types for ALisp security and execution telemetry."""

    EVAL_START = "EVAL_START"
    EVAL_SUCCESS = "EVAL_SUCCESS"
    CONTRACT_VIOLATION = "CONTRACT_VIOLATION"
    FUEL_EXHAUSTED = "FUEL_EXHAUSTED"
    TIMEOUT = "TIMEOUT"
    ACCESS_DENIED = "ACCESS_DENIED"
    TAINT_LEAK = "TAINT_LEAK"
    PATCH_APPLIED = "PATCH_APPLIED"
    MEMORY_LIMIT_EXCEEDED = "MEMORY_LIMIT_EXCEEDED"
    EXCEPTION = "EXCEPTION"


_current_trace_id: ContextVar[Optional[str]] = ContextVar(
    "_current_trace_id", default=None
)
_current_span_id: ContextVar[Optional[str]] = ContextVar(
    "_current_span_id", default=None
)


def generate_trace_id() -> str:
    """Generate a W3C compliant 32-character hexadecimal Trace ID."""
    return secrets.token_hex(16)


def generate_span_id() -> str:
    """Generate a W3C compliant 16-character hexadecimal Span ID."""
    return secrets.token_hex(8)


def get_current_trace_id() -> Optional[str]:
    """Retrieve the active W3C Trace ID from the current context."""
    return _current_trace_id.get()


def get_current_span_id() -> Optional[str]:
    """Retrieve the active W3C Span ID from the current context."""
    return _current_span_id.get()


@contextmanager
def with_trace(
    trace_id: Optional[str] = None,
    parent_id: Optional[str] = None,
) -> Iterator[str]:
    """Context manager for establishing or propagating a W3C TraceContext scope.

    Yields the active trace_id.
    """
    effective_trace_id = trace_id or _current_trace_id.get() or generate_trace_id()
    new_span_id = generate_span_id()

    token_trace = _current_trace_id.set(effective_trace_id)
    token_span = _current_span_id.set(new_span_id)

    try:
        yield effective_trace_id
    finally:
        _current_trace_id.reset(token_trace)
        _current_span_id.reset(token_span)


DEFAULT_AUDIT_LOG_PATH = (
    Path(__file__).parent.parent.parent / "outputs" / "database" / "alisp_events.jsonl"
)


class AuditLogger:
    """Thread-safe structured audit logger emitting JSON Lines with W3C TraceContext."""

    def __init__(self, log_path: Optional[Union[str, Path]] = None) -> None:
        self.log_path = (
            Path(log_path) if log_path is not None else DEFAULT_AUDIT_LOG_PATH
        )
        self._lock = threading.Lock()
        self._memory_events: List[Dict[str, Any]] = []
        self._listeners: List[Callable[[Dict[str, Any]], None]] = []

    def add_listener(self, listener: Callable[[Dict[str, Any]], None]) -> None:
        """Register a callback invoked whenever an audit event is logged."""
        self._listeners.append(listener)

    def get_memory_events(self) -> List[Dict[str, Any]]:
        """Retrieve in-memory copy of events logged through this instance."""
        return list(self._memory_events)

    def clear_memory_events(self) -> None:
        """Clear recorded in-memory events."""
        self._memory_events.clear()

    def record_event(
        self,
        event_type: Union[AuditEventType, str],
        message: str,
        details: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None,
        span_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Record a structured audit event to outputs/database/alisp_events.jsonl."""
        ev_type_str = (
            event_type.value
            if isinstance(event_type, AuditEventType)
            else str(event_type)
        )
        active_trace = trace_id or get_current_trace_id() or generate_trace_id()
        active_span = span_id or get_current_span_id() or generate_span_id()

        record: Dict[str, Any] = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "trace_id": active_trace,
            "span_id": active_span,
            "event_type": ev_type_str,
            "message": message,
            "details": details or {},
        }

        with self._lock:
            self._memory_events.append(record)
            # Write to disk if log directory is available
            try:
                self.log_path.parent.mkdir(parents=True, exist_ok=True)
                with open(self.log_path, "a", encoding="utf-8") as f:
                    f.write(json.dumps(record, ensure_ascii=False) + "\n")
            except Exception:
                # Telemetry failures must never crash the primary execution
                pass

        for listener in self._listeners:
            try:
                listener(record)
            except Exception:
                pass

        return record


_global_audit_logger: Optional[AuditLogger] = None
_logger_lock = threading.Lock()


def get_audit_logger(log_path: Optional[Union[str, Path]] = None) -> AuditLogger:
    """Retrieve or initialize the global singleton AuditLogger instance."""
    global _global_audit_logger
    with _logger_lock:
        if _global_audit_logger is None:
            _global_audit_logger = AuditLogger(log_path=log_path)
        elif log_path is not None:
            _global_audit_logger.log_path = Path(log_path)
        return _global_audit_logger


def record_audit_event(
    event_type: Union[AuditEventType, str],
    message: str,
    details: Optional[Dict[str, Any]] = None,
    trace_id: Optional[str] = None,
    span_id: Optional[str] = None,
) -> Dict[str, Any]:
    """Helper function to record an audit event via the default AuditLogger."""
    logger = get_audit_logger()
    return logger.record_event(
        event_type=event_type,
        message=message,
        details=details,
        trace_id=trace_id,
        span_id=span_id,
    )
