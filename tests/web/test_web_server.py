"""
Unit tests for PEP 3333 WSGI Web Server Application & API endpoints.
"""

import io
import json
import os
import sys

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from security.middleware.wsgi import SecurityWSGIMiddleware
from web.server import VECTOR_ENGINE, WSGIApplication, application

os.environ["SEARCH_ALLOW_FALLBACK"] = "1"


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
    assert isinstance(application, (WSGIApplication, SecurityWSGIMiddleware))
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
    # SecurityWSGIMiddleware intercepts traversal before app and returns 400
    assert (
        status.startswith("400") or status.startswith("403") or status.startswith("404")
    )


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

    # Traversal should return 400 (SecurityWSGIMiddleware) or 403 (app-level)
    status, headers, body = call_wsgi(
        application, method="GET", path="/raw_data/../../../etc/passwd"
    )
    assert status.startswith("400") or status.startswith("403")


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


def test_wsgi_app_search_pagination_and_total_hits():
    """Validates /api/search response schema for total_hits, offset, limit, and has_more fields."""
    status, headers, body = call_wsgi(
        application,
        method="GET",
        path="/api/search",
        query_string="q=malware&top_k=2&offset=0",
    )
    assert status.startswith("200")
    data = json.loads(body.decode("utf-8"))
    assert data["status"] == "success"
    assert "total" in data
    assert "total_hits" in data
    assert "offset" in data
    assert data["offset"] == 0
    assert "limit" in data
    assert data["limit"] == 2
    assert "has_more" in data
    assert isinstance(data["has_more"], bool)

    # Offset query
    status2, headers2, body2 = call_wsgi(
        application,
        method="GET",
        path="/api/search",
        query_string="q=malware&limit=24&offset=24",
    )
    assert status2.startswith("200")
    data2 = json.loads(body2.decode("utf-8"))
    assert data2["offset"] == 24
    assert data2["limit"] == 24


def test_index_html_mcp_sandbox_default_json_validity():
    """Verifies that the static textarea in index.html contains valid JSON with query and top_k."""
    import re

    index_path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "site", "index.html")
    )
    assert os.path.exists(index_path), f"index.html not found at {index_path}"
    with open(index_path, "r", encoding="utf-8") as f:
        html_content = f.read()

    match = re.search(
        r'<textarea\s+id="mcpArgsInput"[^>]*>(.*?)</textarea>',
        html_content,
        re.DOTALL | re.IGNORECASE,
    )
    assert match is not None, "mcpArgsInput textarea not found in index.html"
    raw_json_str = match.group(1).strip()
    parsed = json.loads(raw_json_str)
    assert isinstance(parsed, dict)
    assert "query" in parsed
    assert "top_k" in parsed
    assert parsed["top_k"] == 5


def test_wsgi_app_post_mcp_ipc_isolation():
    """Verifies that POST /api/mcp executes via SearchClient IPC without loading VectorEngine in Web process."""
    from unittest.mock import MagicMock

    workspace_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    app = WSGIApplication(workspace_dir=workspace_dir, vector_engine=None)
    assert app.handlers._vector_engine is None

    mock_client = MagicMock()
    mock_client.search.return_value = {
        "status": "success",
        "results": [
            {
                "id": "2502.12345",
                "title": "Zero Bloat Security",
                "score": 0.99,
                "category": "cs.CR",
                "tags": ["zero-bloat", "ipc"],
                "description": "Abstract testing zero memory footprint",
            }
        ],
    }
    mock_client.get_related.return_value = {
        "status": "success",
        "paper_id": "2502.12345",
        "related_papers": [],
        "mermaid_graph": "graph TD; root[2502.12345]",
    }
    app.handlers._search_client = mock_client

    payload = {
        "name": "search_security_papers",
        "arguments": {"query": "zero bloat", "top_k": 1},
    }
    status, headers, body = call_wsgi(
        app, method="POST", path="/api/mcp", body=json.dumps(payload)
    )
    assert status.startswith("200")
    data = json.loads(body.decode("utf-8"))
    assert data["status"] == "success"
    assert len(data["result"]["results"]) == 1
    assert data["result"]["results"][0]["id"] == "2502.12345"
    assert app.handlers._vector_engine is None
    assert mock_client.search.called


