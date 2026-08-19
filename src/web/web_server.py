#!/usr/bin/env python3
"""
Backward-compatible Web Server Facade for arXiv Security Papers.
Delegates HTTP and API Gateway responsibilities to `src/gateway/`
and UI Presentation rendering to `src/presentation/`.
"""

import os
import sys

if os.path.dirname(os.path.abspath(__file__)) not in sys.path:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gateway import (
    CORS_HEADERS,
    VECTOR_ENGINE,
    WORKSPACE_DIR,
    WSGIApplication,
    app,
    application,
    get_workspace_dir,
    log_query,
    run_web_server,
)
from presentation import extract_paper_preview_metadata, render_okf_preview_html

SITE_DIR = os.path.join(WORKSPACE_DIR, "site")

__all__ = [
    "WSGIApplication",
    "application",
    "app",
    "VECTOR_ENGINE",
    "run_web_server",
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
