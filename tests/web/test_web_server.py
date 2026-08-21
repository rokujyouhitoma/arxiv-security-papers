"""
Unit tests for PEP 3333 WSGI Web Server Application & API endpoints.
"""

import io
import json
import os
import sys

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )

from web.server import VECTOR_ENGINE, WSGIApplication, application


def call_wsgi(
    app, method="GET", path="/", query_string="", body=None, headers_dict=None
):
    """Helper to simulate WSGI environment call."""
    environ = {
        "REQUEST_METHOD": method,
        "PATH_INFO": path,
        "QUERY_STRING": query_string,
        "SERVER_NAME": "localhost",
        "SERVER_PORT": "8000",
        "wsgi.version": (1, 0),
        "wsgi.url_scheme": "http",
        "wsgi.errors": io.StringIO(),
        "wsgi.multithread": False,
        "wsgi.multiprocess": False,
        "wsgi.run_once": False,
    }

    if body is not None:
        if isinstance(body, str):
            body_bytes = body.encode("utf-8")
        else:
            body_bytes = body
        environ["CONTENT_LENGTH"] = str(len(body_bytes))
        environ["wsgi.input"] = io.BytesIO(body_bytes)
    else:
        environ["CONTENT_LENGTH"] = "0"
        environ["wsgi.input"] = io.BytesIO(b"")

    if headers_dict:
        for k, v in headers_dict.items():
            environ[f"HTTP_{k.upper().replace('-', '_')}"] = v

    response_data = {"status": None, "headers": []}

    def start_response(status, response_headers, exc_info=None):
        response_data["status"] = status
        response_data["headers"] = response_headers
        return lambda x: None

    result_iter = app(environ, start_response)
    response_body = b"".join(result_iter)
    return response_data["status"], response_data["headers"], response_body


def test_vector_engine_ready():
    assert VECTOR_ENGINE is not None
    assert isinstance(VECTOR_ENGINE.documents, list)


def test_search_handler_logic():
    results = VECTOR_ENGINE.search("malware", top_k=2)
    assert isinstance(results, list)


def test_wsgi_app_get_index_html():
    assert isinstance(application, WSGIApplication)
    status, headers, body = call_wsgi(application, method="GET", path="/")
    assert status.startswith("200")
    header_dict = dict(headers)
    assert "Content-Type" in header_dict
    assert "text/html" in header_dict["Content-Type"]
    assert b"arXiv" in body or b"html" in body.lower()


def test_wsgi_app_get_search():
    status, headers, body = call_wsgi(
        application,
        method="GET",
        path="/api/search",
        query_string="q=malware&top_k=2",
    )
    assert status.startswith("200")
    header_dict = dict(headers)
    assert "application/json" in header_dict.get("Content-Type", "")
    assert header_dict.get("Access-Control-Allow-Origin") == "*"

    data = json.loads(body.decode("utf-8"))
    assert data["status"] == "success"
    assert "results" in data
    assert "profile" in data


def test_wsgi_app_get_trends():
    status, headers, body = call_wsgi(
        application,
        method="GET",
        path="/api/trends",
        query_string="period=monthly",
    )
    assert status.startswith("200") or status.startswith("404")
    data = json.loads(body.decode("utf-8"))
    assert "status" in data


def test_wsgi_app_get_stats():
    status, headers, body = call_wsgi(application, method="GET", path="/api/stats")
    assert status.startswith("200")
    data = json.loads(body.decode("utf-8"))
    assert data["status"] == "success"
    assert "total_papers" in data
    assert data["server_interface"] == "PEP 3333 WSGI"


def test_wsgi_app_options_cors():
    status, headers, body = call_wsgi(application, method="OPTIONS", path="/api/search")
    assert status.startswith("200")
    header_dict = dict(headers)
    assert header_dict.get("Access-Control-Allow-Origin") == "*"
    assert "GET, POST, OPTIONS" in header_dict.get("Access-Control-Allow-Methods", "")


def test_wsgi_app_post_mcp():
    payload = {
        "name": "search_security_papers",
        "arguments": {"query": "ransomware", "top_k": 2},
    }
    status, headers, body = call_wsgi(
        application, method="POST", path="/api/mcp", body=json.dumps(payload)
    )
    assert status.startswith("200")
    data = json.loads(body.decode("utf-8"))
    assert data["status"] == "success"
    assert data["tool"] == "search_security_papers"
    assert "result" in data


