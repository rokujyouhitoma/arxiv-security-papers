#!/usr/bin/env python3
"""
Structured Security Audit Logging Module.
Provides standardized, typed security audit event recording with automatic credential masking.
Zero external runtime dependencies (Python standard library only).
"""

import json
import threading
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

from ..secrets.manager import detect_exposed_secrets, mask_secret


class SecurityEventType(str, Enum):
    """Enumeration of standardized security audit event types."""

    AUTH_LOGIN = "auth.login"
    AUTH_FAILURE = "auth.failure"
    RBAC_VIOLATION = "rbac.violation"
    SSRF_BLOCKED = "ssrf.blocked"
    SECRET_LEAK_DETECTED = "secret.leak_detected"
    INGEST_QUOTA_EXCEEDED = "ingest.quota_exceeded"
    RATE_LIMIT_TRIGGERED = "ratelimit.triggered"
    CIRCUIT_STATE_CHANGE = "circuit.state_change"
    GENERAL_SECURITY = "security.general"


class EventSeverity(str, Enum):
    """Event severity levels."""

    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class EventStatus(str, Enum):
    """Outcome status of the audited action."""

    SUCCESS = "SUCCESS"
    FAILURE = "FAILURE"
    BLOCKED = "BLOCKED"


def _mask_scalar_val(val: Any) -> Any:
    """Masks string scalar if it resembles a secret."""
    if isinstance(val, str):
        findings = detect_exposed_secrets(val, check_entropy=False)
        if findings:
            return mask_secret(val)
    return val


def _mask_sensitive_dict(data: Dict[str, Any]) -> Dict[str, Any]:
    """Recursively masks known credential fields or high-entropy values in dict."""
    masked: Dict[str, Any] = {}
    sensitive_keys = {"password", "secret", "token", "api_key", "key", "authorization"}
    for k, v in data.items():
        if isinstance(v, dict):
            masked[k] = _mask_sensitive_dict(v)
        elif k.lower() in sensitive_keys and isinstance(v, str):
            masked[k] = mask_secret(v)
        else:
            masked[k] = _mask_scalar_val(v)
    return masked


@dataclass(frozen=True)
class SecurityAuditEvent:
    """Standardized Security Audit Event Record."""

    event_type: str
    severity: str
    actor: str
    action: str
    target_resource: str
    status: str
    event_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    client_ip: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Converts event to dictionary with sanitized, masked metadata."""
        d = asdict(self)
        d["metadata"] = _mask_sensitive_dict(self.metadata)
        return d

    def to_json(self) -> str:
        """Serializes masked audit event to JSON string."""
        return json.dumps(self.to_dict(), sort_keys=True, separators=(",", ":"))


def _norm_attr(val: Any) -> Any:
    return getattr(val, "value", val)


def _matches_type(e: SecurityAuditEvent, event_type: Optional[str]) -> bool:
    """Checks if event matches event_type."""
    return event_type is None or _norm_attr(e.event_type) == _norm_attr(event_type)


def _matches_severity(e: SecurityAuditEvent, severity: Optional[str]) -> bool:
    """Checks if event matches severity."""
    return severity is None or _norm_attr(e.severity) == _norm_attr(severity)


def _filter_events(
    events: List[SecurityAuditEvent],
    event_type: Optional[str],
    severity: Optional[str],
) -> List[SecurityAuditEvent]:
    """Filters events by type and severity."""
    return [
        e
        for e in events
        if _matches_type(e, event_type) and _matches_severity(e, severity)
    ]


class SecurityAuditLogger:
    """
    In-memory thread-safe security audit log sink.
    Records structured events and supports querying by type and severity.
    """

    def __init__(self, max_buffer_size: int = 10000) -> None:
        self.max_buffer_size = max_buffer_size
        self._events: List[SecurityAuditEvent] = []
        self._lock = threading.Lock()

    def log(self, event: SecurityAuditEvent) -> None:
        """Appends an event to the audit trail, maintaining buffer bounds."""
        with self._lock:
            if len(self._events) >= self.max_buffer_size:
                self._events.pop(0)
            self._events.append(event)

    def record(
        self,
        event_type: str,
        severity: str,
        actor: str,
        action: str,
        target_resource: str,
        status: str,
        client_ip: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> SecurityAuditEvent:
        """Convenience factory and logging helper."""
        event = SecurityAuditEvent(
            event_type=event_type,
            severity=severity,
            actor=actor,
            action=action,
            target_resource=target_resource,
            status=status,
            client_ip=client_ip,
            metadata=metadata if metadata is not None else {},
        )
        self.log(event)
        return event

    def get_events(
        self,
        event_type: Optional[str] = None,
        severity: Optional[str] = None,
    ) -> List[SecurityAuditEvent]:
        """Filters logged events by optional type and severity."""
        with self._lock:
            return _filter_events(self._events, event_type, severity)

    def clear(self) -> None:
        """Clears all logged events."""
        with self._lock:
            self._events.clear()

    def __len__(self) -> int:
        with self._lock:
            return len(self._events)

    def __bool__(self) -> bool:
        return True
