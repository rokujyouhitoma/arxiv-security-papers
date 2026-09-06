#!/usr/bin/env python3
"""
Unit tests for SecurityWSGIMiddleware and Web Gateway Pilot Integration (Issue #161).
"""

from typing import Any, Callable, Dict, Iterable, List, Tuple

from security.audit.event_logger import (
    EventSeverity,
    EventStatus,
    SecurityAuditLogger,
    SecurityEventType,
)
from security.middleware.wsgi import (
    SecurityWSGIMiddleware,
    extract_client_ip,
    is_malformed_path_or_query,
)
from security.ratelimit.limiter import SlidingWindowRateLimiter
from web.gateway.app import application


def simple_dummy_app(
    environ: Dict[str, Any], start_response: Callable[..., Any]
) -> Iterable[bytes]:
    status = "200 OK"
    headers = [("Content-Type", "application/json")]
    start_response(status, headers)
    return [b'{"status":"ok"}']


def make_test_environ(
    method: str = "GET",
    path: str = "/",
    query: str = "",
    remote_addr: str = "127.0.0.1",
    x_forwarded_for: str = "",
) -> Dict[str, Any]:
    env: Dict[str, Any] = {
        "REQUEST_METHOD": method,
        "PATH_INFO": path,
        "QUERY_STRING": query,
        "REMOTE_ADDR": remote_addr,
    }
    if x_forwarded_for:
        env["HTTP_X_FORWARDED_FOR"] = x_forwarded_for
    return env


def test_client_ip_extraction():
    """Verify correct extraction of client IP from headers or REMOTE_ADDR."""
    env1 = make_test_environ(remote_addr="192.168.1.50")
    assert extract_client_ip(env1) == "192.168.1.50"

    env2 = make_test_environ(
        remote_addr="10.0.0.1",
        x_forwarded_for="203.0.113.195, 70.41.3.18, 150.172.238.178",
    )
    assert extract_client_ip(env2) == "203.0.113.195"

    env3 = {}
    assert extract_client_ip(env3) == "127.0.0.1"


def test_path_traversal_detection():
    """Verify traversal patterns and null bytes are recognized as malformed."""
    assert not is_malformed_path_or_query("/api/search", "q=security")
    assert not is_malformed_path_or_query("/dashboard", "")

    # Traversal patterns
    assert is_malformed_path_or_query("/api/../etc/passwd", "")
    assert is_malformed_path_or_query("/api/%2e%2e/secret", "")
    assert is_malformed_path_or_query("/api/search", "file=../../config")
    assert is_malformed_path_or_query("/api/test/..", "")

    # Null bytes & control chars
    assert is_malformed_path_or_query("/api/\x00test", "")
    assert is_malformed_path_or_query("/api/test", "param=%00malicious")
    assert is_malformed_path_or_query("/api/\x07beep", "")


def test_security_headers_injection():
    """Verify default security response headers are transparently injected."""
    audit_logger = SecurityAuditLogger()
    middleware = SecurityWSGIMiddleware(
        app=simple_dummy_app,
        audit_logger=audit_logger,
        enable_rate_limiting=False,
    )

    captured_status: List[str] = []
    captured_headers: List[List[Tuple[str, str]]] = []

    def start_response(status: str, headers: List[Tuple[str, str]], exc_info=None):
        captured_status.append(status)
        captured_headers.append(headers)

    env = make_test_environ(path="/api/status")
    res = middleware(env, start_response)
    assert list(res) == [b'{"status":"ok"}']
    assert captured_status[0] == "200 OK"

    header_dict = {k.lower(): v for k, v in captured_headers[0]}
    assert "strict-transport-security" in header_dict
    assert header_dict["x-content-type-options"] == "nosniff"
    assert header_dict["x-frame-options"] == "DENY"
    assert "content-security-policy" in header_dict
    assert header_dict["content-type"] == "application/json"


def test_malformed_path_blocking_and_audit():
    """Verify path traversal request is blocked with 400 and logged to audit logger."""
    audit_logger = SecurityAuditLogger()
    middleware = SecurityWSGIMiddleware(
        app=simple_dummy_app,
        audit_logger=audit_logger,
    )

    captured_status: List[str] = []
    captured_headers: List[List[Tuple[str, str]]] = []

    def start_response(status: str, headers: List[Tuple[str, str]], exc_info=None):
        captured_status.append(status)
        captured_headers.append(headers)

    env = make_test_environ(
        path="/api/data/../../etc/passwd", remote_addr="198.51.100.22"
    )
    res = middleware(env, start_response)

    assert captured_status[0] == "400 Bad Request"
    assert b"Bad Request" in b"".join(res)

    # Verify audit event
    events = audit_logger.get_events(
        event_type=SecurityEventType.GENERAL_SECURITY,
        severity=EventSeverity.WARNING,
    )
    assert len(events) == 1
    event = events[0]
    assert event.action == "REQUEST_BLOCKED_MALFORMED"
    assert event.status == EventStatus.BLOCKED
    assert event.client_ip == "198.51.100.22"


def test_rate_limiting_enforcement_and_audit():
    """Verify rate limiter blocks excess requests with 429 and logs audit event."""
    audit_logger = SecurityAuditLogger()
    limiter = SlidingWindowRateLimiter()
    middleware = SecurityWSGIMiddleware(
        app=simple_dummy_app,
        rate_limiter=limiter,
        audit_logger=audit_logger,
        default_rate_limit=3,
        default_window_seconds=10.0,
    )

    client_ip = "203.0.113.88"
    captured_status: List[str] = []

    def start_response(status: str, headers: List[Tuple[str, str]], exc_info=None):
        captured_status.append(status)

    env = make_test_environ(path="/api/resource", remote_addr=client_ip)

    # First 3 requests succeed
    for i in range(3):
        captured_status.clear()
        res = list(middleware(env, start_response))
        assert captured_status[0] == "200 OK"
        assert res == [b'{"status":"ok"}']

    # 4th request is rate-limited
    captured_status.clear()
    blocked_res = list(middleware(env, start_response))
    assert captured_status[0] == "429 Too Many Requests"
    assert b"Rate limit exceeded" in b"".join(blocked_res)

    # Verify rate limit audit event
    rl_events = audit_logger.get_events(
        event_type=SecurityEventType.RATE_LIMIT_TRIGGERED
    )
    assert len(rl_events) == 1
    assert rl_events[0].action == "RATE_LIMIT_EXCEEDED"
    assert rl_events[0].client_ip == client_ip


def test_gateway_pilot_integration():
    """Verify web gateway application is wrapped with SecurityWSGIMiddleware and handles routes."""
    assert isinstance(application, SecurityWSGIMiddleware)

    captured_status: List[str] = []
    captured_headers: List[List[Tuple[str, str]]] = []

    def start_response(status: str, headers: List[Tuple[str, str]], exc_info=None):
        captured_status.append(status)
        captured_headers.append(headers)

    # 1. Normal request to gateway route
    env = make_test_environ(method="GET", path="/api/stats")
    _ = list(application(env, start_response))
    assert captured_status[0] == "200 OK"

    header_dict = {k.lower(): v for k, v in captured_headers[0]}
    assert "strict-transport-security" in header_dict
    assert header_dict["x-content-type-options"] == "nosniff"

    # 2. Malformed traversal attack to gateway
    captured_status.clear()
    bad_env = make_test_environ(method="GET", path="/api/stats/../../../secret")
    _bad = list(application(bad_env, start_response))
    assert captured_status[0] == "400 Bad Request"
    assert _bad  # consumed
