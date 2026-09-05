#!/usr/bin/env python3
"""Unit tests for SyncWorker, GthreadWorker, AsyncWorker, and ManagedServiceWorker."""

import socket
import threading
import time
from typing import Any, Dict, List, Optional

from supervisor.config import SupervisorConfig
from supervisor.contracts import DefaultLifecycleHook
from supervisor.workers.async_worker import AsyncWorker
from supervisor.workers.gthread_worker import GthreadWorker
from supervisor.workers.service_worker import ManagedServiceWorker
from supervisor.workers.sync_worker import SyncWorker


def dummy_wsgi_app(environ: Dict[str, Any], start_response: Any) -> List[bytes]:
    status = "200 OK"
    headers = [("Content-Type", "application/json"), ("X-Test-Header", "Hello")]
    start_response(status, headers)
    return [
        b'{"message":"pong","path":"' + environ.get("PATH_INFO", "/").encode() + b'"}'
    ]


def test_sync_worker_client_handling() -> None:
    cfg = SupervisorConfig(bind_port=9981)
    worker = SyncWorker(
        worker_id="sync_test_01",
        config=cfg,
        app_target=dummy_wsgi_app,
    )

    client_s, server_s = socket.socketpair()
    try:
        client_s.sendall(b"GET /api/test?q=hello HTTP/1.1\r\nHost: localhost\r\n\r\n")
        worker.handle_client(server_s)

        resp = client_s.recv(4096)
        assert b"HTTP/1.1 200 OK" in resp
        assert b"X-Test-Header: Hello" in resp
        assert b'"path":"/api/test"' in resp
        assert worker.requests_handled == 1
    finally:
        client_s.close()


def test_gthread_worker_execution() -> None:
    cfg = SupervisorConfig(bind_port=9982, threads=2)
    worker = GthreadWorker(
        worker_id="gthread_test_01",
        config=cfg,
        app_target=dummy_wsgi_app,
    )

    client_s, server_s = socket.socketpair()
    try:
        client_s.sendall(
            b"POST /submit HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\ntest"
        )
        worker.handle_client(server_s)

        resp = client_s.recv(4096)
        assert b"HTTP/1.1 200 OK" in resp
        assert b'"path":"/submit"' in resp
        assert worker.requests_handled == 1
    finally:
        client_s.close()


