"""
Unit tests for Pure Python OpenTelemetry tracing and OTLP serialization.
"""

import json
import os
import tempfile

from observability import (
    BatchSpanProcessor,
    FileSpanExporter,
    StatusCode,
    TracerProvider,
    build_otlp_payload,
    get_current_span,
)


def test_span_lifecycle_and_context_nesting():
    provider = TracerProvider()
    tracer = provider.get_tracer("test.tracer")

    with tracer.start_as_current_span("parent_span") as parent:
        parent.set_attribute("dataset.target", "cs.CR")
        assert get_current_span() is parent

        with tracer.start_as_current_span("child_span") as child:
            child.set_attribute("http.status_code", 200)
            assert get_current_span() is child
            assert child.parent_context == parent.context
            assert child.context.trace_id == parent.context.trace_id
            assert child.context.span_id != parent.context.span_id

        assert get_current_span() is parent

    assert parent.end_time_ns is not None
    assert parent.is_recording() is False


def test_span_exception_recording():
    provider = TracerProvider()
    tracer = provider.get_tracer("test.tracer")

    span = tracer.start_span("failing_operation")
    try:
        raise ValueError("Network timeout connecting to arXiv")
    except ValueError as e:
        span.record_exception(e)
    span.end()

    assert span.status.status_code == StatusCode.ERROR
    assert "Network timeout" in (span.status.description or "")
    assert len(span.events) == 1
    assert span.events[0].name == "exception"
    assert span.events[0].attributes["exception.type"] == "ValueError"


def test_otlp_json_serialization():
    provider = TracerProvider()
    tracer = provider.get_tracer("test.tracer")

    span = tracer.start_span("llm_call")
    span.set_attribute("llm.model_name", "gpt-4o-mini")
    span.set_attribute("llm.token_count", 42)
    span.set_attribute("tags", ["security", "pqc"])
    span.end()

    payload = build_otlp_payload([span], service_name="test-service")
    assert "resourceSpans" in payload
    resource = payload["resourceSpans"][0]["resource"]
    assert any(
        a["key"] == "service.name" and a["value"]["stringValue"] == "test-service"
        for a in resource["attributes"]
    )
    scope_spans = payload["resourceSpans"][0]["scopeSpans"][0]["spans"]
    assert len(scope_spans) == 1
    assert scope_spans[0]["name"] == "llm_call"
    assert scope_spans[0]["traceId"] == span.context.trace_id


def test_file_span_exporter_and_flush():
    with tempfile.TemporaryDirectory() as tmpdir:
        log_file = os.path.join(tmpdir, "traces.jsonl")
        exporter = FileSpanExporter(file_path=log_file)
        processor = BatchSpanProcessor(exporter, max_export_batch_size=1)

        provider = TracerProvider()
        provider.add_span_processor(processor)
        tracer = provider.get_tracer("file.test")

        with tracer.start_as_current_span("persisted_span") as s:
            s.set_attribute("key", "value")

        provider.force_flush()

        assert os.path.exists(log_file)
        with open(log_file, "r", encoding="utf-8") as f:
            lines = f.readlines()
        assert len(lines) >= 1
        data = json.loads(lines[0])
        assert "resourceSpans" in data
