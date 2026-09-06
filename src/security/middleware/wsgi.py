#!/usr/bin/env python3
"""
PEP 3333 Compliant Unified Security WSGI Middleware.
Provides automated security headers, client IP rate limiting, path traversal guards,
and structured security audit logging for web applications and gateways.
Zero external runtime dependencies (Python standard library only).
"""

from __future__ import annotations

import time
import urllib.parse
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple

from ..audit.event_logger import (
    EventSeverity,
    EventStatus,
    SecurityAuditLogger,
    SecurityEventType,
)
from ..ratelimit.limiter import SlidingWindowRateLimiter, TokenBucketRateLimiter

DEFAULT_SECURITY_HEADERS: Dict[str, str] = {
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Content-Security-Policy": (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline'; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; "
        "connect-src 'self'"
    ),
}


def _has_null_bytes(target: str) -> bool:
    """Checks if string contains literal or percent-encoded null bytes."""
    return "\x00" in target or "%00" in target.lower()


def _has_control_chars(target: str) -> bool:
    """Checks for non-printable ASCII control characters."""
    for ch in target:
        code = ord(ch)
        if code < 32 and ch not in ("\t", "\n", "\r"):
            return True
    return False


def _has_traversal_tokens(decoded: str) -> bool:
    """Detects directory traversal sequences in decoded string."""
    if "../" in decoded or "..\\" in decoded:
        return True
    segments = decoded.split("/")
    return any(seg == ".." for seg in segments)


def _is_suspicious_payload(payload: str) -> bool:
    """Checks if a string payload contains null bytes, control chars, or traversal tokens."""
    if _has_null_bytes(payload) or _has_control_chars(payload):
        return True
    return _has_traversal_tokens(urllib.parse.unquote(payload))


def is_malformed_path_or_query(path: str, query: str) -> bool:
    """Validates that PATH_INFO and QUERY_STRING do not contain traversal or null bytes."""
    return _is_suspicious_payload(path) or _is_suspicious_payload(query)


def _get_forwarded_ip(x_forwarded: Any) -> Optional[str]:
    """Safely extracts leftmost IP from HTTP_X_FORWARDED_FOR header."""
    if not isinstance(x_forwarded, str) or not x_forwarded.strip():
        return None
    first = x_forwarded.split(",")[0].strip()
    return first or None


def extract_client_ip(environ: Dict[str, Any]) -> str:
    """Extracts and sanitizes client IP address from WSGI environ."""
    forwarded = _get_forwarded_ip(environ.get("HTTP_X_FORWARDED_FOR"))
    if forwarded is not None:
        return forwarded
    remote = environ.get("REMOTE_ADDR")
    if isinstance(remote, str) and remote.strip():
        return remote.strip()
    return "127.0.0.1"


def _acquire_generic(limiter: Any, client_ip: str) -> bool:
    """Attempts acquire with key, falling back to parameterless acquire."""
    try:
        return bool(limiter.acquire(client_ip))
    except TypeError:
        return bool(limiter.acquire())


def _check_rate_limit(
    limiter: Any,
    client_ip: str,
    default_rate: int,
    default_window: float,
) -> bool:
    """Evaluates rate limit against limiter instance. Returns True if request is allowed."""
    if limiter is None:
        return True
    if isinstance(limiter, SlidingWindowRateLimiter):
        return limiter.acquire(
            client_ip, max_requests=default_rate, window_seconds=default_window
        )
    if isinstance(limiter, TokenBucketRateLimiter):
        return limiter.acquire(1.0)
    if hasattr(limiter, "acquire"):
        return _acquire_generic(limiter, client_ip)
    return True


def _merge_security_headers(
    existing_headers: List[Tuple[str, str]],
    security_headers: Dict[str, str],
) -> List[Tuple[str, str]]:
    """Injects security headers if not already present (case-insensitive)."""
    existing_lower = {k.lower() for k, _ in existing_headers}
    merged = list(existing_headers)
    for name, value in security_headers.items():
        if name.lower() not in existing_lower:
            merged.append((name, value))
    return merged


