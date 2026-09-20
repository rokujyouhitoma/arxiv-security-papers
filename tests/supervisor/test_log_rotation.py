"""
Unit Tests for Supervisor Log Unification and RotatingFileHandler.
Validates outputs/logs/supervisor.log target, rotation limits, and src/ isolation.
"""

import logging
import os
from logging.handlers import RotatingFileHandler
from typing import Any

from supervisor.arbiter import Arbiter
from supervisor.config import SupervisorConfig


def test_supervisor_config_path_unification(tmp_path: Any) -> None:
    ws = str(tmp_path)
    # 1. Daemon mode default log location
    cfg = SupervisorConfig(workspace_dir=ws, daemon=True)
    expected_log = os.path.join(ws, "outputs", "logs", "supervisor.log")
    assert cfg.log_file == expected_log
    assert cfg.pid_file == os.path.join(ws, "outputs", "supervisor", "arbiter.pid")
    assert cfg.control_socket == os.path.join(
        ws, "outputs", "supervisor", "control.sock"
    )

    # 2. Legacy supervisor.log redirection
    legacy_cfg = SupervisorConfig(
        workspace_dir=ws, log_file="outputs/supervisor/supervisor.log"
    )
    assert legacy_cfg.log_file == expected_log

    # 3. Custom absolute log file preservation
    custom_cfg = SupervisorConfig(workspace_dir=ws, log_file="/tmp/custom_app.log")
    assert custom_cfg.log_file == "/tmp/custom_app.log"


def test_arbiter_setup_logging_rotating_file_handler(tmp_path: Any) -> None:
    ws = str(tmp_path)
    cfg = SupervisorConfig(
        workspace_dir=ws, daemon=True, log_file=str(tmp_path / "test_sup.log")
    )
    arbiter = Arbiter(config=cfg)
    assert arbiter is not None

    root_logger = logging.getLogger()
    handlers = [
        h
        for h in root_logger.handlers
        if isinstance(h, RotatingFileHandler)
        and getattr(h, "baseFilename", None) == os.path.abspath(str(cfg.log_file))
    ]
    assert len(handlers) >= 1
    handler = handlers[0]
    assert handler.maxBytes == 10 * 1024 * 1024
    assert handler.backupCount == 3


def test_arbiter_log_rotation_execution(tmp_path: Any) -> None:
    ws = str(tmp_path)
    log_file = str(tmp_path / "rotation_test.log")
    cfg = SupervisorConfig(workspace_dir=ws, log_file=log_file)
    arbiter = Arbiter(config=cfg)

    # Create dummy log content exceeding max_bytes (e.g. 100 bytes threshold)
    with open(log_file, "w", encoding="utf-8") as f:
        f.write("A" * 200)

    # Trigger rotation with max_bytes=100
    arbiter._check_and_rotate_log(max_bytes=100, backup_count=3)

    assert os.path.exists(f"{log_file}.1")
    with open(f"{log_file}.1", "r", encoding="utf-8") as f:
        assert f.read() == "A" * 200


def test_supervisor_runtime_does_not_create_src_outputs(tmp_path: Any) -> None:
    from settings import BASE_DIR

    src_outputs = os.path.join(BASE_DIR, "src", "outputs")
    assert not os.path.exists(src_outputs), "src/outputs must not exist"

    cfg = SupervisorConfig(workspace_dir=BASE_DIR)
    arbiter = Arbiter(config=cfg)
    assert arbiter is not None
    assert not os.path.exists(src_outputs), "Arbiter init must not create src/outputs"
