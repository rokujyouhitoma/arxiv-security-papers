#!/usr/bin/env python3
"""
Thin compatibility shim forwarding to the web package.
"""

from web.web_server import *  # noqa: F401, F403
from web.web_server import run_web_server

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
