import atexit
import json
import os
import signal
import sys
import threading
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Union

from observability.trace import Span, StatusCode, TracerProvider, get_tracer_provider


def _convert_seq_value(val: Union[list, tuple]) -> Dict[str, Any]:
    return {"arrayValue": {"values": [_convert_attr_value(v) for v in val]}}


def _convert_attr_value(val: Any) -> Dict[str, Any]:
    """Converts a Python value into OTLP AnyValue JSON schema."""
    if isinstance(val, bool):
        return {"boolValue": val}
    if isinstance(val, int):
        return {"intValue": str(val)}
    if isinstance(val, float):
        return {"doubleValue": val}
    if isinstance(val, (list, tuple)):
        return _convert_seq_value(val)
    return {"stringValue": str(val)}


def _build_status_dict(span: Span) -> Dict[str, Any]:
    """Builds OTLP Status dictionary from Span status."""
    if span.status.status_code == StatusCode.OK:
        return {"code": 1}
    if span.status.status_code == StatusCode.ERROR:
        res: Dict[str, Any] = {"code": 2}
        if span.status.description:
            res["message"] = span.status.description
        return res
    return {"code": 0}


def _format_span_events(events: List[Any]) -> List[Dict[str, Any]]:
    return [
        {
            "timeUnixNano": str(ev.timestamp_ns),
            "name": ev.name,
            "attributes": [
                {"key": k, "value": _convert_attr_value(v)}
                for k, v in ev.attributes.items()
            ],
        }
        for ev in events
    ]


def _format_span_attributes(attributes: Dict[str, Any]) -> List[Dict[str, Any]]:
    return [{"key": k, "value": _convert_attr_value(v)} for k, v in attributes.items()]


def span_to_otlp_json_dict(
    span: Span, service_name: str = "app-service"
) -> Dict[str, Any]:
    """
    Serializes a single Span into OpenTelemetry Protocol (OTLP) HTTP JSON v1/traces format.
    Ref: https://opentelemetry.io/docs/specs/otlp/#json-protobuf-encoding
    """
    span_dict: Dict[str, Any] = {
        "traceId": span.context.trace_id,
        "spanId": span.context.span_id,
        "name": span.name,
        "kind": 1 if span.kind == "INTERNAL" else 2,
        "startTimeUnixNano": str(span.start_time_ns),
        "endTimeUnixNano": str(span.end_time_ns or span.start_time_ns),
        "attributes": _format_span_attributes(span.attributes),
        "events": _format_span_events(span.events),
        "status": _build_status_dict(span),
    }
    parent_id = getattr(span.parent_context, "span_id", None)
    if parent_id:
        span_dict["parentSpanId"] = parent_id

    return span_dict


def build_otlp_payload(
    spans: List[Span], service_name: str = "app-service"
) -> Dict[str, Any]:
    """Wraps spans into standard ResourceSpans / ScopeSpans envelope."""
    span_dicts = [span_to_otlp_json_dict(s, service_name) for s in spans]
    return {
        "resourceSpans": [
            {
                "resource": {
                    "attributes": [
                        {
                            "key": "service.name",
                            "value": {"stringValue": service_name},
                        },
                        {
                            "key": "telemetry.sdk.language",
                            "value": {"stringValue": "python"},
                        },
                        {
                            "key": "telemetry.sdk.name",
                            "value": {"stringValue": "pure-opentelemetry"},
                        },
                    ]
                },
                "scopeSpans": [
                    {
                        "scope": {"name": "pure-tracer"},
                        "spans": span_dicts,
                    }
                ],
            }
        ]
    }


def _get_raw_otlp_endpoint(endpoint: Optional[str]) -> str:
    if endpoint:
        return endpoint
    return os.environ.get("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT") or os.environ.get(
        "OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318/v1/traces"
    )


def _resolve_otlp_endpoint(endpoint: Optional[str]) -> str:
    """Resolves and normalizes the OTLP traces HTTP endpoint."""
    resolved = _get_raw_otlp_endpoint(endpoint)
    if not resolved.endswith("/v1/traces") and not resolved.endswith(":4318"):
        sep = "" if resolved.endswith("/") else "/"
        return f"{resolved}{sep}v1/traces"
    return resolved


def _resolve_otlp_headers(custom_headers: Optional[Dict[str, str]]) -> Dict[str, str]:
    """Parses environment OTEL_EXPORTER_OTLP_HEADERS into header dict."""
    headers = {"Content-Type": "application/json"}
    if custom_headers:
        headers.update(custom_headers)
    env_headers = os.environ.get("OTEL_EXPORTER_OTLP_HEADERS", "")
    if env_headers:
        for item in env_headers.split(","):
            if "=" in item:
                k, v = item.split("=", 1)
                headers[k.strip()] = v.strip()
    return headers


