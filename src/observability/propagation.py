"""
W3C Trace Context (traceparent / tracestate) Propagation Module.
Standard-library only implementation conforming to W3C Recommendation (2021).
Format: 00-{trace_id:32hex}-{span_id:16hex}-{trace_flags:2hex}
"""

import os
import re
import secrets
from dataclasses import dataclass
from typing import Any, Dict, Optional

TRACEPARENT_REGEX = re.compile(
    r"^([0-9a-f]{2})-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$"
)


@dataclass(frozen=True)
class SpanContext:
    """Immutable W3C compliant trace identification context."""

    trace_id: str
    span_id: str
    trace_flags: str = "01"  # '01' means sampled
    is_remote: bool = False

    @property
    def is_valid(self) -> bool:
        return (
            len(self.trace_id) == 32
            and len(self.span_id) == 16
            and self.trace_id != "0" * 32
            and self.span_id != "0" * 16
        )

    def to_traceparent(self) -> str:
        """Formats the context into standard W3C traceparent header string."""
        return f"00-{self.trace_id}-{self.span_id}-{self.trace_flags}"


def generate_trace_id() -> str:
    """Generates a random 128-bit (32 hex characters) trace ID."""
    return secrets.token_hex(16)


def generate_span_id() -> str:
    """Generates a random 64-bit (16 hex characters) span ID."""
    return secrets.token_hex(8)


class TraceContextPropagator:
    """Propagates W3C Trace Context across process and network boundaries."""

    @staticmethod
    def extract(carrier: Optional[Dict[str, Any]] = None) -> Optional[SpanContext]:
        """
        Extracts SpanContext from carrier dictionary or TRACEPARENT environment variable.
        """
        traceparent_val = None
        if carrier:
            # Case-insensitive lookup in headers
            for k, v in carrier.items():
                if k.lower() in ("traceparent", "http_traceparent"):
                    traceparent_val = str(v).strip()
                    break

        if not traceparent_val:
            traceparent_val = os.environ.get("TRACEPARENT", "").strip()

        if not traceparent_val:
            return None

        match = TRACEPARENT_REGEX.match(traceparent_val)
        if not match:
            return None

        version, trace_id, parent_id, flags = match.groups()
        if version == "ff" or trace_id == "0" * 32 or parent_id == "0" * 16:
            return None

        return SpanContext(
            trace_id=trace_id,
            span_id=parent_id,
            trace_flags=flags,
            is_remote=True,
        )

    @staticmethod
    def inject(carrier: Dict[str, Any], context: SpanContext) -> None:
        """Injects W3C traceparent into carrier dictionary."""
        if context and context.is_valid:
            carrier["traceparent"] = context.to_traceparent()
