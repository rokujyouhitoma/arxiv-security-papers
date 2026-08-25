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
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path), timeout=0.1, request_timeout=0.1
    )
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

        # Simulate timeout — mark as actively handling a request so hung detection fires
        arbiter.watchdog._worker_meta[99999]["is_handling_request"] = True
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


# ---------------------------------------------------------------------------
# Issue 071 — regression tests
# ---------------------------------------------------------------------------


def test_idle_workers_not_hung(tmp_path) -> None:
    """IDLE ワーカー（is_handling_request=False）は hung 判定されないことを確認する。

    pulse_callback が届かない状況でも IDLE なワーカーを SIGKILL しないことが
    Arbiter クラッシュの主要な根本原因修正の核心である。
    """
    cfg = SupervisorConfig(workspace_dir=str(tmp_path), request_timeout=0.01)
    arbiter = Arbiter(cfg)

    # Register a worker and let its heartbeat expire
    arbiter.watchdog.register_worker(77777, "sync")
    arbiter.web_workers[77777] = MagicMock()
    # Force the heartbeat timestamp to be very old
    arbiter.watchdog._heartbeats[77777] = 0.0
    # is_handling_request is NOT set (defaults to False / absent)

    with patch("os.kill") as mock_kill:
        arbiter.running = True
        arbiter.check_hung_workers()
        # IDLE worker must NOT be killed
        mock_kill.assert_not_called()


def test_arbiter_control_sock_removed_on_shutdown(tmp_path) -> None:
    """Arbiter.shutdown() 後に control.sock が自動削除されることを確認する。"""
    sock_path = str(tmp_path / "control.sock")
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        control_socket=sock_path,
    )
    arbiter = Arbiter(cfg)
    arbiter.running = True

    # Start the control server (creates the socket file)
    arbiter._start_control_server()
    assert os.path.exists(
        sock_path
    ), "control.sock must exist after _start_control_server()"

    with patch("os.kill"):
        arbiter.shutdown()

    assert not os.path.exists(
        sock_path
    ), "control.sock must be deleted after shutdown()"


def test_check_hung_workers_respawns_db_correctly(tmp_path) -> None:
    """hung になった DB ワーカーは 'db' として再起動されることを確認する（'web' ではなく）。"""
    cfg = SupervisorConfig(workspace_dir=str(tmp_path), request_timeout=0.01)
    arbiter = Arbiter(cfg)

    # Register a DB worker that is actively handling a request
    arbiter.watchdog.register_worker(88888, "database")
    # Mark as handling a request so it qualifies for hung detection
    arbiter.watchdog._worker_meta[88888]["is_handling_request"] = True
    arbiter.watchdog._heartbeats[88888] = 0.0  # expired
    arbiter.db_workers[88888] = MagicMock()

    with patch("os.kill"), patch.object(arbiter, "spawn_worker") as mock_spawn:
        arbiter.running = True
        arbiter.check_hung_workers()
        # Must respawn as 'db', not 'web'
        mock_spawn.assert_called_once_with("db")


def test_arbiter_main_loop_exception_cleanup(tmp_path, caplog) -> None:
    """Arbiter メインループで予期せぬ例外が発生しても control.sock が削除され critical ログが出力されることを確認する。"""
    import logging

    sock_path = str(tmp_path / "control.sock")
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        control_socket=sock_path,
        manage_database=False,
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

    assert not os.path.exists(
        sock_path
    ), "control.sock must be deleted after abnormal loop exit"
    assert "Unexpected crash in main event loop" in caplog.text
