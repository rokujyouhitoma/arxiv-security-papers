#!/usr/bin/env python3
"""
Web Application & MCP API Server for arXiv Security Papers
Serves the Glassmorphic Web UI and provides REST / MCP JSON-RPC API endpoints.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import json
import urllib.parse
from http.server import HTTPServer, SimpleHTTPRequestHandler
from vector_engine import VectorEngine
from mcp_server import dispatch_tool, handle_get_paper_summary, handle_get_latest_trends, is_safe_workspace_path

def get_workspace_dir():
    current_dir = os.path.dirname(os.path.abspath(__file__))
    if os.path.exists(os.path.join(current_dir, "..", "config.json")):
        return os.path.abspath(os.path.join(current_dir, ".."))
    return current_dir

WORKSPACE_DIR = get_workspace_dir()
SITE_DIR = os.path.join(WORKSPACE_DIR, "site")
VECTOR_ENGINE = VectorEngine(workspace_dir=WORKSPACE_DIR)


class ArxivWebServerHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SITE_DIR, **kwargs)

    def _send_json_response(self, data, status_code=200):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path
        query_params = urllib.parse.parse_qs(parsed_url.query)

        # API: Search
        if path == "/api/search":
            q = query_params.get("q", [""])[0]
            top_k = int(query_params.get("top_k", [10])[0])
            category = query_params.get("category", [None])[0]
            results, profile = VECTOR_ENGINE.search_with_profile(q, top_k=top_k, category=category)
            self._send_json_response({
                "status": "success",
                "query": q,
                "count": len(results),
                "results": results,
                "profile": profile
            })
            return

        # API: Paper Details
        if path.startswith("/api/paper/"):
            arxiv_id = path.replace("/api/paper/", "").strip()
            res = handle_get_paper_summary({"arxiv_id": arxiv_id})
            self._send_json_response(res, status_code=200 if res.get("status") == "success" else 404)
            return

        # API: Trends
        if path == "/api/trends":
            period = query_params.get("period", ["monthly"])[0]
            res = handle_get_latest_trends({"period": period})
            self._send_json_response(res, status_code=200 if res.get("status") == "success" else 404)
            return

        # API: System Stats
        if path == "/api/stats":
            total_papers = len(VECTOR_ENGINE.documents)
            self._send_json_response({
                "status": "success",
                "total_papers": total_papers,
                "vector_db_status": "ready",
                "okf_version": "v0.2",
                "mcp_version": "1.0.0"
            })
            return

        # Default: Serve static files from site/ (/search or / serves index.html)
        if path in ["/", "/search"] or not os.path.exists(os.path.join(SITE_DIR, path.lstrip("/"))):
            if not path.startswith("/api/"):
                self.path = "/index.html" + ("?" + parsed_url.query if parsed_url.query else "")
        super().do_GET()

    def do_POST(self):
        if self.path == "/api/mcp":
            content_length = int(self.headers.get("Content-Length", 0))
            body_data = self.rfile.read(content_length).decode("utf-8")
            try:
                payload = json.loads(body_data)
                name = payload.get("name")
                arguments = payload.get("arguments", {})
                result = dispatch_tool(name, arguments)
                self._send_json_response({"status": "success", "tool": name, "result": result})
            except Exception as e:
                self._send_json_response({"status": "error", "message": str(e)}, status_code=400)
            return

        self._send_json_response({"status": "error", "message": "Not Found"}, status_code=404)


def run_web_server(port=8000):
    server_address = ("", port)
    httpd = HTTPServer(server_address, ArxivWebServerHandler)
    print(f"🚀 arxiv-security-papers Web Server running at http://localhost:{port}")
    httpd.serve_forever()


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Web Server for arxiv-security-papers")
    parser.add_argument("--port", type=int, default=8000, help="Port to run web server on")
    args = parser.parse_args()
    run_web_server(port=args.port)
