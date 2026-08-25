"""Unit tests for Supervisor Top Monitoring Viewer."""

import os
from unittest.mock import MagicMock, patch

from supervisor.cli import main
from supervisor.top import SupervisorTopViewer, run_top


def test_top_format_uptime() -> None:
    viewer = SupervisorTopViewer(MagicMock(), no_color=True)
    assert "00m 45s" in viewer.format_uptime(45)
    assert "01h 05m 10s" in viewer.format_uptime(3910)
    assert "2d 03h 04m 05s" in viewer.format_uptime(183845)


def test_top_render_dashboard() -> None:
    mock_client = MagicMock()
    viewer = SupervisorTopViewer(mock_client, no_color=True)

    data = {
        "status": "ok",
        "arbiter_pid": 12345,
        "uptime": 120.5,
        "pools": {
            "web_pool": {"active": 2, "target": 2},
            "indexer": {"active": 1, "target": 1},
        },
        "workers": {
            "12346": {
                "pid": 12346,
                "type": "indexer",
                "status": "ALIVE",
                "is_healthy": True,
                "requests_handled": 10,
                "idle_seconds": 0.5,
            },
            "12347": {
                "pid": 12347,
                "type": "sync",
                "status": "ALIVE",
                "is_healthy": True,
                "requests_handled": 42,
                "idle_seconds": 1.2,
            },
        },
    }

    dashboard = viewer.render_dashboard(data)
    assert "Supervisor Process Top Monitor" in dashboard
    assert "Arbiter PID: 12345" in dashboard
    assert "web_pool: 2/2" in dashboard
    assert "indexer: 1/1" in dashboard
    assert "12346" in dashboard
    assert "12347" in dashboard
    assert "sync" in dashboard
    assert "HEALTHY" in dashboard
    assert "42" in dashboard


def test_top_render_dashboard_idle_worker_healthy() -> None:
    """Verifies that workers idle for long durations still display as HEALTHY."""
    mock_client = MagicMock()
    viewer = SupervisorTopViewer(mock_client, no_color=True)

    data = {
        "status": "ok",
        "arbiter_pid": 12345,
        "uptime": 3600.0,
        "target_workers": 1,
        "active_web_workers": 1,
        "bind": "0.0.0.0:8000",
        "worker_class": "sync",
        "workers": {
            "12346": {
                "pid": 12346,
                "type": "sync",
                "status": "ALIVE",
                "is_healthy": True,
                "requests_handled": 0,
                "idle_seconds": 600.0,
            }
        },
    }

    dashboard = viewer.render_dashboard(data)
    assert "HEALTHY" in dashboard
    assert "600.0s" in dashboard


def test_top_get_process_memory_mb() -> None:
    rss, pss = SupervisorTopViewer.get_process_memory_mb(os.getpid())
    assert isinstance(rss, float)
    assert isinstance(pss, float)
    assert rss >= 0.0
    assert pss >= 0.0

    # Test nonexistent PID
    rss_none, pss_none = SupervisorTopViewer.get_process_memory_mb(9999999)
    assert rss_none == 0.0
    assert pss_none == 0.0


def test_top_render_dashboard_empty_workers() -> None:
    mock_client = MagicMock()
    viewer = SupervisorTopViewer(mock_client, no_color=True)

    data = {
        "status": "ok",
        "arbiter_pid": 12345,
        "uptime": 10.0,
        "pools": {},
        "workers": {},
    }

    dashboard = viewer.render_dashboard(data)
    assert "No active workers registered." in dashboard


def test_top_run_once_success() -> None:
    mock_client = MagicMock()
    mock_client.get_status.return_value = {
        "status": "ok",
        "arbiter_pid": 1000,
        "uptime": 10.0,
        "workers": {},
    }

    code = run_top(mock_client, interval=1.0, once=True, no_color=True)
    assert code == 0


def test_top_run_error_status() -> None:
    mock_client = MagicMock()
    mock_client.get_status.return_value = {
        "status": "error",
        "error": "Socket disconnected",
    }

    code = run_top(mock_client, interval=1.0, once=True, no_color=True)
    assert code == 1


def test_cli_top_command(tmp_path) -> None:
    sock_path = str(tmp_path / "control.sock")
    with patch("supervisor.cli.ControlClient") as mock_client_cls:
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.get_status.return_value = {
            "status": "ok",
            "arbiter_pid": 9999,
            "uptime": 50.0,
            "workers": {},
        }

        code = main(["--control-socket", sock_path, "top", "--once", "--no-color"])
        assert code == 0
        mock_client.get_status.assert_called_once()