def test_is_address_in_use_error():
    import errno

    from web.gateway.app import _is_address_in_use_error

    err_eaddrinuse = OSError(errno.EADDRINUSE, "Address already in use")
    assert _is_address_in_use_error(err_eaddrinuse) is True

    err_98 = OSError(98, "Address already in use")
    assert _is_address_in_use_error(err_98) is True

    err_text = OSError(1, "Address already in use on custom socket")
    assert _is_address_in_use_error(err_text) is True

    err_other = OSError(errno.ENOENT, "No such file or directory")
    assert _is_address_in_use_error(err_other) is False


def test_format_port_conflict_message():
    from web.gateway.app import _format_port_conflict_message

    msg_with_pid = _format_port_conflict_message("0.0.0.0", 8000, pid=12345)
    assert "8000" in msg_with_pid
    assert "12345" in msg_with_pid
    assert "kill 12345" in msg_with_pid
    assert "--auto-port" in msg_with_pid

    msg_without_pid = _format_port_conflict_message("127.0.0.1", 9000, pid=None)
    assert "9000" in msg_without_pid
    assert "make stop_supervisor" in msg_without_pid
    assert "--port 9001" in msg_without_pid


def test_bind_server_safe_single_port_conflict(monkeypatch):
    import errno
    import sys

    from web.gateway.app import _bind_server_safe

    app_mod = sys.modules["web.gateway.app"]

    def mock_try_bind(host, port):
        return None, OSError(errno.EADDRINUSE, "Address already in use")

    monkeypatch.setattr(app_mod, "_try_bind_single_port", mock_try_bind)
    monkeypatch.setattr(app_mod, "_find_pid_using_port", lambda p: 54321)

    server, port = _bind_server_safe("0.0.0.0", 8000, auto_port=False)
    assert server is None
    assert port == 8000


def test_bind_server_safe_auto_port(monkeypatch):
    import errno
    import sys
    from unittest.mock import MagicMock

    from web.gateway.app import _bind_server_safe

    app_mod = sys.modules["web.gateway.app"]
    mock_server = MagicMock()

    def mock_try_bind(host, port):
        if port == 8000:
            return None, OSError(errno.EADDRINUSE, "Address already in use")
        return mock_server, None

    monkeypatch.setattr(app_mod, "_try_bind_single_port", mock_try_bind)

    server, port = _bind_server_safe("0.0.0.0", 8000, auto_port=True, max_attempts=5)
    assert server == mock_server
    assert port == 8001


def test_run_web_server_port_conflict_exits(monkeypatch):
    import sys

    import pytest

    from web.gateway.app import run_web_server

    app_mod = sys.modules["web.gateway.app"]
    monkeypatch.setattr(
        app_mod,
        "_bind_server_safe",
        lambda host, port, auto_port, max_attempts: (None, port),
    )

    with pytest.raises(SystemExit) as exc_info:
        run_web_server(port=8000, host="0.0.0.0")
    assert exc_info.value.code == 1


def test_run_web_server_keyboard_interrupt_graceful(monkeypatch):
    import sys
    from unittest.mock import MagicMock

    from web.gateway.app import run_web_server

    app_mod = sys.modules["web.gateway.app"]
    mock_server = MagicMock()
    mock_server.serve_forever.side_effect = KeyboardInterrupt

    monkeypatch.setattr(
        app_mod,
        "_bind_server_safe",
        lambda host, port, auto_port, max_attempts: (mock_server, 8000),
    )

    run_web_server(port=8000, host="0.0.0.0")
    assert mock_server.server_close.called
