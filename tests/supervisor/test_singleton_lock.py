#!/usr/bin/env python3
"""Unit tests for Arbiter Singleton Lock and Process Duplicate Prevention."""

import os
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from supervisor.arbiter import Arbiter
from supervisor.cli import _handle_restart
from supervisor.config import SupervisorConfig


def test_single_instance_lock_acquisition_and_release(tmp_path: Any) -> None:
    """Tests acquiring and releasing exclusive file lock."""
    lock_file = str(tmp_path / "arbiter.lock")
    pid_file = str(tmp_path / "arbiter.pid")
    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        lock_file=lock_file,
        pid_file=pid_file,
    )
    arbiter = Arbiter(cfg)
    arbiter.acquire_single_instance_lock()
    assert os.path.exists(lock_file)
    with open(lock_file, "r", encoding="utf-8") as f:
        assert f.read().strip() == str(arbiter.pid)

    arbiter.release_single_instance_lock()
    assert not os.path.exists(lock_file)


def test_single_instance_lock_blocks_second_arbiter(tmp_path: Any) -> None:
    """Tests that a second Arbiter cannot start when lock is held by first Arbiter."""
    lock_file = str(tmp_path / "arbiter.lock")
    pid_file = str(tmp_path / "arbiter.pid")
    cfg1 = SupervisorConfig(
        workspace_dir=str(tmp_path),
        lock_file=lock_file,
        pid_file=pid_file,
    )
    arbiter1 = Arbiter(cfg1)
    arbiter1.acquire_single_instance_lock()

    cfg2 = SupervisorConfig(
        workspace_dir=str(tmp_path),
        lock_file=lock_file,
        pid_file=pid_file,
    )
    arbiter2 = Arbiter(cfg2)
    with pytest.raises(RuntimeError) as exc_info:
        arbiter2.acquire_single_instance_lock()
    assert "already running" in str(exc_info.value)

    # Cleanup
    arbiter1.release_single_instance_lock()


def test_check_existing_pid_detects_running_process(tmp_path: Any) -> None:
    """Tests _check_existing_pid raises when existing PID is alive."""
    pid_file = str(tmp_path / "arbiter.pid")
    # Write current PID into pid file
    with open(pid_file, "w", encoding="utf-8") as f:
        f.write(f"{os.getpid()}\n")

    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        pid_file=pid_file,
    )
    arbiter = Arbiter(cfg)
    # Different dummy PID
    arbiter.pid = 99999999
    with patch("os.kill") as mock_kill:
        mock_kill.return_value = None  # Process is alive
        with pytest.raises(RuntimeError) as exc_info:
            arbiter._check_existing_pid()
        assert "already running with PID" in str(exc_info.value)


def test_cli_restart_polls_and_cleans_old_process(tmp_path: Any) -> None:
    """Tests CLI _handle_restart waits for old PID shutdown and starts new."""
    lock_file = str(tmp_path / "arbiter.lock")
    pid_file = str(tmp_path / "arbiter.pid")
    control_sock = str(tmp_path / "control.sock")

    with open(pid_file, "w", encoding="utf-8") as f:
        f.write("12345\n")

    mock_args = MagicMock()
    mock_args.bind = None
    mock_args.workers = None
    mock_args.worker_class = None
    mock_args.threads = None
    mock_args.timeout = None
    mock_args.app = None
    mock_args.daemon = False
    mock_args.log_file = None
    mock_args.pid_file = pid_file

    cfg = SupervisorConfig(
        workspace_dir=str(tmp_path),
        pid_file=pid_file,
        lock_file=lock_file,
        control_socket=control_sock,
    )

    with patch("os.kill") as mock_kill, patch(
        "supervisor.cli._handle_start"
    ) as mock_start:
        # First call os.kill checks alive, second sends SIGTERM, next raises OSError (terminated)
        mock_kill.side_effect = [None, None, OSError("No such process")]
        mock_start.return_value = 0

        res = _handle_restart(mock_args, cfg, str(tmp_path), control_sock)
        assert res == 0
        assert mock_start.called
