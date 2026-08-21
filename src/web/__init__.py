#!/usr/bin/env python3
"""
Web & API Serving Package.
Combines WSGI web server, API Gateway routing, and UI presentation components.
"""

from . import gateway, presentation
from .server import WSGIApplication, app, application, run_web_server

__all__ = [
    "app",
    "application",
    "WSGIApplication",
    "run_web_server",
    "gateway",
    "presentation",
]
