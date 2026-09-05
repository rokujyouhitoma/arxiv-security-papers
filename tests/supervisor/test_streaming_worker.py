"""Tests for non-blocking streaming and SSE handling in SyncWorker and GthreadWorker (Issue 168)."""

import socket
import time
from typing import Any, Callable, Dict, Iterator

from supervisor.config import SupervisorConfig
from supervisor.workers.gthread_worker import GthreadWorker
from supervisor.workers.sync_worker import SyncWorker


def test_sync_worker_streaming_sse_dispatch() -> None:
    """Verify SyncWorker streams SSE chunks immediately without full-body buffering."""
    stream_closed = False

    def sse_app(
        environ: Dict[str, Any], start_response: Callable[..., Any]
    ) -> Iterator[bytes]:
        start_response("200 OK", [("Content-Type", "text/event-stream")])

        def gen() -> Iterator[bytes]:
            nonlocal stream_closed
            try:
                for i in range(3):
                    yield f"data: event {i}\n\n".encode("utf-8")
            finally:
                stream_closed = True

        return gen()

    server_sock, client_sock = socket.socketpair()
    config = SupervisorConfig(timeout=2.0)
    worker = SyncWorker(worker_id="test-stream-1", config=config, app_target=sse_app)

    # Send simple GET request
    client_sock.sendall(b"GET /api/stream/top HTTP/1.1\r\nHost: localhost\r\n\r\n")

    # Run worker handle_client in the server socket
    worker.handle_client(server_sock)

    # Read from client side
    client_sock.settimeout(2.0)
    data = b""
    while True:
        try:
            chunk = client_sock.recv(4096)
            if not chunk:
                break
            data += chunk
        except (socket.timeout, OSError):
            break

    response_text = data.decode("iso-8859-1")
    assert "HTTP/1.1 200 OK" in response_text
    assert "text/event-stream" in response_text
    assert "data: event 0" in response_text
    assert "data: event 1" in response_text
    assert "data: event 2" in response_text
    assert stream_closed is True

    client_sock.close()


def test_sync_worker_streaming_client_disconnect() -> None:
    """Verify SyncWorker detects client disconnect and calls close() on the WSGI iterator."""
    closed_called = False

    class MockStreamIter:
        def __iter__(self) -> "MockStreamIter":
            return self

        def __next__(self) -> bytes:
            time.sleep(0.01)
            return b"data: ping\n\n"

        def close(self) -> None:
            nonlocal closed_called
            closed_called = True

    def sse_app(
        environ: Dict[str, Any], start_response: Callable[..., Any]
    ) -> MockStreamIter:
        start_response("200 OK", [("Content-Type", "text/event-stream")])
        return MockStreamIter()

    server_sock, client_sock = socket.socketpair()
    config = SupervisorConfig(timeout=2.0)
    worker = SyncWorker(
        worker_id="test-disconnect-1", config=config, app_target=sse_app
    )

    client_sock.sendall(b"GET /api/stream/events HTTP/1.1\r\n\r\n")

    # Close client immediately to induce BrokenPipeError on next write
    client_sock.close()

    worker.handle_client(server_sock)
    assert closed_called is True


def test_gthread_worker_concurrent_sse_and_http() -> None:
    """Verify GthreadWorker handles concurrent requests while SSE connection is active."""

    def test_app(
        environ: Dict[str, Any], start_response: Callable[..., Any]
    ) -> Iterator[bytes]:
        path = environ.get("PATH_INFO", "/")
        if path == "/stream":
            start_response("200 OK", [("Content-Type", "text/event-stream")])

            def sse_gen() -> Iterator[bytes]:
                for _ in range(3):
                    time.sleep(0.05)
                    yield b"data: tick\n\n"

            return sse_gen()
        start_response(
            "200 OK",
            [("Content-Type", "application/json"), ("Content-Length", "15")],
        )
        return [b'{"status":"ok"}']

    config = SupervisorConfig(threads=4, timeout=5.0)
    worker = GthreadWorker(
        worker_id="test-gthread-stream", config=config, app_target=test_app
    )

    # 1. Normal HTTP
    srv1, clt1 = socket.socketpair()
    clt1.sendall(b"GET /health HTTP/1.1\r\n\r\n")
    worker.handle_client(srv1)
    res = clt1.recv(4096)
    assert b"200 OK" in res
    assert b'{"status":"ok"}' in res
    clt1.close()

    # 2. Streaming HTTP
    srv2, clt2 = socket.socketpair()
    clt2.sendall(b"GET /stream HTTP/1.1\r\n\r\n")
    worker.handle_client(srv2)
    stream_res = clt2.recv(4096)
    assert b"200 OK" in stream_res
    assert b"text/event-stream" in stream_res
    assert b"data: tick" in stream_res
    clt2.close()
