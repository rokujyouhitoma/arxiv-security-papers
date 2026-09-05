#!/usr/bin/env python3
"""
Integration tests for /api/graph/query REST endpoint.
Validates HTTP responses, schema conformance, parameter clamping, and query dispatching.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import io
import json
import os
from typing import Any, Dict, List

from web.gateway.app import WSGIApplication


def _call_wsgi(app: WSGIApplication, path: str, query: str = "") -> Dict[str, Any]:
    status_out: List[str] = []
    headers_out: List[Any] = []

    def start_response(status: str, headers: List[Any], exc_info: Any = None) -> None:
        status_out.append(status)
        headers_out.append(headers)

    environ = {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": path,
        "QUERY_STRING": query,
        "wsgi.input": io.BytesIO(b""),
    }
    raw = b"".join(app(environ, start_response)).decode("utf-8")
    assert status_out[0] == "200 OK"
    res: Dict[str, Any] = json.loads(raw)
    return res


def test_api_graph_query_gaps() -> None:
    workspace_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    app = WSGIApplication(workspace_dir=workspace_dir)

    res = _call_wsgi(app, "/api/graph/query", "q=gaps&limit=25")
    assert res["status"] == "success"
    assert res["query"] == "gaps"
    assert "mesh" in res
    assert "nodes" in res["mesh"]
    assert "edges" in res["mesh"]
    assert len(res["mesh"]["nodes"]) > 0


def test_api_graph_query_cwe() -> None:
    workspace_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    app = WSGIApplication(workspace_dir=workspace_dir)

    res = _call_wsgi(app, "/api/graph/query", "q=cwe:+CWE-20&limit=30")
    assert res["status"] == "success"
    assert "cwe" in res["query"].lower()
    assert "mesh" in res
    node_ids = {n["id"] for n in res["mesh"]["nodes"]}
    assert "Vulnerability:CWE-20" in node_ids


def test_api_graph_query_limit_clamping() -> None:
    workspace_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    app = WSGIApplication(workspace_dir=workspace_dir)

    # limit > 500 should be clamped
    res = _call_wsgi(app, "/api/graph/query", "q=match:+security&limit=99999")
    assert res["status"] == "success"
    assert len(res["mesh"]["nodes"]) <= 500


def test_api_graph_query_paper_match_with_edges() -> None:
    workspace_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    app = WSGIApplication(workspace_dir=workspace_dir)

    res = _call_wsgi(app, "/api/graph/query", "q=match:Paper:&limit=20")
    assert res["status"] == "success"
    assert "mesh" in res
    assert "nodes" in res["mesh"]
    assert "edges" in res["mesh"]
    node_ids = {n["id"] for n in res["mesh"]["nodes"]}
    for e in res["mesh"]["edges"]:
        assert e["source"] in node_ids, f"Dangling edge: {e}"
        assert e["target"] in node_ids, f"Dangling edge: {e}"
