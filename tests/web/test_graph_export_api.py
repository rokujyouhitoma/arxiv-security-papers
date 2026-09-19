#!/usr/bin/env python3
"""Integration tests for /api/export/graph multi-format download API (Issue 199)."""

from __future__ import annotations

import io
import json
import os
from typing import Any, Dict, List, Tuple

from web.gateway import WSGIApplication


def _make_test_environ(query_string: str = "") -> Dict[str, Any]:
    return {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": "/api/export/graph",
        "QUERY_STRING": query_string,
        "wsgi.input": io.BytesIO(b""),
        "CONTENT_LENGTH": "0",
        "REMOTE_ADDR": "127.0.0.1",
    }


def _execute_request(
    app: WSGIApplication, env: Dict[str, Any]
) -> Tuple[str, Dict[str, str], bytes]:
    status_captured: List[str] = []
    headers_captured: List[List[Tuple[str, str]]] = []

    def start_response(status: str, headers: List[Tuple[str, str]]) -> None:
        status_captured.append(status)
        headers_captured.append(headers)

    body = b"".join(app(env, start_response))
    headers_dict = {k.lower(): v for k, v in headers_captured[0]}
    return status_captured[0], headers_dict, body


class TestTurtleExport:
    """Tests for Turtle format export endpoint."""

    def test_turtle_status_and_content_type(self) -> None:
        app = WSGIApplication()
        env = _make_test_environ("format=turtle")
        status, headers, body = _execute_request(app, env)
        assert status == "200 OK"
        assert "text/turtle" in headers.get("content-type", "")
        assert b"@prefix" in body or b"sec:" in body

    def test_turtle_disposition_and_cache(self) -> None:
        app = WSGIApplication()
        env = _make_test_environ("format=turtle")
        _, headers, _ = _execute_request(app, env)
        assert 'attachment; filename="graph.ttl"' in headers.get(
            "content-disposition", ""
        )
        assert headers.get("cache-control") == "no-store"

    def test_ttl_alias(self) -> None:
        app = WSGIApplication()
        env = _make_test_environ("format=ttl")
        status, headers, body = _execute_request(app, env)
        assert status == "200 OK"
        assert "text/turtle" in headers.get("content-type", "")
        assert len(body) > 0


class TestJsonLdExport:
    """Tests for JSON-LD format export endpoint."""

    def test_jsonld_headers(self) -> None:
        app = WSGIApplication()
        env = _make_test_environ("format=jsonld")
        status, headers, _ = _execute_request(app, env)
        assert status == "200 OK"
        assert "application/ld+json" in headers.get("content-type", "")
        assert 'attachment; filename="graph.jsonld"' in headers.get(
            "content-disposition", ""
        )

    def test_jsonld_body(self) -> None:
        app = WSGIApplication()
        env = _make_test_environ("format=jsonld")
        _, _, body = _execute_request(app, env)
        data = json.loads(body.decode("utf-8"))
        assert "@context" in data
        assert "@graph" in data


class TestStixExport:
    """Tests for STIX 2.1 format export endpoint."""

    def test_stix_headers(self) -> None:
        app = WSGIApplication()
        env = _make_test_environ("format=stix")
        status, headers, _ = _execute_request(app, env)
        assert status == "200 OK"
        assert "application/json" in headers.get("content-type", "")
        assert 'attachment; filename="graph_stix_bundle.json"' in headers.get(
            "content-disposition", ""
        )

    def test_stix_body_structure(self) -> None:
        app = WSGIApplication()
        env = _make_test_environ("format=stix")
        _, _, body = _execute_request(app, env)
        data = json.loads(body.decode("utf-8"))
        assert data.get("type") == "bundle"
        assert data.get("id", "").startswith("bundle--")
        assert "objects" in data


class TestExportCornerCases:
    """Tests for default parameters, errors, and security headers."""

    def test_default_format(self) -> None:
        app = WSGIApplication()
        env = _make_test_environ("")
        status, headers, body = _execute_request(app, env)
        assert status == "200 OK"
        assert "text/turtle" in headers.get("content-type", "")
        assert len(body) > 0

    def test_invalid_format_returns_400(self) -> None:
        app = WSGIApplication()
        env = _make_test_environ("format=invalid_format_xyz")
        status, headers, body = _execute_request(app, env)
        assert status == "400 Bad Request"
        data = json.loads(body.decode("utf-8"))
        assert data.get("status") == "error"

    def test_cors_headers(self) -> None:
        app = WSGIApplication()
        env = _make_test_environ("format=turtle")
        status, headers, _ = _execute_request(app, env)
        assert status == "200 OK"
        assert headers.get("access-control-allow-origin") == "*"
        assert "GET" in headers.get("access-control-allow-methods", "")


class TestDashboardExportUI:
    """Tests for Dashboard HTML export elements."""

    def _read_dashboard_html(self) -> str:
        workspace_dir = os.path.dirname(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        )
        dashboard_path = os.path.join(workspace_dir, "site", "dashboard.html")
        with open(dashboard_path, "r", encoding="utf-8") as f:
            content = f.read()
        js_path = os.path.join(workspace_dir, "site", "js", "dashboard.js")
        if os.path.exists(js_path):
            with open(js_path, "r", encoding="utf-8") as js_f:
                content += "\n" + js_f.read()
        return content

    def test_ui_dropdown_elements(self) -> None:
        html = self._read_dashboard_html()
        assert 'id="btnExportDropdown"' in html
        assert 'id="exportDropdownMenu"' in html
        assert "triggerGraphDownload('turtle')" in html

    def test_ui_format_buttons(self) -> None:
        html = self._read_dashboard_html()
        assert "triggerGraphDownload('jsonld')" in html
        assert "triggerGraphDownload('stix')" in html

    def test_ui_js_handlers_and_shortcuts(self) -> None:
        html = self._read_dashboard_html()
        assert "window.toggleExportDropdown" in html
        assert "window.triggerGraphDownload" in html
        assert "closeExportDropdown" in html
        assert "Alt+E" in html or "altKey" in html
