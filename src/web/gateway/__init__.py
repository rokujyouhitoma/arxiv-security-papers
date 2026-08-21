#!/usr/bin/env python3
"""
API Gateway and Network Layer for arXiv Security Papers.
Provides WSGI application router, HTTP handlers, query logging, and CORS middleware.
"""

from .app import WSGIApplication, app, application, run_web_server
from .handlers import GatewayHandlers
from .logger import WORKSPACE_DIR, get_workspace_dir, log_query
from .router import (
    CORS_HEADERS,
    response_bytes,
    response_error,
    response_html,
    response_json,
)

VECTOR_ENGINE = application.handlers.vector_engine

__all__ = [
    "WSGIApplication",
    "application",
    "app",
    "VECTOR_ENGINE",
    "run_web_server",
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
