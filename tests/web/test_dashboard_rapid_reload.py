"""
Unit and integration tests for Dashboard rapid reload concurrency and ThreadingWSGIServer non-blocking resilience.
Verifies that Server-Sent Events (SSE) streaming does not block concurrent HTTP GET requests.
"""

from __future__ import annotations

import os
import socket
import threading
import time
import urllib.error
import urllib.request
from typing import Generator
from wsgiref.simple_server import make_server

import pytest

from web.gateway.app import ThreadingWSGIServer, WSGIApplication


def _get_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


@pytest.fixture
def running_threaded_server() -> Generator[str, None, None]:
    """Spins up a real ThreadingWSGIServer instance on a free localhost port."""
    workspace_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    app = WSGIApplication(workspace_dir=workspace_dir)
    port = _get_free_port()
    httpd = make_server("127.0.0.1", port, app, server_class=ThreadingWSGIServer)

    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()

    base_url = f"http://127.0.0.1:{port}"
    # Wait for server to accept connections
    for _ in range(50):
        try:
            with urllib.request.urlopen(f"{base_url}/api/stats", timeout=0.5):
                break
        except Exception:
            time.sleep(0.05)

    yield base_url

    httpd.shutdown()
    httpd.server_close()


def test_threading_wsgi_server_structure() -> None:
    """Verifies that ThreadingWSGIServer is properly configured with daemon threads."""
    from socketserver import ThreadingMixIn
    from wsgiref.simple_server import WSGIServer

    assert issubclass(ThreadingWSGIServer, ThreadingMixIn)
    assert issubclass(ThreadingWSGIServer, WSGIServer)
    assert ThreadingWSGIServer.daemon_threads is True
    assert ThreadingWSGIServer.allow_reuse_address is True


def test_concurrent_sse_and_rapid_dashboard_reload(
    running_threaded_server: str,
) -> None:
    """
    Verifies that an active SSE stream does NOT block concurrent rapid reload requests to /dashboard.
    """
    base_url = running_threaded_server
    stop_event = threading.Event()
    sse_connected = threading.Event()

    sse_resp = None

    def sse_client() -> None:
        nonlocal sse_resp
        url = f"{base_url}/api/stream/top?interval=0.2"
        try:
            req = urllib.request.Request(url, headers={"Accept": "text/event-stream"})
            sse_resp = urllib.request.urlopen(req, timeout=5.0)
            sse_connected.set()
            # Read chunks until stopped
            while not stop_event.is_set():
                line = sse_resp.readline()
                if not line:
                    break
        except Exception:
            pass
        finally:
            if sse_resp:
                try:
                    sse_resp.close()
                except Exception:
                    pass

    # 1. Start persistent SSE client in a background thread
    t_sse = threading.Thread(target=sse_client, daemon=True)
    t_sse.start()

    # Wait until SSE connection is established
    assert sse_connected.wait(timeout=3.0), "SSE stream failed to connect"

    # 2. Concurrently execute 10 rapid reload GET requests to /dashboard
    latencies = []
    for _ in range(10):
        t0 = time.perf_counter()
        req = urllib.request.Request(f"{base_url}/dashboard")
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            content = resp.read()
            status = resp.status
        dt = time.perf_counter() - t0
        latencies.append(dt)

        assert status == 200
        assert b"<!DOCTYPE html>" in content
        assert b"graphCanvas" in content
        # Must be very fast (under 500ms) without any blocking
        assert dt < 0.5, f"Request took too long: {dt:.3f}s"

    # 3. Clean up SSE stream
    stop_event.set()
    if sse_resp:
        try:
            sse_resp.close()
        except Exception:
            pass
    t_sse.join(timeout=1.0)


def test_dashboard_html_contains_unload_cleanup() -> None:
    """Verifies that site/dashboard.html contains beforeunload/pagehide event handlers to close EventSource."""
    path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "site", "dashboard.html")
    )
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "beforeunload" in content
    assert "pagehide" in content
    assert "sseEventSource.close()" in content
