"""Unit tests for Arbiter process manager and lifecycle orchestration."""

import os
from unittest.mock import MagicMock, patch

from supervisor.arbiter import Arbiter
from supervisor.config import SupervisorConfig


def test_arbiter_initialization(tmp_path) -> None:
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


def test_arbiter_control_commands(tmp_path) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path), workers=2)
    arbiter = Arbiter(cfg)

    # Ping
    ping_resp = arbiter.handle_control_command({"cmd": "ping"})
    assert ping_resp["status"] == "ok"
    assert ping_resp["message"] == "pong"

    # Status
    status_resp = arbiter.handle_control_command({"cmd": "status"})
    assert status_resp["status"] == "ok"
    assert status_resp["target_workers"] == 2

    # Scale
    scale_resp = arbiter.handle_control_command({"cmd": "scale", "workers": 5})
    assert scale_resp["status"] == "ok"
    assert scale_resp["target_workers"] == 5
    assert arbiter.config.workers == 5

    # Scale invalid
    scale_err = arbiter.handle_control_command({"cmd": "scale", "workers": 0})
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


def test_arbiter_hung_workers_kill(tmp_path) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path), timeout=0.1)
    arbiter = Arbiter(cfg)

    # Register mock worker
    arbiter.web_workers[99999] = MagicMock()
    arbiter.watchdog.register_worker(99999, "sync")

    with patch("os.kill") as mock_kill, patch.object(
        arbiter, "spawn_worker"
    ) as mock_spawn:
        arbiter.running = True
        arbiter.check_hung_workers()
        # Not hung yet
        mock_kill.assert_not_called()

        # Simulate timeout
        arbiter.watchdog._heartbeats[99999] = 0.0
        arbiter.check_hung_workers()
        mock_kill.assert_called_once_with(99999, 9)  # SIGKILL = 9
        mock_spawn.assert_called_once_with("web")


def test_arbiter_shutdown_clean(tmp_path) -> None:
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        pid_file=str(tmp_path / "test.pid"),
        control_socket=str(tmp_path / "test.sock"),
    )
    arbiter = Arbiter(cfg)
    arbiter.running = True

    # Create dummy pid file
    with open(cfg.pid_file, "w") as f:
        f.write("1234")

    with patch("os.kill"):
        arbiter.shutdown()

    assert not os.path.exists(cfg.pid_file)
    assert arbiter.running is False
