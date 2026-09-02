#!/usr/bin/env python3
"""Unit tests for Arbiter process manager and lifecycle orchestration."""

import os
import signal
from typing import Any
from unittest.mock import MagicMock, patch

from supervisor.arbiter import Arbiter
from supervisor.config import PoolConfig, ServiceConfig, SupervisorConfig
from supervisor.contracts import ServiceRole, WorkerSpec


def test_arbiter_initialization(tmp_path: Any) -> None:
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        bind_port=9991,
        workers=3,
        worker_class="sync",
    )
    arbiter = Arbiter(cfg)
    assert arbiter.config.workers == 3
    assert arbiter.server_socket is None

    sock = arbiter.init_server_socket()
    assert sock is not None
    assert arbiter.server_socket is not None
    sock.close()
    arbiter.server_socket = None


def test_arbiter_control_commands(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path), workers=2)
    arbiter = Arbiter(cfg)

    # Ping
    ping_resp = arbiter.handle_control_command({"cmd": "ping"})
    assert ping_resp["status"] == "ok"
    assert ping_resp["message"] == "pong"

    # Status
    status_resp = arbiter.handle_control_command({"cmd": "status"})
    assert status_resp["status"] == "ok"
    assert "pools" in status_resp

    # Scale
    scale_resp = arbiter.handle_control_command(
        {"cmd": "scale", "pool": "default", "workers": 5}
    )
    assert scale_resp["status"] == "ok"
    assert scale_resp["target_workers"] == 5
    assert arbiter.pools["default"].target_count == 5

    # Scale invalid
    scale_err = arbiter.handle_control_command(
        {"cmd": "scale", "pool": "default", "workers": 0}
    )
    assert scale_err["status"] == "error"

    # Reload
    with patch.object(arbiter, "reload") as mock_reload:
        reload_resp = arbiter.handle_control_command({"cmd": "reload"})
        assert reload_resp["status"] == "ok"
        mock_reload.assert_called_once()

    # Stop
    stop_resp = arbiter.handle_control_command({"cmd": "stop"})
    assert stop_resp["status"] == "ok"
    assert arbiter.running is False

    # Unknown
    unknown_resp = arbiter.handle_control_command({"cmd": "non_existent"})
    assert unknown_resp["status"] == "error"


def test_arbiter_hung_workers_kill(tmp_path: Any) -> None:
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path), timeout=0.1, request_timeout=0.1
    )
    arbiter = Arbiter(cfg)

    # Register mock worker in default pool
    arbiter.pools["default"].workers[99999] = MagicMock()
    arbiter.watchdog.register_worker(99999, "default")

    with patch("os.kill") as mock_kill, patch.object(
        arbiter, "spawn_worker"
    ) as mock_spawn:
        arbiter.running = True
        arbiter.check_hung_workers()
        mock_kill.assert_not_called()

        # Simulate timeout — mark as actively handling a request
        arbiter.watchdog._worker_meta[99999]["is_handling_request"] = True
        arbiter.watchdog._heartbeats[99999] = 0.0
        arbiter.check_hung_workers()
        mock_kill.assert_called_once_with(99999, 9)  # SIGKILL = 9
        mock_spawn.assert_called_once_with("default")


def test_arbiter_shutdown_clean(tmp_path: Any) -> None:
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        pid_file=str(tmp_path / "test.pid"),
        control_socket=str(tmp_path / "test.sock"),
    )
    arbiter = Arbiter(cfg)
    arbiter.running = True

    with open(cfg.pid_file, "w") as f:
        f.write("1234")

    with patch("os.kill"):
        arbiter.shutdown()

    assert not os.path.exists(cfg.pid_file)
    assert arbiter.running is False


def test_idle_workers_not_hung(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path), request_timeout=0.01)
    arbiter = Arbiter(cfg)

    arbiter.watchdog.register_worker(77777, "default")
    arbiter.pools["default"].workers[77777] = MagicMock()
    arbiter.watchdog._heartbeats[77777] = 0.0

    with patch("os.kill") as mock_kill:
        arbiter.running = True
        arbiter.check_hung_workers()
        mock_kill.assert_not_called()


def test_arbiter_control_sock_removed_on_shutdown(tmp_path: Any) -> None:
    sock_path = str(tmp_path / "control.sock")
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        control_socket=sock_path,
    )
    arbiter = Arbiter(cfg)
    arbiter.running = True

    arbiter._start_control_server()
    assert os.path.exists(sock_path)

    with patch("os.kill"):
        arbiter.shutdown()

    assert not os.path.exists(sock_path)


def test_check_hung_workers_respawns_service_pool_correctly(tmp_path: Any) -> None:
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        services=[ServiceConfig(name="indexer_service", workers=1)],
        request_timeout=0.01,
    )
    arbiter = Arbiter(cfg)

    arbiter.watchdog.register_worker(88888, "indexer_service")
    arbiter.watchdog._worker_meta[88888]["is_handling_request"] = True
    arbiter.watchdog._heartbeats[88888] = 0.0
    arbiter.pools["indexer_service"].workers[88888] = MagicMock()

    with patch("os.kill"), patch.object(arbiter, "spawn_worker") as mock_spawn:
        arbiter.running = True
        arbiter.check_hung_workers()
        mock_spawn.assert_called_once_with("indexer_service")


