"""
Unit Tests for AI-Friendly Structured JSON Logging & Sensitive Masking Engine.
Verifies OpenTelemetry/ECS alignment, ISO 8601 formatting, contextvars trace propagation,
and CWE-532 compliant credential/PII masking.
"""

import json
import logging
from typing import Any, Dict

from observability.logging import (
    StructuredJsonFormatter,
    TraceContextFilter,
    configure_logging,
)
from observability.masking import mask_dict, mask_text
from observability.propagation import (
    clear_current_trace_context,
    get_current_trace_id,
    set_current_trace_context,
)


def test_mask_text_credentials_and_pii() -> None:
    # 1. Bearer Token
    raw_bearer = (
        "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz123abc456"
    )
    masked_bearer = mask_text(raw_bearer)
    assert "***MASKED***" in masked_bearer
    assert "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" not in masked_bearer

    # 2. Password & Secret
    raw_pwd = "User login failed: password='SuperSecretPassword123' and api_key=\"ak-live-999888777\""
    masked_pwd = mask_text(raw_pwd)
    assert "password='***MASKED***'" in masked_pwd
    assert 'api_key="***MASKED***"' in masked_pwd
    assert "SuperSecretPassword123" not in masked_pwd

    # 3. Email (PII)
    raw_email = (
        "Contact security officer at admin@example.com or user.test+tag@corp.net"
    )
    masked_email = mask_text(raw_email)
    assert "***MASKED_EMAIL***" in masked_email
    assert "admin@example.com" not in masked_email

    # 4. Credit Card (PAN)
    raw_card = "Processed card 4111-2222-3333-4444 on gateway"
    masked_card = mask_text(raw_card)
    assert "***MASKED_CARD***" in masked_card
    assert "4111-2222-3333-4444" not in masked_card


def test_mask_dict_nested_structures() -> None:
    payload: Dict[str, Any] = {
        "user_id": 42,
        "email": "dev@example.org",
        "secret_token": "my-secret-token-xyz",
        "nested": {
            "password": "NestedPassword456",
            "normal_field": "Hello World",
            "items": ["token: secret-value-12345678", 100],
        },
    }
    masked = mask_dict(payload)
    assert masked["user_id"] == 42
    assert masked["email"] == "***MASKED_EMAIL***"
    assert masked["secret_token"] == "***MASKED***"
    assert masked["nested"]["password"] == "***MASKED***"
    assert masked["nested"]["normal_field"] == "Hello World"
    assert "***MASKED***" in masked["nested"]["items"][0]


def test_structured_json_formatter_standard_fields() -> None:
    formatter = StructuredJsonFormatter(service_name="test-service")
    record = logging.LogRecord(
        name="test.logger",
        level=logging.INFO,
        pathname="/workspace/src/test.py",
        lineno=42,
        msg="Database query executed in %s ms",
        args=("12.5",),
        exc_info=None,
    )
    record.process = 12345
    setattr(record, "trace_id", "c4b8e8f289a14e76b99d3f0e8a719c2a")
    setattr(record, "span_id", "9a14e76b99d3f0e8")
    setattr(record, "event", {"category": "database", "action": "query"})
    setattr(record, "http", {"method": "GET", "path": "/api/test", "status_code": 200})

    output = formatter.format(record)
    data = json.loads(output)

    assert data["level"] == "INFO"
    assert data["service"] == "test-service"
    assert data["logger"] == "test.logger"
    assert data["line"] == 42
    assert data["pid"] == 12345
    assert data["message"] == "Database query executed in 12.5 ms"
    assert data["trace_id"] == "c4b8e8f289a14e76b99d3f0e8a719c2a"
    assert data["span_id"] == "9a14e76b99d3f0e8"
    assert data["event"]["category"] == "database"
    assert data["http"]["status_code"] == 200
    assert "timestamp" in data
    assert data["timestamp"].endswith("Z")


def test_structured_json_formatter_error_block_and_diagnostic() -> None:
    formatter = StructuredJsonFormatter(service_name="test-service")
    try:
        raise ValueError("Invalid dimension size: expected 768")
    except ValueError:
        import sys

        exc_info = sys.exc_info()

    record = logging.LogRecord(
        name="search.engine",
        level=logging.ERROR,
        pathname="/workspace/src/search.py",
        lineno=88,
        msg="Search failed with password=SecretPassword123",
        args=(),
        exc_info=exc_info,
    )
    setattr(
        record,
        "diagnostic",
        {
            "cause": "DIMENSION_MISMATCH",
            "remediation_hint": "Check model config",
        },
    )

    output = formatter.format(record)
    data = json.loads(output)

    assert data["level"] == "ERROR"
    assert "password=***MASKED***" in data["message"]
    assert "error" in data
    assert data["error"]["class"] == "ValueError"
    assert "Invalid dimension size" in data["error"]["message"]
    assert isinstance(data["error"]["stacktrace"], list)
    assert len(data["error"]["stacktrace"]) > 0
    assert data["diagnostic"]["cause"] == "DIMENSION_MISMATCH"


def test_trace_context_filter_and_propagation() -> None:
    clear_current_trace_context()
    assert get_current_trace_id() == ""

    set_current_trace_context(
        trace_id="4bf92f3577b34da6a3ce929d0e0e4736",
        span_id="00f067aa0ba902b7",
    )
    assert get_current_trace_id() == "4bf92f3577b34da6a3ce929d0e0e4736"

    tfilter = TraceContextFilter()
    record = logging.LogRecord(
        name="test.logger",
        level=logging.INFO,
        pathname="test.py",
        lineno=10,
        msg="Test message",
        args=(),
        exc_info=None,
    )
    tfilter.filter(record)
    assert record.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736"
    assert record.span_id == "00f067aa0ba902b7"
    clear_current_trace_context()


def test_configure_logging_integration(tmp_path: Any) -> None:
    log_file = str(tmp_path / "test_app.jsonl")
    logger = configure_logging(
        service_name="test_app",
        log_level="DEBUG",
        log_file=log_file,
        console=False,
    )
    set_current_trace_context("trace1234567890abcdef1234567890ab", "span1234567890ab")
    logger.info("Application initialized with token='secret-token-abcdef123456'")

    with open(log_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    assert len(lines) == 1
    data = json.loads(lines[0])
    assert data["service"] == "test_app"
    assert data["level"] == "INFO"
    assert data["trace_id"] == "trace1234567890abcdef1234567890ab"
    assert "***MASKED***" in data["message"]
    clear_current_trace_context()
