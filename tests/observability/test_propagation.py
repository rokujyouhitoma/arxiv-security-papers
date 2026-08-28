"""
Unit tests for W3C Trace Context propagation.
"""

from observability.propagation import (
    SpanContext,
    TraceContextPropagator,
    generate_span_id,
    generate_trace_id,
)


def test_generate_ids():
    trace_id = generate_trace_id()
    span_id = generate_span_id()
    assert len(trace_id) == 32
    assert len(span_id) == 16
    assert all(c in "0123456789abcdef" for c in trace_id)
    assert all(c in "0123456789abcdef" for c in span_id)


def test_span_context_w3c_formatting():
    ctx = SpanContext(
        trace_id="4bf92f3577b34da6a3ce929d0e0e4736",
        span_id="00f067aa0ba902b7",
        trace_flags="01",
    )
    assert ctx.is_valid
    assert (
        ctx.to_traceparent()
        == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    )


def test_trace_context_extraction_from_carrier():
    carrier = {"Traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"}
    ctx = TraceContextPropagator.extract(carrier)
    assert ctx is not None
    assert ctx.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736"
    assert ctx.span_id == "00f067aa0ba902b7"
    assert ctx.trace_flags == "01"
    assert ctx.is_remote is True


def test_trace_context_extraction_from_env(monkeypatch):
    monkeypatch.setenv(
        "TRACEPARENT",
        "00-abcdef0123456789abcdef0123456789-1234567890abcdef-00",
    )
    ctx = TraceContextPropagator.extract()
    assert ctx is not None
    assert ctx.trace_id == "abcdef0123456789abcdef0123456789"
    assert ctx.span_id == "1234567890abcdef"
    assert ctx.trace_flags == "00"


def test_trace_context_injection():
    ctx = SpanContext(
        trace_id="4bf92f3577b34da6a3ce929d0e0e4736",
        span_id="00f067aa0ba902b7",
        trace_flags="01",
    )
    carrier = {}
    TraceContextPropagator.inject(carrier, ctx)
    assert (
        carrier["traceparent"]
        == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    )
