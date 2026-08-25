"""Unit tests for SyncWorker, GthreadWorker, AsyncWorker, ManagedServiceWorker, and DatabaseWorker."""

import socket
import threading
import time
from typing import Any, Dict, List

from supervisor.config import SupervisorConfig
from supervisor.contracts import DefaultLifecycleHook
from supervisor.workers.async_worker import AsyncWorker
from supervisor.workers.gthread_worker import GthreadWorker
from supervisor.workers.service_worker import DatabaseWorker, ManagedServiceWorker
from supervisor.workers.sync_worker import SyncWorker


def dummy_wsgi_app(environ: Dict[str, Any], start_response) -> List[bytes]:
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


def test_managed_service_worker_lifecycle(tmp_path) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    pulses = []
    flushed = []
    teared_down = []

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
    assert worker.db_ready is True
    worker.alive = False
    t.join(timeout=2.0)

    assert len(pulses) > 0
    assert pulses[0]["service"] == "custom_cache"
    assert pulses[0]["is_healthy"] is True
    assert len(flushed) > 0
    assert len(teared_down) > 0


def test_database_worker_subclass(tmp_path) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    pulses = []

    worker = DatabaseWorker(
        worker_id="db_test_01",
        config=cfg,
        pulse_callback=lambda pid, meta: pulses.append(meta),
    )

    t = threading.Thread(target=worker.run, daemon=True)
    t.start()

    time.sleep(0.2)
    assert worker.db_ready is True
    worker.alive = False
    t.join(timeout=2.0)

    assert len(pulses) > 0
    assert pulses[0]["service"] == "database"


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


def test_dedicated_db_worker_module(tmp_path) -> None:
    from supervisor.workers.db_worker import DatabaseWorker as DedicatedDBWorker

    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    pulses = []

    worker = DedicatedDBWorker(
        worker_id="dedicated_db_01",
        config=cfg,
        pulse_callback=lambda pid, meta: pulses.append(meta),
    )
    assert worker._verify_storage_health() is True
    worker._flush_and_checkpoint()
    assert worker.checkpoints_completed == 1

    t = threading.Thread(target=worker.run, daemon=True)
    t.start()
    time.sleep(0.2)
    assert worker.db_ready is True
    worker.alive = False
    t.join(timeout=2.0)

    assert len(pulses) > 0
    assert pulses[0]["subsystem"] == "database"


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
