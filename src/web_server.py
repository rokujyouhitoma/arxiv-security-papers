#!/usr/bin/env python3
"""
PEP 3333 WSGI Web Application & MCP API Server for arXiv Security Papers
Serves the Glassmorphic Web UI and provides REST / MCP JSON-RPC API endpoints.
"""

import html
import json
import mimetypes
import os
import re
import sys
import urllib.parse
from wsgiref.simple_server import make_server

if os.path.dirname(os.path.abspath(__file__)) not in sys.path:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mcp.papers_server import (
    PROMPTS_MANIFEST,
    RESOURCES_MANIFEST,
    TOOLS_MANIFEST,
    dispatch_tool,
    handle_get_latest_trends,
    handle_get_paper_summary,
    handle_get_prompt,
    handle_read_resource,
    is_safe_workspace_path,
)
from vector_engine import VectorEngine


def get_workspace_dir() -> str:
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur != os.path.dirname(cur):
        if (
            os.path.exists(os.path.join(cur, "pyproject.toml"))
            or os.path.exists(os.path.join(cur, "Makefile"))
            or os.path.exists(os.path.join(cur, ".agents"))
        ):
            return cur
        cur = os.path.dirname(cur)
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


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

    def __init__(
        self,
        site_dir=SITE_DIR,
        vector_engine=VECTOR_ENGINE,
        workspace_dir=WORKSPACE_DIR,
    ):
        self.site_dir = site_dir
        self.vector_engine = vector_engine
        self.workspace_dir = workspace_dir

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
        sub_path = path.replace("/api/paper/", "").strip()
        if sub_path.endswith("/related"):
            arxiv_id = sub_path.replace("/related", "").strip()
            return self._handle_paper_related(start_response, arxiv_id)

        arxiv_id = sub_path
        res = handle_get_paper_summary({"arxiv_id": arxiv_id})
        status = "200 OK" if res.get("status") == "success" else "404 Not Found"
        return self._response_json(start_response, res, status=status)

    def _handle_paper_related(self, start_response, arxiv_id):
        res = self.vector_engine.get_related_papers(arxiv_id)
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
            method = payload.get("method")
            req_id = payload.get("id")

            # Standard MCP JSON-RPC 2.0 Routing
            if method:
                params = payload.get("params", {})
                if method == "tools/list":
                    return self._response_json(
                        start_response,
                        {
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "result": {"tools": TOOLS_MANIFEST},
                        },
                    )
                elif method == "tools/call":
                    t_name = params.get("name")
                    t_args = params.get("arguments", {})
                    output = dispatch_tool(t_name, t_args)
                    return self._response_json(
                        start_response,
                        {
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "result": {
                                "content": [
                                    {
                                        "type": "text",
                                        "text": json.dumps(output, ensure_ascii=False),
                                    }
                                ]
                            },
                        },
                    )
                elif method == "resources/list":
                    return self._response_json(
                        start_response,
                        {
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "result": {"resources": RESOURCES_MANIFEST},
                        },
                    )
                elif method == "resources/read":
                    uri = params.get("uri", "")
                    output = handle_read_resource(uri)
                    return self._response_json(
                        start_response,
                        {"jsonrpc": "2.0", "id": req_id, "result": output},
                    )
                elif method == "prompts/list":
                    return self._response_json(
                        start_response,
                        {
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "result": {"prompts": PROMPTS_MANIFEST},
                        },
                    )
                elif method == "prompts/get":
                    p_name = params.get("name")
                    p_args = params.get("arguments", {})
                    output = handle_get_prompt(p_name, p_args)
                    return self._response_json(
                        start_response,
                        {"jsonrpc": "2.0", "id": req_id, "result": output},
                    )

            # Fallback legacy format: {"name": ..., "arguments": ...}
            name = payload.get("name")
            arguments = payload.get("arguments", {})
            if not name:
                return self._response_json(
                    start_response,
                    {
                        "status": "error",
                        "message": "Missing 'name' or 'method' in JSON payload",
                    },
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
        raw_data_dir = os.path.realpath(
            os.path.join(self.workspace_dir, "outputs", "raw_data")
        )
        outputs_dir = os.path.realpath(os.path.join(self.workspace_dir, "outputs"))
        abs_site_dir = os.path.realpath(self.site_dir)

        is_raw_data = path.startswith("/raw_data/")
        is_outputs = path.startswith("/outputs/")

        if is_raw_data:
            rel = path[len("/raw_data/") :].lstrip("/")
            target_file = os.path.realpath(os.path.join(raw_data_dir, rel))
            base_dir = raw_data_dir
        elif is_outputs:
            rel = path[len("/outputs/") :].lstrip("/")
            target_file = os.path.realpath(os.path.join(outputs_dir, rel))
            base_dir = outputs_dir
        else:
            rel_path = path.lstrip("/")
            if rel_path in ["", "search", "trends", "dashboard"]:
                rel_path = "index.html"
            target_file = os.path.realpath(os.path.join(self.site_dir, rel_path))
            base_dir = abs_site_dir

        # Ensure target_file is strictly within base_dir (CWE-22 path traversal prevention)
        try:
            common = os.path.commonpath([base_dir, target_file])
            if common != base_dir or not is_safe_workspace_path(target_file):
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

        if not os.path.isfile(target_file):
            has_extension = bool(os.path.splitext(target_file)[1])
            # Only fallback to index.html for extension-less SPA navigation routes in site_dir
            if not is_raw_data and not is_outputs and not has_extension:
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
        if target_file.endswith(".md"):
            mime_type = "text/plain; charset=utf-8"
        elif mime_type is None:
            mime_type = "application/octet-stream"
        elif mime_type.startswith("text/") or mime_type in [
            "application/javascript",
            "application/json",
        ]:
            mime_type += "; charset=utf-8"

        return self._response_file(start_response, target_file, mime_type)

    def _handle_preview(self, start_response, path):
        arxiv_id = (
            path.replace("/preview/", "").strip().replace("/", "_").replace("..", "")
        )
        res = handle_get_paper_summary({"arxiv_id": arxiv_id})
        if res.get("status") != "success":
            return self._response_json(
                start_response,
                {"status": "error", "message": f"Paper '{arxiv_id}' not found."},
                status="404 Not Found",
            )

        content = res.get("content", "")
        raw_md_path = "/" + res.get("path", "")

        # Parse YAML frontmatter metadata
        title_m = re.search(r"^title:\s*[\"']?(.*?)[\"']?$", content, re.MULTILINE)
        title = title_m.group(1) if title_m else arxiv_id

        tags_m = re.search(r"^tags:\s*\[(.*?)\]", content, re.MULTILINE)
        tags_str = tags_m.group(1) if tags_m else ""

        authors_m = re.search(r"^authors:\s*\[(.*?)\]", content, re.MULTILINE)
        authors_str = authors_m.group(1) if authors_m else ""

        date_m = re.search(
            r"^timestamp:\s*[\"']?([0-9]{4}-[0-9]{2}-[0-9]{2})", content, re.MULTILINE
        )
        date_str = date_m.group(1) if date_m else ""

        escaped_content = json.dumps(content, ensure_ascii=False)

        html_doc = f"""<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{html.escape(title)} - Google OKF Preview</title>
  <link rel="stylesheet" href="/style.css">
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
  <script src="/js/lexer.js"></script>
  <script src="/js/parser.js"></script>
  <script src="/js/evaluator.js"></script>
  <script src="/js/renderer.js"></script>
  <script src="/js/markdown_compiler.js"></script>
</head>
<body style="background: var(--bg-dark); color: var(--text-primary); margin: 0; padding: 2rem 1rem;">
  <div style="max-width: 1080px; margin: 0 auto;">
    <div class="glass-panel" style="padding: 1.5rem; margin-bottom: 2rem;">
      <div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 1rem;">
        <div style="display: flex; gap: 0.5rem; align-items: center;">
          <span class="modal-badge">Google OKF v0.2</span>
          <span class="arxiv-id-tag">arXiv: {html.escape(arxiv_id)}</span>
        </div>
        <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
          <a href="{html.escape(raw_md_path)}" class="btn-link-action" target="_blank" rel="noopener">
            📝 生の Markdown (.md)
          </a>
          <a href="https://arxiv.org/abs/{html.escape(arxiv_id)}"
             class="btn-link-action" target="_blank" rel="noopener">
            arXiv 原本 ↗
          </a>
          <a href="https://arxiv.org/pdf/{html.escape(arxiv_id)}.pdf"
             class="btn-link-action" target="_blank" rel="noopener">
            PDF 📄
          </a>
          <a href="/" class="btn-link-action">🏠 ポータル</a>
        </div>
      </div>
      <h1 style="font-size: 1.6rem; color: #fff; margin: 0.5rem 0;">{html.escape(title)}</h1>
      <div style="font-size: 0.85rem; color: #94a3b8; display: flex; gap: 1.5rem; flex-wrap: wrap; margin-top: 0.8rem;">
        <div>👥 <strong>著者:</strong> {html.escape(authors_str)}</div>
        <div>📅 <strong>公開日:</strong> {html.escape(date_str)}</div>
        <div>🏷️ <strong>タグ:</strong> {html.escape(tags_str)}</div>
      </div>
    </div>
    <div id="previewBody" class="glass-panel" style="padding: 2.5rem; line-height: 1.75;">
      <p style="color: #94a3b8;">ドキュメントをレンダリング中...</p>
    </div>
  </div>
  <script>
    document.addEventListener('DOMContentLoaded', () => {{
      const rawContent = {escaped_content};
      const container = document.getElementById('previewBody');
      if (window.MarkdownCompiler) {{
        const compiled = window.MarkdownCompiler.compile(rawContent);
        container.innerHTML = compiled.html;
        window.MarkdownCompiler.renderMermaid(container);
      }} else {{
        container.innerText = rawContent;
      }}
    }});
  </script>
</body>
</html>"""
        body = html_doc.encode("utf-8")
        headers = [
            ("Content-Type", "text/html; charset=utf-8"),
            ("Content-Length", str(len(body))),
        ] + CORS_HEADERS
        start_response("200 OK", headers)
        return [body]

    def __call__(self, environ, start_response):
        method = environ.get("REQUEST_METHOD", "GET").upper()
        path = environ.get("PATH_INFO", "/")
        query_string = environ.get("QUERY_STRING", "")
        query_params = urllib.parse.parse_qs(query_string)

        if method == "OPTIONS":
            return self._handle_options(start_response)

        if method in ["GET", "HEAD"]:
            if path == "/api/search":
                res = self._handle_search(start_response, query_params)
            elif path.startswith("/api/paper/"):
                res = self._handle_paper(start_response, path)
            elif path == "/api/trends":
                res = self._handle_trends(start_response, query_params)
            elif path == "/api/stats":
                res = self._handle_stats(start_response)
            elif path.startswith("/preview/"):
                res = self._handle_preview(start_response, path)
            elif path.startswith("/api/"):
                res = self._response_json(
                    start_response,
                    {"status": "error", "message": "API endpoint not found"},
                    status="404 Not Found",
                )
            else:
                res = self._handle_static(start_response, path)

            if method == "HEAD":
                return [b""]
            return res

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
