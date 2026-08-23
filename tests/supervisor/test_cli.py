"""Unit tests for Supervisor CLI entry point and subcommands."""

from unittest.mock import MagicMock, patch

from supervisor.cli import build_parser, main, parse_bind


def test_build_parser_structure() -> None:
    parser = build_parser()
    assert parser.prog == "supervisor"

    subparsers_action = next(a for a in parser._actions if a.dest == "command")
    choices = subparsers_action.choices
    assert "start" in choices
    assert "status" in choices
    assert "scale" in choices
    assert "reload" in choices
    assert "stop" in choices
    assert "ping" in choices


def test_parse_bind() -> None:
    h1, p1 = parse_bind("127.0.0.1:9000")
    assert h1 == "127.0.0.1"
    assert p1 == 9000

    h2, p2 = parse_bind("8080")
    assert h2 == "0.0.0.0"
    assert p2 == 8080


def test_cli_ipc_commands(tmp_path) -> None:
    sock_path = str(tmp_path / "control.sock")

    with patch("supervisor.cli.ControlClient") as mock_client_cls:
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client

        # Ping
        mock_client.ping.return_value = True
        code_ping = main(["--control-socket", sock_path, "ping"])
        assert code_ping == 0
        mock_client.ping.assert_called_once()

        # Status
        mock_client.get_status.return_value = {"status": "ok", "workers": 4}
        code_status = main(["--control-socket", sock_path, "status"])
        assert code_status == 0
        mock_client.get_status.assert_called_once()

        # Scale
        mock_client.scale_workers.return_value = {"status": "ok", "target_workers": 6}
        code_scale = main(["--control-socket", sock_path, "scale", "--workers", "6"])
        assert code_scale == 0
        mock_client.scale_workers.assert_called_once_with(6)

        # Reload
        mock_client.reload.return_value = {"status": "ok"}
        code_reload = main(["--control-socket", sock_path, "reload"])
        assert code_reload == 0
        mock_client.reload.assert_called_once()

        # Stop
        mock_client.stop.return_value = {"status": "ok"}
        code_stop = main(["--control-socket", sock_path, "stop"])
        assert code_stop == 0
        mock_client.stop.assert_called_once()


def test_cli_start_mocked() -> None:
    with patch("supervisor.cli.Arbiter") as mock_arbiter_cls:
        mock_arbiter = MagicMock()
        mock_arbiter_cls.return_value = mock_arbiter

        code = main(
            [
                "start",
                "--workers",
                "2",
                "--worker-class",
                "sync",
                "--bind",
                "127.0.0.1:8001",
            ]
        )
        assert code == 0
        mock_arbiter.start.assert_called_once()
        config = mock_arbiter_cls.call_args[0][0]
        assert config.workers == 2
        assert config.worker_class == "sync"
        assert config.bind_host == "127.0.0.1"
        assert config.bind_port == 8001


def test_cli_start_with_config_file(tmp_path) -> None:
    cfg_file = tmp_path / "supervisor.json"
    cfg_file.write_text(
        '{"bind_host": "127.0.0.1", "bind_port": 9005, "workers": 7, "worker_class": "gthread", "threads": 3}',
        encoding="utf-8",
    )

    with patch("supervisor.cli.Arbiter") as mock_arbiter_cls:
        mock_arbiter = MagicMock()
        mock_arbiter_cls.return_value = mock_arbiter

        code = main(["--config", str(cfg_file), "start"])
        assert code == 0
        mock_arbiter.start.assert_called_once()
        config = mock_arbiter_cls.call_args[0][0]
        assert config.bind_host == "127.0.0.1"
        assert config.bind_port == 9005
        assert config.workers == 7
        assert config.worker_class == "gthread"
        assert config.threads == 3


def test_cli_start_with_config_override(tmp_path) -> None:
    cfg_file = tmp_path / "supervisor.json"
    cfg_file.write_text(
        '{"bind_host": "127.0.0.1", "bind_port": 9005, "workers": 7, "worker_class": "sync"}',
        encoding="utf-8",
    )

    with patch("supervisor.cli.Arbiter") as mock_arbiter_cls:
        mock_arbiter = MagicMock()
        mock_arbiter_cls.return_value = mock_arbiter

        # Override workers and bind from CLI
        code = main(
            [
                "--config",
                str(cfg_file),
                "start",
                "--workers",
                "10",
                "--bind",
                "0.0.0.0:9999",
            ]
        )
        assert code == 0
        config = mock_arbiter_cls.call_args[0][0]
        assert config.workers == 10
        assert config.bind_host == "0.0.0.0"
        assert config.bind_port == 9999
        assert config.worker_class == "sync"
