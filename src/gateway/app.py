#!/usr/bin/env python3
"""
PEP 3333 WSGI Application and HTTP Server for arXiv Security Papers API Gateway.
"""

import urllib.parse
from typing import Any, Callable, Dict, List, Optional
from wsgiref.simple_server import make_server

from search.vector_engine import VectorEngine

from .handlers import GatewayHandlers
from .logger import WORKSPACE_DIR
from .router import CORS_HEADERS, response_error


class WSGIApplication:
    """
    PEP 3333 compliant WSGI Application router for arXiv Security Papers Gateway.
    """

    def __init__(
        self,
        workspace_dir: Optional[str] = None,
        vector_engine: Optional[VectorEngine] = None,
    ) -> None:
        self.workspace_dir = workspace_dir or WORKSPACE_DIR
        self.handlers = GatewayHandlers(
            workspace_dir=self.workspace_dir, vector_engine=vector_engine
        )

    def _handle_options(self, start_response: Callable[..., Any]) -> List[bytes]:
        start_response("200 OK", CORS_HEADERS)
        return [b""]

    def _route_get(
        self,
        environ: Dict[str, Any],
        start_response: Callable[..., Any],
        path: str,
        query_params: Dict[str, List[str]],
    ) -> List[bytes]:
        remote_addr = environ.get("REMOTE_ADDR", "-")
        if path == "/api/search":
            return self.handlers.handle_search(
                start_response, query_params, remote_addr=remote_addr
            )
        if path.startswith("/api/paper/"):
            return self.handlers.handle_paper(start_response, path)
        if path == "/api/trends":
            return self.handlers.handle_trends(start_response, query_params)
        if path == "/api/stats":
            return self.handlers.handle_stats(start_response)
        if path.startswith("/preview/"):
            return self.handlers.handle_preview(start_response, path)
        if path.startswith("/api/"):
            return response_error(
                start_response, "API endpoint not found", status="404 Not Found"
            )
        return self.handlers.handle_static(start_response, path)

    def __call__(
        self, environ: Dict[str, Any], start_response: Callable[..., Any]
    ) -> List[bytes]:
        method = environ.get("REQUEST_METHOD", "GET").upper()
        path = environ.get("PATH_INFO", "/")
        query_string = environ.get("QUERY_STRING", "")
        query_params = urllib.parse.parse_qs(query_string)

        if method == "OPTIONS":
            return self._handle_options(start_response)
        if method in ["GET", "HEAD"]:
            res = self._route_get(environ, start_response, path, query_params)
            return [b""] if method == "HEAD" else res
        if method == "POST":
            if path == "/api/mcp":
                return self.handlers.handle_mcp_post(environ, start_response)
            return response_error(
                start_response, "Endpoint not found", status="404 Not Found"
            )

        return response_error(
            start_response,
            f"Method {method} Not Allowed",
            status="405 Method Not Allowed",
        )


application = WSGIApplication()
app = application


def run_web_server(port: int = 8000, host: str = "0.0.0.0") -> None:
    """Runs standard PEP 3333 WSGI Server."""
    httpd = make_server(host, port, application)
    print(
        f"🚀 arxiv-security-papers PEP 3333 WSGI Web Server running at http://localhost:{port}"
    )
    httpd.serve_forever()


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