def test_arbiter_main_loop_exception_cleanup(tmp_path: Any, caplog: Any) -> None:
    import logging

    sock_path = str(tmp_path / "control.sock")
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        control_socket=sock_path,
        workers=1,
    )
    arbiter = Arbiter(cfg)

    with patch.object(
        arbiter,
        "_handle_queued_signals",
        side_effect=RuntimeError("Simulated loop crash"),
    ), patch.object(arbiter, "init_signals"), patch.object(
        arbiter, "init_server_socket"
    ), patch.object(
        arbiter, "load_wsgi_app"
    ), patch.object(
        arbiter, "spawn_worker"
    ), patch(
        "os.kill"
    ):
        with caplog.at_level(logging.CRITICAL):
            arbiter.start()

    assert not os.path.exists(sock_path)
    assert "Unexpected crash in main event loop" in caplog.text


def test_arbiter_scale_multi_pool_isolation(tmp_path: Any) -> None:
    """異なる複数プール（stateless / service）が独立してスケーリングできることを検証する。"""
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        pools=[PoolConfig(name="http_pool", workers=2)],
        services=[ServiceConfig(name="cache_sync", workers=3)],
    )
    arbiter = Arbiter(cfg)

    arbiter.pools["http_pool"].workers = {1001: MagicMock(), 1002: MagicMock()}
    arbiter.pools["cache_sync"].workers = {
        2001: MagicMock(),
        2002: MagicMock(),
        2003: MagicMock(),
    }

    with patch.object(arbiter, "spawn_worker") as mock_spawn:
        res = arbiter.handle_control_command(
            {"cmd": "scale", "pool": "http_pool", "workers": 4}
        )
        assert res["status"] == "ok"
        assert res["target_pool"] == "http_pool"
        assert res["target_workers"] == 4
        assert arbiter.pools["http_pool"].target_count == 4
        assert arbiter.pools["cache_sync"].target_count == 3
        assert mock_spawn.call_count == 2
        mock_spawn.assert_called_with("http_pool")

    with patch("os.kill") as mock_kill:
        res = arbiter.handle_control_command(
            {"cmd": "scale", "pool": "cache_sync", "workers": 1}
        )
        assert res["status"] == "ok"
        assert res["target_pool"] == "cache_sync"
        assert res["target_workers"] == 1
        assert arbiter.pools["cache_sync"].target_count == 1
        assert arbiter.pools["http_pool"].target_count == 4
        assert mock_kill.call_count == 2
        for call_args in mock_kill.call_args_list:
            assert call_args[0][0] in (2001, 2002, 2003)
            assert call_args[0][1] == signal.SIGTERM


def test_arbiter_scale_unknown_pool(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    arbiter = Arbiter(cfg)
    res = arbiter.handle_control_command(
        {"cmd": "scale", "pool": "invalid_pool_name", "workers": 2}
    )
    assert res["status"] == "error"
    assert "Unknown target worker pool" in res["error"]


def test_arbiter_load_wsgi_app_fallback(tmp_path: Any) -> None:
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path), app_uri="invalid.module:non_existent"
    )
    arbiter = Arbiter(cfg)
    app = arbiter.load_wsgi_app()
    assert callable(app)

    status_captured = []
    headers_captured = []

    def start_response(status: str, headers: Any) -> None:
        status_captured.append(status)
        headers_captured.append(headers)

    resp = app({}, start_response)
    assert status_captured == ["200 OK"]
    assert b"Supervisor Active" in resp[0]


def test_arbiter_signal_handling(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path), workers=2)
    arbiter = Arbiter(cfg)
    arbiter.init_signals()

    # SIGHUP reloads
    arbiter._signal_queue.append(signal.SIGHUP)
    with patch.object(arbiter, "reload") as mock_reload:
        arbiter._handle_queued_signals()
        mock_reload.assert_called_once()

    # SIGTERM terminates
    arbiter.running = True
    arbiter._signal_queue.append(signal.SIGTERM)
    arbiter._handle_queued_signals()
    assert arbiter.running is False


