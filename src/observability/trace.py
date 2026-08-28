"""
Pure Python OpenTelemetry Tracing Core Module.
Zero-external-dependency implementation of Span, Tracer, and TracerProvider.
"""

import contextvars
import threading
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Dict, List, Optional

from observability.propagation import (
    SpanContext,
    TraceContextPropagator,
    generate_span_id,
    generate_trace_id,
)


class StatusCode(str, Enum):
    """Standard OpenTelemetry Span Status Codes."""

    UNSET = "UNSET"
    OK = "OK"
    ERROR = "ERROR"


@dataclass
class Status:
    """Status associated with a span upon completion."""

    status_code: StatusCode = StatusCode.UNSET
    description: Optional[str] = None


@dataclass
class SpanEvent:
    """Individual structured timestamped event or exception within a span."""

    name: str
    timestamp_ns: int
    attributes: Dict[str, Any] = field(default_factory=dict)


class Span:
    """OpenTelemetry compliant distributed tracing Span."""

    def __init__(
        self,
        name: str,
        context: SpanContext,
        parent_context: Optional[SpanContext] = None,
        attributes: Optional[Dict[str, Any]] = None,
        kind: str = "INTERNAL",
        on_end: Optional[Callable[["Span"], None]] = None,
    ) -> None:
        self.name = name
        self.context = context
        self.parent_context = parent_context
        self.attributes: Dict[str, Any] = dict(attributes or {})
        self.kind = kind
        self.start_time_ns = time.time_ns()
        self.end_time_ns: Optional[int] = None
        self.status = Status(StatusCode.UNSET)
        self.events: List[SpanEvent] = []
        self._on_end = on_end
        self._ended = False
        self._lock = threading.Lock()

    def set_attribute(self, key: str, value: Any) -> "Span":
        """Sets an individual attribute key-value pair."""
        with self._lock:
            self.attributes[key] = value
        return self

    def set_attributes(self, attributes: Dict[str, Any]) -> "Span":
        """Sets multiple attribute key-value pairs."""
        with self._lock:
            self.attributes.update(attributes)
        return self

    def set_status(
        self,
        status: Status | StatusCode,
        description: Optional[str] = None,
    ) -> "Span":
        """Sets the span status and optional error description."""
        with self._lock:
            if isinstance(status, StatusCode):
                self.status = Status(status, description)
            else:
                self.status = status
        return self

    def record_exception(
        self,
        exception: BaseException,
        attributes: Optional[Dict[str, Any]] = None,
        escaped: bool = False,
    ) -> "Span":
        """Records an exception event according to OpenTelemetry semantic conventions."""
        attrs: Dict[str, Any] = {
            "exception.type": type(exception).__name__,
            "exception.message": str(exception),
            "exception.escaped": escaped,
        }
        if attributes:
            attrs.update(attributes)
        self.add_event("exception", attributes=attrs)
        self.set_status(StatusCode.ERROR, str(exception))
        return self

    def add_event(
        self, name: str, attributes: Optional[Dict[str, Any]] = None
    ) -> "Span":
        """Adds a named timestamped event."""
        with self._lock:
            self.events.append(
                SpanEvent(
                    name=name,
                    timestamp_ns=time.time_ns(),
                    attributes=dict(attributes or {}),
                )
            )
        return self

    def end(self, end_time_ns: Optional[int] = None) -> None:
        """Ends the span and invokes the export callback."""
        with self._lock:
            if self._ended:
                return
            self._ended = True
            self.end_time_ns = end_time_ns or time.time_ns()

        if self._on_end:
            self._on_end(self)

    def is_recording(self) -> bool:
        return not self._ended

    def __enter__(self) -> "Span":
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        if exc_val is not None:
            self.record_exception(exc_val, escaped=True)
        self.end()


_CURRENT_SPAN: contextvars.ContextVar[Optional[Span]] = contextvars.ContextVar(
    "current_span", default=None
)