class SecurityWSGIMiddleware:
    """
    PEP 3333 compliant WSGI Middleware for automated, transparent security hardening.
    Wraps any WSGI application to enforce security headers, IP rate limiting,
    path traversal rejection, and structured security audit logging.
    """

    def __init__(
        self,
        app: Callable[[Dict[str, Any], Callable[..., Any]], Iterable[bytes]],
        rate_limiter: Optional[Any] = None,
        audit_logger: Optional[SecurityAuditLogger] = None,
        enable_security_headers: bool = True,
        enable_rate_limiting: bool = True,
        enable_path_traversal_guard: bool = True,
        custom_security_headers: Optional[Dict[str, str]] = None,
        default_rate_limit: int = 120,
        default_window_seconds: float = 60.0,
    ) -> None:
        self.app = app
        self.rate_limiter = rate_limiter
        self.audit_logger = (
            audit_logger if audit_logger is not None else SecurityAuditLogger()
        )
        self.enable_security_headers = enable_security_headers
        self.enable_rate_limiting = enable_rate_limiting
        self.enable_path_traversal_guard = enable_path_traversal_guard
        self.default_rate_limit = default_rate_limit
        self.default_window_seconds = default_window_seconds
        self.security_headers = dict(DEFAULT_SECURITY_HEADERS)
        if custom_security_headers:
            self.security_headers.update(custom_security_headers)

    def _is_rate_allowed(self, client_ip: str) -> bool:
        """Helper to invoke configured rate limiter."""
        return _check_rate_limit(
            limiter=self.rate_limiter,
            client_ip=client_ip,
            default_rate=self.default_rate_limit,
            default_window=self.default_window_seconds,
        )

    def _handle_malformed(
        self,
        start_response: Callable[..., Any],
        client_ip: str,
        path: str,
        query: str,
    ) -> List[bytes]:
        """Rejects malformed requests with 400 Bad Request and logs audit event."""
        self.audit_logger.record(
            event_type=SecurityEventType.GENERAL_SECURITY,
            severity=EventSeverity.WARNING,
            actor=client_ip,
            action="REQUEST_BLOCKED_MALFORMED",
            target_resource=path,
            status=EventStatus.BLOCKED,
            client_ip=client_ip,
            metadata={"reason": "Path traversal or control character", "query": query},
        )
        headers = [("Content-Type", "text/plain; charset=utf-8")]
        if self.enable_security_headers:
            headers = _merge_security_headers(headers, self.security_headers)
        start_response("400 Bad Request", headers)
        return [b"Bad Request: Malformed path or query\n"]

    def _handle_rate_limited(
        self,
        start_response: Callable[..., Any],
        client_ip: str,
        path: str,
    ) -> List[bytes]:
        """Rejects throttled requests with 429 Too Many Requests and logs audit event."""
        self.audit_logger.record(
            event_type=SecurityEventType.RATE_LIMIT_TRIGGERED,
            severity=EventSeverity.WARNING,
            actor=client_ip,
            action="RATE_LIMIT_EXCEEDED",
            target_resource=path,
            status=EventStatus.BLOCKED,
            client_ip=client_ip,
            metadata={"client_ip": client_ip},
        )
        headers = [
            ("Content-Type", "text/plain; charset=utf-8"),
            ("Retry-After", str(int(self.default_window_seconds))),
        ]
        if self.enable_security_headers:
            headers = _merge_security_headers(headers, self.security_headers)
        start_response("429 Too Many Requests", headers)
        return [b"Too Many Requests: Rate limit exceeded\n"]

    def _record_access_audit(
        self,
        client_ip: str,
        method: str,
        path: str,
        status: str,
        duration_ms: float,
    ) -> None:
        """Records a structured access audit event."""
        is_success = status.startswith("2") or status.startswith("3")
        event_status = EventStatus.SUCCESS if is_success else EventStatus.FAILURE
        self.audit_logger.record(
            event_type=SecurityEventType.GENERAL_SECURITY,
            severity=EventSeverity.INFO,
            actor=client_ip,
            action=f"HTTP_{method.upper()}",
            target_resource=path,
            status=event_status,
            client_ip=client_ip,
            metadata={
                "status": status,
                "method": method,
                "duration_ms": round(duration_ms, 2),
            },
        )

    def _dispatch_app(
        self,
        environ: Dict[str, Any],
        start_response: Callable[..., Any],
        client_ip: str,
        path: str,
        start_time: float,
    ) -> Iterable[bytes]:
        """Wraps start_response for security headers and executes underlying WSGI app."""
        captured_status: List[str] = ["200 OK"]

        def custom_start_response(
            status: str,
            response_headers: List[Tuple[str, str]],
            exc_info: Any = None,
        ) -> Any:
            captured_status[0] = status
            headers = response_headers
            if self.enable_security_headers:
                headers = _merge_security_headers(headers, self.security_headers)
            return start_response(status, headers, exc_info)

        result = self.app(environ, custom_start_response)
        duration_ms = (time.monotonic() - start_time) * 1000.0
        self._record_access_audit(
            client_ip=client_ip,
            method=str(environ.get("REQUEST_METHOD", "GET")),
            path=path,
            status=captured_status[0],
            duration_ms=duration_ms,
        )
        return result

    def __call__(
        self,
        environ: Dict[str, Any],
        start_response: Callable[..., Any],
    ) -> Iterable[bytes]:
        """PEP 3333 entrypoint."""
        client_ip = extract_client_ip(environ)
        path = str(environ.get("PATH_INFO", "/"))
        query = str(environ.get("QUERY_STRING", ""))
        start_time = time.monotonic()

        if self.enable_path_traversal_guard and is_malformed_path_or_query(path, query):
            return self._handle_malformed(start_response, client_ip, path, query)

        if self.enable_rate_limiting and not self._is_rate_allowed(client_ip):
            return self._handle_rate_limited(start_response, client_ip, path)

        return self._dispatch_app(environ, start_response, client_ip, path, start_time)
