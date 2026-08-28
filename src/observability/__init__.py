"""
Pure Python Observability Package (Zero-External-Dependency).
Provides W3C Trace Context propagation, OpenTelemetry OTLP tracing, OpenInference GenAI conventions,
and ephemeral process flush management.
"""

import os
from typing import Optional

from observability.export import (
    BatchSpanProcessor,
    FileSpanExporter,
    FlushManager,
    OTLPJsonSpanExporter,
    build_otlp_payload,
    span_to_otlp_json_dict,
)
from observability.openinference import (
    OpenInferenceConventions,
    OpenInferenceSpanKind,
    record_llm_span,
    record_retriever_span,
    record_tool_span,
    set_openinference_kind,
)
from observability.propagation import (
    SpanContext,
    TraceContextPropagator,
    generate_span_id,
    generate_trace_id,
)
from observability.trace import (
    Span,
    Status,
    StatusCode,
    Tracer,
    TracerProvider,
    get_current_span,
    get_current_span_context,
    get_tracer,
    get_tracer_provider,
    set_tracer_provider,
)


def init_observability(
    service_name: str = "arxiv-security-papers",
    otlp_endpoint: Optional[str] = None,
    enable_file_export: bool = True,
    enable_lifecycle_flush: bool = True,
) -> TracerProvider:
    """
    Initializes global TracerProvider with OTLP / File exporters and registers
    atexit / signal lifecycle flush hooks for ephemeral execution.
    """
    provider = TracerProvider()

    # 1. Local File Exporter
    if enable_file_export:
        file_exp = FileSpanExporter()
        provider.add_span_processor(
            BatchSpanProcessor(file_exp, max_export_batch_size=64)
        )

    # 2. Remote OTLP HTTP Exporter (if endpoint configured)
    endpoint = otlp_endpoint or os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT")
    if endpoint:
        otlp_exp = OTLPJsonSpanExporter(endpoint=endpoint, service_name=service_name)
        provider.add_span_processor(BatchSpanProcessor(otlp_exp))

    set_tracer_provider(provider)

    # 3. Lifecycle Flush Hooks (atexit / SIGTERM)
    if enable_lifecycle_flush:
        FlushManager.register_lifecycle(provider)

    return provider


__all__ = [
    "Span",
    "Tracer",
    "TracerProvider",
    "SpanContext",
    "Status",
    "StatusCode",
    "get_tracer",
    "get_tracer_provider",
    "set_tracer_provider",
    "get_current_span",
    "get_current_span_context",
    "TraceContextPropagator",
    "generate_trace_id",
    "generate_span_id",
    "OTLPJsonSpanExporter",
    "FileSpanExporter",
    "BatchSpanProcessor",
    "FlushManager",
    "build_otlp_payload",
    "span_to_otlp_json_dict",
    "OpenInferenceSpanKind",
    "OpenInferenceConventions",
    "set_openinference_kind",
    "record_llm_span",
    "record_retriever_span",
    "record_tool_span",
    "init_observability",
]
