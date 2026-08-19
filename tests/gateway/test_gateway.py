#!/usr/bin/env python3
"""
Unit tests for API Gateway Layer (WSGI Application router, REST API, CORS).
"""

import io
import json
from typing import Any, Dict, List, Tuple
from unittest.mock import MagicMock

from gateway import WSGIApplication


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
