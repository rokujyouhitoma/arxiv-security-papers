#!/usr/bin/env python3
"""
HTTP Router and Response Utilities for API Gateway.
Provides CORS, standard HTTP headers, and WSGI response builders.
"""

import json
from typing import Any, Callable, Dict, List, Tuple

CORS_HEADERS: List[Tuple[str, str]] = [
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Methods", "GET, POST, OPTIONS, HEAD"),
    ("Access-Control-Allow-Headers", "Content-Type, Authorization"),
]


def response_json(
    start_response: Callable[..., Any],
    data: Dict[str, Any] | List[Any],
    status: str = "200 OK",
) -> List[bytes]:
    """Generates JSON response for WSGI callable."""
    body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
    ] + CORS_HEADERS
    start_response(status, headers)
    return [body]


def response_html(
    start_response: Callable[..., Any],
    html_content: str,
    status: str = "200 OK",
) -> List[bytes]:
    """Generates HTML response for WSGI callable."""
    body = html_content.encode("utf-8")
    headers = [
        ("Content-Type", "text/html; charset=utf-8"),
        ("Content-Length", str(len(body))),
    ] + CORS_HEADERS
    start_response(status, headers)
    return [body]


def response_bytes(
    start_response: Callable[..., Any],
    body: bytes,
    content_type: str = "application/octet-stream",
    status: str = "200 OK",
) -> List[bytes]:
    """Generates raw bytes response for WSGI callable."""
    headers = [
        ("Content-Type", content_type),
        ("Content-Length", str(len(body))),
    ] + CORS_HEADERS
    start_response(status, headers)
    return [body]


SSE_HEADERS: List[Tuple[str, str]] = [
    ("Content-Type", "text/event-stream; charset=utf-8"),
    ("Cache-Control", "no-cache, no-transform"),
    ("X-Accel-Buffering", "no"),
] + CORS_HEADERS


def response_sse(
    start_response: Callable[..., Any],
    stream_generator: Any,
    status: str = "200 OK",
) -> Any:
    """Generates SSE (Server-Sent Events) streaming response for WSGI callable."""
    start_response(status, list(SSE_HEADERS))
    return stream_generator


def response_error(
    start_response: Callable[..., Any],
    message: str,
    status: str = "400 Bad Request",
) -> List[bytes]:
    """Generates standard error JSON response."""
    return response_json(
        start_response,
        {"status": "error", "message": message},
        status=status,
    )
