#!/usr/bin/env python3
"""
PEP 3333 WSGI Web Application & MCP API Server for arXiv Security Papers
Serves the Glassmorphic Web UI and provides REST / MCP JSON-RPC API endpoints.
"""

import json
import mimetypes
import os
import sys
import urllib.parse
from wsgiref.simple_server import make_server

if os.path.dirname(os.path.abspath(__file__)) not in sys.path:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mcp_server import (
    dispatch_tool,
    handle_get_latest_trends,
    handle_get_paper_summary,
    is_safe_workspace_path,
)
from vector_engine import VectorEngine


def get_workspace_dir():
    current_dir = os.path.dirname(os.path.abspath(__file__))
    if os.path.exists(os.path.join(current_dir, "..", "config.json")):
        return os.path.abspath(os.path.join(current_dir, ".."))
    return current_dir


WORKSPACE_DIR = get_workspace_dir()
SITE_DIR = os.path.join(WORKSPACE_DIR, "site")
VECTOR_ENGINE = VectorEngine(workspace_dir=WORKSPACE_DIR)

CORS_HEADERS = [
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
    ("Access-Control-Allow-Headers", "Content-Type"),
]


class WSGIApplication:
    """
    PEP 3333 Compliant WSGI Application for arXiv Security Papers Web & MCP Gateway.
    """

    def __init__(self, site_dir=SITE_DIR, vector_engine=VECTOR_ENGINE):
        self.site_dir = site_dir
        self.vector_engine = vector_engine

    def _response_json(self, start_response, data, status="200 OK"):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        headers = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
        ] + CORS_HEADERS
        start_response(status, headers)
        return [body]

    def _response_file(self, start_response, file_path, content_type):
        try:
            with open(file_path, "rb") as f:
                body = f.read()
            headers = [
                ("Content-Type", content_type),
                ("Content-Length", str(len(body))),
            ] + CORS_HEADERS
            start_response("200 OK", headers)
            return [body]
        except Exception as e:
            return self._response_json(
                start_response,
                {"status": "error", "message": f"Failed to read file: {e}"},
                status="500 Internal Server Error",
            )

    def _handle_options(self, start_response):
        headers = [("Content-Length", "0")] + CORS_HEADERS
        start_response("200 OK", headers)
        return [b""]

    def _handle_search(self, start_response, query_params):
        q = query_params.get("q", [""])[0]
        top_k_val = query_params.get("top_k", ["10"])[0]
        try:
            top_k = int(top_k_val)
        except ValueError:
            top_k = 10
        category = query_params.get("category", [None])[0]
        results, profile = self.vector_engine.search_with_profile(
            q, top_k=top_k, category=category
        )
        return self._response_json(
            start_response,
            {
                "status": "success",
                "query": q,
                "count": len(results),
                "results": results,
                "profile": profile,
            },
        )

    def _handle_paper(self, start_response, path):
        arxiv_id = path.replace("/api/paper/", "").strip()
        res = handle_get_paper_summary({"arxiv_id": arxiv_id})
        status = "200 OK" if res.get("status") == "success" else "404 Not Found"
        return self._response_json(start_response, res, status=status)

    def _handle_trends(self, start_response, query_params):
        period = query_params.get("period", ["monthly"])[0]
        res = handle_get_latest_trends({"period": period})
        status = "200 OK" if res.get("status") == "success" else "404 Not Found"
        return self._response_json(start_response, res, status=status)

    def _handle_stats(self, start_response):
        total_papers = len(self.vector_engine.documents)
        return self._response_json(
            start_response,
            {
                "status": "success",
                "total_papers": total_papers,
                "vector_db_status": "ready",
                "okf_version": "v0.2",
                "mcp_version": "1.0.0",
                "server_interface": "PEP 3333 WSGI",
            },
        )

    def _handle_mcp_post(self, environ, start_response):
        try:
            content_length_str = environ.get("CONTENT_LENGTH", "0")
            content_length = int(content_length_str) if content_length_str else 0
        except ValueError:
            content_length = 0

        # Maximum payload limit of 1MB (CWE-400 mitigation)
        if content_length > 1024 * 1024:
            return self._response_json(
                start_response,
                {"status": "error", "message": "Payload Too Large"},
                status="413 Payload Too Large",
            )

        wsgi_input = environ.get("wsgi.input")
        if not wsgi_input or content_length == 0:
            return self._response_json(
                start_response,
                {"status": "error", "message": "Empty request body"},
                status="400 Bad Request",
            )

        body_data = wsgi_input.read(content_length).decode("utf-8", errors="replace")
        try:
            payload = json.loads(body_data)
            name = payload.get("name")
            arguments = payload.get("arguments", {})
            if not name:
                return self._response_json(
                    start_response,
                    {"status": "error", "message": "Missing 'name' in JSON payload"},
                    status="400 Bad Request",
                )
            result = dispatch_tool(name, arguments)
            return self._response_json(
                start_response, {"status": "success", "tool": name, "result": result}
            )
        except Exception as e:
            return self._response_json(
                start_response,
                {"status": "error", "message": f"Invalid JSON payload: {e}"},
                status="400 Bad Request",
            )

    def _handle_static(self, start_response, path):
        rel_path = path.lstrip("/")
        if rel_path in ["", "search"]:
            rel_path = "index.html"

        target_file = os.path.realpath(os.path.join(self.site_dir, rel_path))
        abs_site_dir = os.path.realpath(self.site_dir)

        # Ensure target_file is strictly within self.site_dir (CWE-22 path traversal prevention)
        try:
            common = os.path.commonpath([abs_site_dir, target_file])
            if common != abs_site_dir:
                return self._response_json(
                    start_response,
                    {"status": "error", "message": "Access Denied"},
                    status="403 Forbidden",
                )
        except ValueError:
            return self._response_json(
                start_response,
                {"status": "error", "message": "Access Denied"},
                status="403 Forbidden",
            )

        if not os.path.isfile(target_file) or not is_safe_workspace_path(target_file):
            # SPA Fallback to index.html for non-API routes
            fallback_index = os.path.join(self.site_dir, "index.html")
            if os.path.isfile(fallback_index):
                return self._response_file(
                    start_response, fallback_index, "text/html; charset=utf-8"
                )
            return self._response_json(
                start_response,
                {"status": "error", "message": "File Not Found"},
                status="404 Not Found",
            )

        mime_type, _ = mimetypes.guess_type(target_file)
        if mime_type is None:
            mime_type = "application/octet-stream"
        if mime_type.startswith("text/") or mime_type in [
            "application/javascript",
            "application/json",
        ]:
            mime_type += "; charset=utf-8"

        return self._response_file(start_response, target_file, mime_type)

    def __call__(self, environ, start_response):
        method = environ.get("REQUEST_METHOD", "GET").upper()
        path = environ.get("PATH_INFO", "/")
        query_string = environ.get("QUERY_STRING", "")
        query_params = urllib.parse.parse_qs(query_string)

        if method == "OPTIONS":
            return self._handle_options(start_response)

        if method == "GET":
            if path == "/api/search":
                return self._handle_search(start_response, query_params)
            if path.startswith("/api/paper/"):
                return self._handle_paper(start_response, path)
            if path == "/api/trends":
                return self._handle_trends(start_response, query_params)
            if path == "/api/stats":
                return self._handle_stats(start_response)
            if path.startswith("/api/"):
                return self._response_json(
                    start_response,
                    {"status": "error", "message": "API endpoint not found"},
                    status="404 Not Found",
                )
            return self._handle_static(start_response, path)

        if method == "POST":
            if path == "/api/mcp":
                return self._handle_mcp_post(environ, start_response)
            return self._response_json(
                start_response,
                {"status": "error", "message": "Endpoint not found"},
                status="404 Not Found",
            )

        return self._response_json(
            start_response,
            {"status": "error", "message": f"Method {method} Not Allowed"},
            status="405 Method Not Allowed",
        )


# Global PEP 3333 WSGI Entrypoint for Gunicorn, uWSGI, and standalone servers
application = WSGIApplication()
app = application


def run_web_server(port=8000, host="0.0.0.0"):
    """Runs standard PEP 3333 WSGI Server"""
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
