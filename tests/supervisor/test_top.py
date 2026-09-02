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


def test_top_rps_calculation() -> None:
    viewer = SupervisorTopViewer(MagicMock(), no_color=True)
    pid = 99901
    now = 1000.0

    # First sample -> RPS is 0.0
    rps1 = viewer._compute_worker_rps(pid, 10, now)
    assert rps1 == 0.0

    # Second sample 2.0s later with +10 requests -> 5.0/s
    rps2 = viewer._compute_worker_rps(pid, 20, now + 2.0)
    assert rps2 == 5.0

    # Third sample 1.0s later with +3 requests -> 3.0/s
    rps3 = viewer._compute_worker_rps(pid, 23, now + 3.0)
    assert rps3 == 3.0


def test_top_render_column_alignment() -> None:
    """Verifies that all columns in supervisor top output align perfectly across different worker types."""
    import re

    mock_client = MagicMock()
    data = {
        "status": "ok",
        "arbiter_pid": 492930,
        "uptime": 14438.0,
        "pools": {"web": "4/2", "search": "1/1", "database": "3/3"},
        "workers": {
            "493004": {
                "pid": 493004,
                "type": "search",
                "status": "ALIVE",
                "is_healthy": True,
                "requests_handled": 0,
                "idle_seconds": 0.0,
            },
            "493005": {
                "pid": 493005,
                "type": "database",
                "status": "ALIVE",
                "is_healthy": True,
                "requests_handled": 6,
                "idle_seconds": 0.0,
            },
            "526846": {
                "pid": 526846,
                "type": "web",
                "status": "ALIVE",
                "is_healthy": True,
                "requests_handled": 13,
                "idle_seconds": 0.0,
            },
        },
    }

    # Test both no_color=True and no_color=False
    for no_color in (True, False):
        viewer = SupervisorTopViewer(mock_client, no_color=no_color)
        dashboard = viewer.render_dashboard(data)

        # Strip ANSI codes for character position verification
        plain = re.sub(r"\x1b\[[0-9;]*m", "", dashboard)
        lines = [ln for ln in plain.splitlines() if ln.strip()]

        header_line = next(ln for ln in lines if "PID" in ln and "TYPE" in ln)
        worker_lines = [
            ln for ln in lines if any(str(p) in ln for p in (493004, 493005, 526846))
        ]

        assert len(worker_lines) == 3

        # Check column starting indices
        pid_idx = header_line.index("PID")
        type_idx = header_line.index("TYPE")
        status_idx = header_line.index("STATUS")
        health_idx = header_line.index("HEALTH")
        req_idx = header_line.index("REQ")
        rps_idx = header_line.index("RPS")
        idle_idx = header_line.index("IDLE")

        for w_line in worker_lines:
            assert w_line[pid_idx : pid_idx + 6].strip().isdigit()
            # Type must start at type_idx
            assert w_line[type_idx : type_idx + 8].strip() in (
                "search",
                "database",
                "web",
            )
            # Status must start at status_idx
            assert w_line[status_idx : status_idx + 5].strip() == "ALIVE"
            # Health must start at health_idx
            assert w_line[health_idx : health_idx + 7].strip() == "HEALTHY"
            # REQ must start at req_idx
            assert w_line[req_idx : req_idx + 3].strip().isdigit()
            # RPS must start at rps_idx
            assert "/s" in w_line[rps_idx : rps_idx + 7]
            # IDLE must start at idle_idx
            assert "s" in w_line[idle_idx : idle_idx + 6]