def test_managed_service_worker_lifecycle(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    pulses: List[Optional[Dict[str, Any]]] = []
    flushed: List[bool] = []
    teared_down: List[bool] = []

    hook = DefaultLifecycleHook(
        setup_fn=lambda: True,
        health_fn=lambda: True,
        flush_fn=lambda: flushed.append(True),
        teardown_fn=lambda: teared_down.append(True),
    )

    worker = ManagedServiceWorker(
        worker_id="svc_test_01",
        config=cfg,
        service_name="custom_cache",
        hook=hook,
        sync_interval=0.1,
        pulse_callback=lambda pid, meta: pulses.append(meta),
    )

    t = threading.Thread(target=worker.run, daemon=True)
    t.start()

    time.sleep(0.3)
    worker.alive = False
    t.join(timeout=2.0)

    assert len(pulses) > 0
    assert pulses[0] is not None
    assert pulses[0]["service"] == "custom_cache"
    assert pulses[0]["is_healthy"] is True
    assert len(flushed) > 0
    assert len(teared_down) > 0


def test_async_worker_execution() -> None:
    cfg = SupervisorConfig(bind_port=9983)
    worker = AsyncWorker(
        worker_id="async_test_01",
        config=cfg,
        app_target=dummy_wsgi_app,
    )
    t = threading.Thread(target=worker.run, daemon=True)
    t.start()
    time.sleep(0.2)
    worker.alive = False
    t.join(timeout=2.0)
    assert worker.requests_handled == 0


def test_gthread_worker_run_loop() -> None:
    cfg = SupervisorConfig(bind_port=9984, threads=2)
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind(("127.0.0.1", 0))
    server_sock.listen(5)

    worker = GthreadWorker(
        worker_id="gthread_loop_01",
        config=cfg,
        server_socket=server_sock,
        app_target=dummy_wsgi_app,
    )

    t = threading.Thread(target=worker.run, daemon=True)
    t.start()
    time.sleep(0.2)
    worker.alive = False
    t.join(timeout=2.0)
    server_sock.close()


def test_sync_worker_run_loop() -> None:
    cfg = SupervisorConfig(bind_port=9985)
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind(("127.0.0.1", 0))
    server_sock.listen(5)

    worker = SyncWorker(
        worker_id="sync_loop_01",
        config=cfg,
        server_socket=server_sock,
        app_target=dummy_wsgi_app,
    )

    t = threading.Thread(target=worker.run, daemon=True)
    t.start()
    time.sleep(0.2)
    worker.alive = False
    t.join(timeout=2.0)
    server_sock.close()


def test_sync_worker_max_requests_retirement() -> None:
    cfg = SupervisorConfig(bind_port=9986)
    worker = SyncWorker(
        worker_id="sync_retire_req",
        config=cfg,
        app_target=dummy_wsgi_app,
        max_requests=2,
        max_requests_jitter=0,
    )
    assert worker.effective_max_requests == 2
    assert worker._should_retire() is False

    client_s1, server_s1 = socket.socketpair()
    try:
        client_s1.sendall(b"GET /req1 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        worker.handle_client(server_s1)
        assert worker.requests_handled == 1
        assert worker.alive is True
        assert worker._should_retire() is False
    finally:
        client_s1.close()

    client_s2, server_s2 = socket.socketpair()
    try:
        client_s2.sendall(b"GET /req2 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        worker.handle_client(server_s2)
        assert worker.requests_handled == 2
        assert worker.alive is False
        assert worker._should_retire() is True
    finally:
        client_s2.close()


def test_worker_lifetime_retirement() -> None:
    cfg = SupervisorConfig()
    worker = SyncWorker(
        worker_id="sync_retire_ttl",
        config=cfg,
        max_worker_lifetime=0.1,
        max_worker_lifetime_jitter=0.0,
    )
    assert worker.effective_max_lifetime == 0.1
    assert worker._should_retire() is False

    time.sleep(0.15)
    assert worker._should_retire() is True


def test_worker_jitter_bounds() -> None:
    cfg = SupervisorConfig()
    worker = SyncWorker(
        worker_id="sync_jitter",
        config=cfg,
        max_requests=100,
        max_requests_jitter=10,
        max_worker_lifetime=60.0,
        max_worker_lifetime_jitter=5.0,
    )
    assert 90 <= worker.effective_max_requests <= 110
    assert 55.0 <= worker.effective_max_lifetime <= 65.0


def test_gthread_worker_custom_threads() -> None:
    """Verifies that GthreadWorker honors explicit threads argument over config."""
    cfg = SupervisorConfig(threads=2)
    worker = GthreadWorker(
        worker_id="gthread_custom_threads",
        config=cfg,
        threads=6,
    )
    assert worker.num_threads == 6


def test_sync_worker_stream_chunks_loop_alive_check() -> None:
    """Verifies that SyncWorker._stream_chunks_loop exits immediately when self.alive is False."""
    cfg = SupervisorConfig()
    worker = SyncWorker(worker_id="sync_stream_alive_check", config=cfg)

    client_s, server_s = socket.socketpair()

    def infinite_chunks() -> Any:
        yield b"chunk1"
        worker.alive = False
        yield b"chunk2"
        yield b"chunk3"

    try:
        count = worker._stream_chunks_loop(server_s, infinite_chunks())
        assert count == 1
        data = client_s.recv(4096)
        assert data == b"chunk1"
    finally:
        client_s.close()
        server_s.close()
