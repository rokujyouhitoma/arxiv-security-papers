#!/usr/bin/env python3
"""
API Gateway and Network Layer for arXiv Security Papers.
Provides WSGI application router, HTTP handlers, query logging, and CORS middleware.
"""

from typing import Any

from .app import WSGIApplication, app, application, get_gateway_wsgi_app, run_web_server
from .handlers import GatewayHandlers
from .logger import WORKSPACE_DIR, get_workspace_dir, log_query
from .router import (
    CORS_HEADERS,
    response_bytes,
    response_error,
    response_html,
    response_json,
)


def __getattr__(name: str) -> Any:
    if name == "VECTOR_ENGINE":
        return get_gateway_wsgi_app().handlers.vector_engine
    raise AttributeError(f"module '{__name__}' has no attribute '{name}'")


__all__ = [
    "WSGIApplication",
    "application",
    "app",
    "run_web_server",
    "get_gateway_wsgi_app",
    "GatewayHandlers",
    "log_query",
    "get_workspace_dir",
    "WORKSPACE_DIR",
    "CORS_HEADERS",
    "response_json",
    "response_html",
    "response_bytes",
    "response_error",
]