def test_wsgi_app_invalid_json_post():
    status, headers, body = call_wsgi(
        application, method="POST", path="/api/mcp", body="INVALID_JSON{{"
    )
    assert status.startswith("400")
    data = json.loads(body.decode("utf-8"))
    assert data["status"] == "error"


def test_wsgi_app_path_traversal_blocked():
    status, headers, body = call_wsgi(
        application, method="GET", path="/../../etc/passwd"
    )
    assert status.startswith("403") or status.startswith("404")


def test_wsgi_app_not_found():
    status, headers, body = call_wsgi(
        application, method="GET", path="/api/nonexistent_route"
    )
    assert status.startswith("404")


def test_wsgi_app_get_paper_related():
    if VECTOR_ENGINE.documents:
        first_id = VECTOR_ENGINE.documents[0]["id"]
        status, headers, body = call_wsgi(
            application, method="GET", path=f"/api/paper/{first_id}/related"
        )
        assert status.startswith("200")
        data = json.loads(body.decode("utf-8"))
        assert data["status"] == "success"
        assert "related_papers" in data
        assert "mermaid_graph" in data

    # Non-existent paper
    status, headers, body = call_wsgi(
        application, method="GET", path="/api/paper/nonexistent_9999/related"
    )
    assert status.startswith("404")


def test_wsgi_app_method_not_allowed():
    status, headers, body = call_wsgi(application, method="PUT", path="/api/search")
    assert status.startswith("405")


def test_wsgi_app_get_raw_data_txt():
    # Find any existing txt file in outputs/raw_data/
    import glob

    txt_files = glob.glob("outputs/raw_data/*/*.txt")
    if txt_files:
        sample_path = "/" + txt_files[0].replace("outputs/", "")
        status, headers, body = call_wsgi(application, method="GET", path=sample_path)
        assert status.startswith("200")
        header_dict = dict(headers)
        assert "text/plain" in header_dict.get("Content-Type", "")
        assert len(body) > 0


def test_wsgi_app_get_raw_data_missing_and_traversal():
    # Missing raw_data should return 404, NOT index.html fallback
    status, headers, body = call_wsgi(
        application, method="GET", path="/raw_data/2026-01-01/missing_file_9999.txt"
    )
    assert status.startswith("404")

    # Traversal should return 403
    status, headers, body = call_wsgi(
        application, method="GET", path="/raw_data/../../../etc/passwd"
    )
    assert status.startswith("403")


def test_wsgi_app_get_preview_html():
    if VECTOR_ENGINE.documents:
        first_id = VECTOR_ENGINE.documents[0]["id"]
        status, headers, body = call_wsgi(
            application, method="GET", path=f"/preview/{first_id}"
        )
        assert status.startswith("200")
        header_dict = dict(headers)
        assert "text/html" in header_dict.get("Content-Type", "")
        html_str = body.decode("utf-8")
        assert "Google OKF Preview" in html_str
        assert first_id in html_str

    # Non-existent preview
    status, headers, body = call_wsgi(
        application, method="GET", path="/preview/nonexistent_9999"
    )
    assert status.startswith("404")


def test_wsgi_app_get_okf_md_plain():
    import glob

    md_files = glob.glob("outputs/okf_papers/*/*.md")
    if md_files:
        sample_path = "/" + md_files[0]
        status, headers, body = call_wsgi(application, method="GET", path=sample_path)
        assert status.startswith("200")
        header_dict = dict(headers)
        assert "text/plain" in header_dict.get("Content-Type", "")
        md_text = body.decode("utf-8")
        assert 'type: "security-paper"' in md_text or "type: security-paper" in md_text


def test_wsgi_app_options_and_error_paths():
    # OPTIONS request
    status, headers, body = call_wsgi(application, method="OPTIONS", path="/api/search")
    assert status.startswith("200")

    # Invalid top_k fallback to default
    status, headers, body = call_wsgi(
        application,
        method="GET",
        path="/api/search",
        query_string="q=test&top_k=invalid_int",
    )
    assert status.startswith("200")

    # MCP Large Payload (413)
    huge_body = "x" * (1024 * 1024 + 10)
    status, headers, body = call_wsgi(
        application, method="POST", path="/api/mcp", body=huge_body
    )
    assert status.startswith("413")

    # MCP Empty body (400)
    status, headers, body = call_wsgi(
        application, method="POST", path="/api/mcp", body=""
    )
    assert status.startswith("400")

    # MCP Missing name or method (400)
    status, headers, body = call_wsgi(
        application, method="POST", path="/api/mcp", body="{}"
    )
    assert status.startswith("400")
