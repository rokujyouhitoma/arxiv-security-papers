#!/usr/bin/env python3
"""
Unit tests for API Gateway Layer (WSGI Application router, REST API, CORS).
"""

import io
import json
from typing import Any, Dict, List, Tuple
from unittest.mock import MagicMock

from web.gateway import WSGIApplication


def make_test_environ(
    method: str = "GET",
    path: str = "/",
    query_string: str = "",
    body: bytes = b"",
    headers: Dict[str, str] | None = None,
) -> Dict[str, Any]:
    env: Dict[str, Any] = {
        "REQUEST_METHOD": method,
        "PATH_INFO": path,
        "QUERY_STRING": query_string,
        "wsgi.input": io.BytesIO(body),
        "CONTENT_LENGTH": str(len(body)),
        "REMOTE_ADDR": "127.0.0.1",
    }
    if headers:
        for k, v in headers.items():
            env[f"HTTP_{k.upper().replace('-', '_')}"] = v
    return env


def test_gateway_options_cors():
    app = WSGIApplication()
    status_captured: List[str] = []
    headers_captured: List[List[Tuple[str, str]]] = []

    def start_response(status: str, headers: List[Tuple[str, str]]) -> None:
        status_captured.append(status)
        headers_captured.append(headers)

    env = make_test_environ(method="OPTIONS", path="/api/search")
    res = app(env, start_response)

    assert status_captured[0] == "200 OK"
    headers_dict = dict(headers_captured[0])
    assert headers_dict.get("Access-Control-Allow-Origin") == "*"
    assert res == [b""]


def test_gateway_405_method_not_allowed():
    app = WSGIApplication()
    status_captured: List[str] = []

    def start_response(status: str, headers: List[Tuple[str, str]]) -> None:
        status_captured.append(status)

    env = make_test_environ(method="DELETE", path="/api/search")
    res = app(env, start_response)

    assert status_captured[0] == "405 Method Not Allowed"
    data = json.loads(res[0].decode("utf-8"))
    assert data["status"] == "error"


def test_gateway_404_not_found():
    app = WSGIApplication()
    status_captured: List[str] = []

    def start_response(status: str, headers: List[Tuple[str, str]]) -> None:
        status_captured.append(status)

    env = make_test_environ(method="GET", path="/api/unknown_endpoint")
    res = app(env, start_response)

    assert status_captured[0] == "404 Not Found"
    data = json.loads(res[0].decode("utf-8"))
    assert data["status"] == "error"


def test_gateway_search_mock():
    mock_engine = MagicMock()
    mock_engine.search_with_profile.return_value = (
        [{"id": "2608.00001", "title": "Test Paper"}],
        {"total_ms": 1.23},
    )

    app = WSGIApplication(vector_engine=mock_engine)
    status_captured: List[str] = []

    def start_response(status: str, headers: List[Tuple[str, str]]) -> None:
        status_captured.append(status)

    env = make_test_environ(
        method="GET", path="/api/search", query_string="q=quantum&top_k=5"
    )
    res = app(env, start_response)

    assert status_captured[0] == "200 OK"
    data = json.loads(res[0].decode("utf-8"))
    assert data["status"] == "success"
    assert len(data["results"]) == 1
    assert data["results"][0]["id"] == "2608.00001"


def test_gateway_mcp_jsonrpc_tool_list():
    app = WSGIApplication()
    status_captured: List[str] = []

    def start_response(status: str, headers: List[Tuple[str, str]]) -> None:
        status_captured.append(status)

    rpc_req = json.dumps({"jsonrpc": "2.0", "method": "tools/list", "id": 1}).encode(
        "utf-8"
    )
    env = make_test_environ(method="POST", path="/api/mcp", body=rpc_req)
    res = app(env, start_response)

    assert status_captured[0] == "200 OK"
    data = json.loads(res[0].decode("utf-8"))
    assert data["jsonrpc"] == "2.0"
    assert "tools" in data["result"]
    assert data["id"] == 1