def test_arbiter_custom_worker_specs_and_dynamic_scaling(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    custom_specs = [
        WorkerSpec(
            name="collector",
            target_count=2,
            worker_class="service",
            role=ServiceRole.STATEFUL_SERVICE,
        ),
        WorkerSpec(
            name="indexer",
            target_count=1,
            worker_class="service",
            role=ServiceRole.STATEFUL_SERVICE,
        ),
        WorkerSpec(
            name="api_gateway",
            target_count=3,
            worker_class="sync",
            role=ServiceRole.STATELESS_POOL,
        ),
    ]

    arbiter = Arbiter(config=cfg, specs=custom_specs)
    assert len(arbiter.pools) == 3
    assert "collector" in arbiter.pools
    assert "indexer" in arbiter.pools
    assert "api_gateway" in arbiter.pools

    # Scale collector pool dynamically
    with patch.object(arbiter, "spawn_worker") as mock_spawn:
        arbiter.scale("collector", 5)
        assert arbiter.pools["collector"].target_count == 5
        assert mock_spawn.call_count == 5

    # Scale via IPC control command
    with patch.object(arbiter, "spawn_worker") as mock_spawn:
        scale_res = arbiter.handle_control_command(
            {"cmd": "scale", "pool": "api_gateway", "workers": 4}
        )
        assert scale_res["status"] == "ok"
        assert scale_res["target_pool"] == "api_gateway"
        assert scale_res["target_workers"] == 4
        assert arbiter.pools["api_gateway"].target_count == 4

    # Status shows all pools
    status_res = arbiter.handle_control_command({"cmd": "status"})
    assert status_res["status"] == "ok"
    assert "pools" in status_res
    assert "collector" in status_res["pools"]
    assert "indexer" in status_res["pools"]
    assert "api_gateway" in status_res["pools"]


def test_arbiter_daemonize_mocked(tmp_path: Any) -> None:
    log_file = str(tmp_path / "daemon.log")
    pid_file = str(tmp_path / "daemon.pid")
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        daemon=True,
        log_file=log_file,
        pid_file=pid_file,
    )
    arbiter = Arbiter(cfg)

    with patch("os.fork", side_effect=[0, 0]) as mock_fork, patch(
        "os.setsid"
    ) as mock_setsid, patch("os.umask") as mock_umask, patch("os.dup2") as mock_dup2:
        arbiter.daemonize()
        assert mock_fork.call_count == 2
        mock_setsid.assert_called_once()
        mock_umask.assert_called_once_with(0)
        assert mock_dup2.call_count >= 2

    arbiter.release_single_instance_lock()


def test_arbiter_existing_pid_check(tmp_path: Any) -> None:
    import pytest

    pid_file = tmp_path / "running.pid"
    pid_file.write_text("999999", encoding="utf-8")
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        pid_file=str(pid_file),
    )
    arbiter = Arbiter(cfg)

    # When os.kill(999999, 0) succeeds (process alive)
    with patch("os.kill") as mock_kill:
        mock_kill.return_value = None
        with pytest.raises(RuntimeError, match="already running with PID 999999"):
            arbiter._check_existing_pid()

    # When os.kill raises ProcessLookupError (process dead / stale PID)
    with patch("os.kill", side_effect=ProcessLookupError):
        # Should not raise exception
        arbiter._check_existing_pid()


def test_arbiter_service_level_restart(tmp_path: Any) -> None:
    specs = [
        WorkerSpec(name="web", target_count=2, role=ServiceRole.STATELESS_POOL),
        WorkerSpec(name="search", target_count=1, role=ServiceRole.STATEFUL_SERVICE),
    ]
    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    arbiter = Arbiter(config=cfg, specs=specs)

    # Mock workers
    arbiter.pools["web"].workers[101] = MagicMock()
    arbiter.pools["web"].workers[102] = MagicMock()
    arbiter.pools["search"].workers[201] = MagicMock()

    with patch("os.kill") as mock_kill, patch.object(
        arbiter, "spawn_worker"
    ) as mock_spawn:
        # 1. Restart stateless pool (web) -> rolling reload
        res_web = arbiter.restart(target="web")
        assert res_web["status"] == "ok"
        assert res_web["mode"] == "rolling"
        assert mock_spawn.call_count == 2
        assert mock_kill.call_count == 2
        mock_kill.assert_any_call(101, signal.SIGQUIT)
        mock_kill.assert_any_call(102, signal.SIGQUIT)

    with patch("os.kill") as mock_kill:
        # 2. Restart stateful service (search) -> SIGTERM graceful teardown
        res_search = arbiter.restart(target="search")
        assert res_search["status"] == "ok"
        assert res_search["mode"] == "graceful_teardown"
        mock_kill.assert_called_once_with(201, signal.SIGTERM)

    # 3. Restart nonexistent target
    res_err = arbiter.restart(target="nonexistent")
    assert res_err["status"] == "error"
    assert "not found" in res_err["error"]

    with patch.object(arbiter, "_restart_pool_by_role") as mock_restart_role:
        # 4. Restart all
        res_all = arbiter.restart(restart_all=True)
        assert res_all["status"] == "ok"
        assert len(res_all["restarted_pools"]) == 2
        assert mock_restart_role.call_count == 2


def test_arbiter_restart_control_command(tmp_path: Any) -> None:
    specs = [
        WorkerSpec(name="web", target_count=2, role=ServiceRole.STATELESS_POOL),
    ]
    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    arbiter = Arbiter(config=cfg, specs=specs)

    with patch.object(
        arbiter, "restart", return_value={"status": "ok", "message": "restarted"}
    ) as mock_restart:
        resp = arbiter.handle_control_command(
            {"cmd": "restart", "target": "web", "mode": "rolling"}
        )
        assert resp["status"] == "ok"
        mock_restart.assert_called_once_with(
            target="web", mode="rolling", restart_all=False
        )