class Tracer:
    """Generates and manages spans for a specific instrumentation library."""

    def __init__(
        self,
        instrumentation_name: str,
        provider: "TracerProvider",
    ) -> None:
        self.instrumentation_name = instrumentation_name
        self.provider = provider

    def start_span(
        self,
        name: str,
        context: Optional[SpanContext] = None,
        attributes: Optional[Dict[str, Any]] = None,
        kind: str = "INTERNAL",
    ) -> Span:
        """Starts a new span with explicit or active parent context."""
        parent = context or get_current_span_context()
        if parent and parent.is_valid:
            trace_id = parent.trace_id
            flags = parent.trace_flags
        else:
            trace_id = generate_trace_id()
            flags = "01"

        span_id = generate_span_id()
        span_ctx = SpanContext(trace_id=trace_id, span_id=span_id, trace_flags=flags)

        span = Span(
            name=name,
            context=span_ctx,
            parent_context=parent,
            attributes=attributes,
            kind=kind,
            on_end=self.provider.on_span_end,
        )
        return span

    def start_as_current_span(
        self,
        name: str,
        context: Optional[SpanContext] = None,
        attributes: Optional[Dict[str, Any]] = None,
        kind: str = "INTERNAL",
    ) -> "_SpanContextManager":
        """Context manager setting the created span as active in contextvars."""
        span = self.start_span(
            name=name, context=context, attributes=attributes, kind=kind
        )
        return _SpanContextManager(span)


class _SpanContextManager:
    """Context manager scope maintaining active span in thread-safe contextvars."""

    def __init__(self, span: Span) -> None:
        self.span = span
        self.token: Optional[contextvars.Token[Optional[Span]]] = None

    def __enter__(self) -> Span:
        self.token = _CURRENT_SPAN.set(self.span)
        return self.span

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        if exc_val is not None:
            self.span.record_exception(exc_val, escaped=True)
        self.span.end()
        if self.token:
            _CURRENT_SPAN.reset(self.token)


class TracerProvider:
    """Central provider managing named Tracers and span processors."""

    def __init__(self) -> None:
        self._processors: List[Any] = []
        self._tracers: Dict[str, Tracer] = {}
        self._lock = threading.Lock()

    def add_span_processor(self, processor: Any) -> None:
        """Registers a span processor (BatchSpanProcessor or SimpleSpanProcessor)."""
        with self._lock:
            self._processors.append(processor)

    def get_tracer(self, instrumentation_name: str = "arxiv-security-papers") -> Tracer:
        """Gets or creates a named Tracer instance."""
        with self._lock:
            if instrumentation_name not in self._tracers:
                self._tracers[instrumentation_name] = Tracer(instrumentation_name, self)
            return self._tracers[instrumentation_name]

    def on_span_end(self, span: Span) -> None:
        """Dispatches finished span to all registered processors."""
        for p in self._processors:
            try:
                p.on_end(span)
            except Exception:
                pass

    def force_flush(self, timeout_millis: int = 5000) -> bool:
        """Flushes all processors synchronously."""
        success = True
        for p in self._processors:
            if hasattr(p, "force_flush"):
                try:
                    if not p.force_flush(timeout_millis):
                        success = False
                except Exception:
                    success = False
        return success

    def shutdown(self) -> None:
        """Shuts down all processors."""
        for p in self._processors:
            if hasattr(p, "shutdown"):
                try:
                    p.shutdown()
                except Exception:
                    pass


# Global TracerProvider Registry
_GLOBAL_TRACER_PROVIDER: TracerProvider = TracerProvider()


def get_tracer_provider() -> TracerProvider:
    return _GLOBAL_TRACER_PROVIDER


def set_tracer_provider(provider: TracerProvider) -> None:
    global _GLOBAL_TRACER_PROVIDER
    _GLOBAL_TRACER_PROVIDER = provider


def get_tracer(
    instrumentation_name: str = "arxiv-security-papers",
) -> Tracer:
    """Convenience accessor to get a tracer from global provider."""
    return get_tracer_provider().get_tracer(instrumentation_name)


def get_current_span() -> Optional[Span]:
    """Retrieves current active span in the executing thread/async task."""
    return _CURRENT_SPAN.get()


def get_current_span_context() -> Optional[SpanContext]:
    """Retrieves current span's SpanContext or extracts from environment."""
    span = get_current_span()
    if span:
        return span.context
    return TraceContextPropagator.extract()
