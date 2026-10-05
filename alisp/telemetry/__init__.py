"""ALisp Telemetry and Audit Subsystem.

Exports structured JSON Lines audit logging and W3C TraceContext propagation.
"""

from __future__ import annotations

from alisp.telemetry.audit import (
    DEFAULT_AUDIT_LOG_PATH,
    AuditEventType,
    AuditLogger,
    generate_span_id,
    generate_trace_id,
    get_audit_logger,
    get_current_span_id,
    get_current_trace_id,
    record_audit_event,
    with_trace,
)

__all__ = [
    "DEFAULT_AUDIT_LOG_PATH",
    "AuditEventType",
    "AuditLogger",
    "generate_span_id",
    "generate_trace_id",
    "get_audit_logger",
    "get_current_span_id",
    "get_current_trace_id",
    "record_audit_event",
    "with_trace",
]