def test_gateway_static_okf_papers_transparent_resolution(tmp_path: Any) -> None:
    # Create mock okf_papers in outputs directory
    outputs_dir = tmp_path / "outputs" / "okf_papers" / "2026-08-17"
    outputs_dir.mkdir(parents=True)
    paper_file = outputs_dir / "2608.16551.md"
    paper_file.write_text("# Test OKF Paper Content", encoding="utf-8")

    app = WSGIApplication(workspace_dir=str(tmp_path))
    status_captured: List[str] = []

    def start_response(status: str, headers: List[Tuple[str, str]]) -> None:
        status_captured.append(status)

    env = make_test_environ(method="GET", path="/okf_papers/2026-08-17/2608.16551.md")
    res = app(env, start_response)

    assert status_captured[0] == "200 OK"
    assert b"# Test OKF Paper Content" in res[0]


def test_gateway_handle_paper_with_content(tmp_path: Any) -> None:
    # Setup mock OKF paper on disk
    outputs_dir = tmp_path / "outputs" / "okf_papers" / "2025-02-23"
    outputs_dir.mkdir(parents=True)
    paper_file = outputs_dir / "2502.16730.md"
    paper_file.write_text(
        '---\ntype: "security-paper"\ntitle: "RapidPen: Penetration Testing"\n---\n\n# RapidPen\n\n## 概要\nTest Content',
        encoding="utf-8",
    )

    mock_engine = MagicMock()
    mock_engine.documents_by_id = {
        "2502.16730": {
            "id": "2502.16730",
            "clean_id": "2502.16730",
            "title": "RapidPen: Penetration Testing",
            "path": "outputs/okf_papers/2025-02-23/2502.16730.md",
        }
    }
    mock_engine.documents = list(mock_engine.documents_by_id.values())

    app = WSGIApplication(workspace_dir=str(tmp_path), vector_engine=mock_engine)
    status_captured: List[str] = []

    def start_response(status: str, headers: List[Tuple[str, str]]) -> None:
        status_captured.append(status)

    env = make_test_environ(method="GET", path="/api/paper/2502.16730")
    res = app(env, start_response)

    assert status_captured[0] == "200 OK"
    data = json.loads(res[0].decode("utf-8"))
    assert data["status"] == "success"
    assert "content" in data
    assert "RapidPen" in data["content"]
    assert data["path"] == "outputs/okf_papers/2025-02-23/2502.16730.md"


def test_gateway_additional_endpoints():
    mock_engine = MagicMock()
    mock_engine.documents = [{"id": "doc1", "category": "cs.CR"}]
    mock_engine.knowledge_graph.get_neighbors.return_value = {"nodes": [], "edges": []}
    mock_engine.get_facets.return_value = {"categories": {"cs.CR": 10}}
    app = WSGIApplication(vector_engine=mock_engine)

    # 1. /api/stats
    status_cap: List[str] = []
    env_stats = make_test_environ(method="GET", path="/api/stats")
    res_stats = app(env_stats, lambda s, h: status_cap.append(s))
    assert status_cap[0] == "200 OK"
    assert json.loads(res_stats[0].decode("utf-8"))["status"] == "success"

    # 2. /api/trends
    status_cap.clear()
    env_trends = make_test_environ(
        method="GET", path="/api/trends", query_string="period=monthly"
    )
    res_trends = app(env_trends, lambda s, h: status_cap.append(s))
    assert status_cap[0] == "200 OK"
    assert json.loads(res_trends[0].decode("utf-8"))["status"] == "success"

    # 3. /api/graph/mesh
    status_cap.clear()
    env_graph = make_test_environ(method="GET", path="/api/graph/mesh")
    res_graph = app(env_graph, lambda s, h: status_cap.append(s))
    assert status_cap[0] == "200 OK"
    assert json.loads(res_graph[0].decode("utf-8"))["status"] == "success"