class OTLPJsonSpanExporter:
    """Exports span batches over HTTP POST in OTLP JSON (v1/traces) format."""

    def __init__(
        self,
        endpoint: Optional[str] = None,
        headers: Optional[Dict[str, str]] = None,
        service_name: str = "app-service",
        timeout: int = 10,
    ) -> None:
        self.endpoint = _resolve_otlp_endpoint(endpoint)
        self.service_name = service_name or os.environ.get(
            "OTEL_SERVICE_NAME", "app-service"
        )
        self.headers = _resolve_otlp_headers(headers)
        self.timeout = timeout

    def export(self, spans: List[Span]) -> bool:
        """Sends batch payload to OTLP collector via urllib."""
        if not spans:
            return True

        payload = build_otlp_payload(spans, self.service_name)
        data = json.dumps(payload).encode("utf-8")

        try:
            req = urllib.request.Request(
                self.endpoint,
                data=data,
                headers=self.headers,
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return resp.status in (200, 202)
        except Exception as e:
            sys.stderr.write(
                f"[Observability] OTLP export warning to {self.endpoint}: {e}\n"
            )
            return False

    def shutdown(self) -> None:
        pass


class FileSpanExporter:
    """Exports span batches to local outputs/logs/otlp_traces.jsonl for persistent inspection."""

    def __init__(self, file_path: Optional[str] = None) -> None:
        self.file_path = file_path or os.path.join(
            "outputs", "logs", "otlp_traces.jsonl"
        )
        os.makedirs(os.path.dirname(os.path.abspath(self.file_path)), exist_ok=True)
        self._lock = threading.Lock()

    def export(self, spans: List[Span]) -> bool:
        if not spans:
            return True
        payload = build_otlp_payload(spans)
        with self._lock:
            with open(self.file_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(payload, ensure_ascii=False) + "\n")
        return True

    def shutdown(self) -> None:
        pass


class BatchSpanProcessor:
    """Batches spans in memory and flushes periodically or on threshold."""

    def __init__(
        self,
        exporter: Any,
        max_queue_size: int = 2048,
        max_export_batch_size: int = 512,
        schedule_delay_millis: int = 5000,
    ) -> None:
        self.exporter = exporter
        self.max_queue_size = max_queue_size
        self.max_export_batch_size = max_export_batch_size
        self.schedule_delay_millis = schedule_delay_millis
        self._queue: List[Span] = []
        self._lock = threading.Lock()
        self._shutdown = False

    def on_end(self, span: Span) -> None:
        if self._shutdown:
            return
        with self._lock:
            if len(self._queue) < self.max_queue_size:
                self._queue.append(span)
            if len(self._queue) >= self.max_export_batch_size:
                batch = self._queue[:]
                self._queue.clear()
                self.exporter.export(batch)

    def force_flush(self, timeout_millis: int = 5000) -> bool:
        """Synchronously drains in-memory queue to prevent telemetry loss."""
        with self._lock:
            if not self._queue:
                return True
            batch = self._queue[:]
            self._queue.clear()
        return bool(self.exporter.export(batch))

    def shutdown(self) -> None:
        self._shutdown = True
        self.force_flush()
        if hasattr(self.exporter, "shutdown"):
            self.exporter.shutdown()


class FlushManager:
    """Manages graceful telemetry flushing on process termination (atexit / SIGTERM / SIGINT)."""

    _registered = False
    _lock = threading.Lock()

    @classmethod
    def _bind_signals(cls, handler: Any) -> None:
        for sig in (signal.SIGTERM, signal.SIGINT):
            try:
                signal.signal(sig, handler)
            except (ValueError, AttributeError):
                pass

    @classmethod
    def register_lifecycle(cls, provider: Optional[TracerProvider] = None) -> None:
        """Hooks atexit and POSIX signal handlers to guarantee zero telemetry loss in CI/CD."""
        with cls._lock:
            if cls._registered:
                return
            cls._registered = True

            target_provider = provider or get_tracer_provider()

            def _shutdown_hook() -> None:
                target_provider.force_flush()
                target_provider.shutdown()

            atexit.register(_shutdown_hook)

            def _signal_handler(signum: int, frame: Any) -> None:
                _shutdown_hook()
                sys.exit(128 + signum)

            cls._bind_signals(_signal_handler)
