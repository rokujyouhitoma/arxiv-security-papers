#!/usr/bin/env python3
"""
Unified PEP 3333 WSGI Web Server for arXiv Security Papers.
Integrates API Gateway routing, MCP JSON-RPC, and Glassmorphism UI presentation.

Architecture Note:
Web server startup and serving processes strictly load pre-built indices
and NEVER perform index building during startup or request handling.
Index building is an offline batch task executed via `make build_vector_db`.
"""

import os
import sys

if os.path.dirname(os.path.abspath(__file__)) not in sys.path:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from typing import Any

from web.gateway import (
    CORS_HEADERS,
    WORKSPACE_DIR,
    WSGIApplication,
    app,
    application,
    get_workspace_dir,
    log_query,
    run_web_server,
)
from web.presentation import extract_paper_preview_metadata, render_okf_preview_html

SITE_DIR = os.path.join(WORKSPACE_DIR, "site")

run_server = run_web_server


def __getattr__(name: str) -> Any:
    if name == "VECTOR_ENGINE":
        from web.gateway import application

        return application.handlers.vector_engine
    raise AttributeError(f"module '{__name__}' has no attribute '{name}'")


__all__ = [
    "WSGIApplication",
    "application",
    "app",
    "run_web_server",
    "run_server",
    "get_workspace_dir",
    "WORKSPACE_DIR",
    "SITE_DIR",
    "CORS_HEADERS",
    "log_query",
    "render_okf_preview_html",
    "extract_paper_preview_metadata",
]

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="PEP 3333 WSGI Web Server for arxiv-security-papers"
    )
    parser.add_argument(
        "--port", type=int, default=8000, help="Port to run web server on"
    )
    parser.add_argument(
        "--host", type=str, default="0.0.0.0", help="Host address to bind to"
    )
    args = parser.parse_args()
    run_web_server(port=args.port, host=args.host)
