"""Unit tests for HeartbeatWatchdog tracking, liveness, and hung detection."""

import time

from supervisor.heartbeat import HeartbeatWatchdog


def test_heartbeat_register_and_pulse() -> None:
    watchdog = HeartbeatWatchdog(timeout=2.0)
    pid = 12345
    watchdog.register_worker(pid, "sync", {"version": "1.0"})

    assert watchdog.is_healthy(pid) is True
    st = watchdog.get_worker_status(pid)
    assert st is not None
    assert st["type"] == "sync"
    assert st["version"] == "1.0"
    assert st["is_healthy"] is True

    # Record pulse
    watchdog.record_heartbeat(pid, {"requests_handled": 10})
    st2 = watchdog.get_worker_status(pid)
    assert st2 is not None
    assert st2["requests_handled"] == 10


def test_heartbeat_hung_detection() -> None:
    watchdog = HeartbeatWatchdog(timeout=0.1)
    pid1 = 11111
    pid2 = 22222
    watchdog.register_worker(pid1, "sync")
    watchdog.register_worker(pid2, "gthread")

    # Mark pid2 as actively handling a request so it is eligible for hung detection.
    # (IDLE workers are intentionally excluded from hung detection — see Issue 071.)
    watchdog._worker_meta[pid2]["is_handling_request"] = True

    time.sleep(0.15)
    # Pulse pid1 only
    watchdog.record_heartbeat(pid1)

    hung = watchdog.get_hung_workers(timeout=0.1)
    assert pid2 in hung
    assert pid1 not in hung

    # Remove pid2
    watchdog.remove_worker(pid2)
    assert watchdog.get_worker_status(pid2) is None


def test_heartbeat_all_statuses() -> None:
    watchdog = HeartbeatWatchdog(timeout=5.0)
    watchdog.register_worker(101, "sync")
    watchdog.register_worker(102, "db")

    all_st = watchdog.get_all_statuses()
    assert 101 in all_st
    assert 102 in all_st
    assert all_st[102]["type"] == "db"
    assert all_st[101]["is_healthy"] is True
    assert all_st[102]["is_healthy"] is True


def test_idle_worker_stays_healthy_over_timeout() -> None:
    """Verifies that idle workers stay healthy indefinitely and are never classified as hung."""
    watchdog = HeartbeatWatchdog(timeout=0.05)
    pid = 99999
    watchdog.register_worker(pid, "sync")

    # Simulate waiting longer than the timeout without requests
    time.sleep(0.1)

    # Status must still be healthy for idle workers
    st = watchdog.get_worker_status(pid)
    assert st is not None
    assert st["is_healthy"] is True
    assert watchdog.is_healthy(pid) is True
    assert watchdog.get_hung_workers(timeout=0.05) == []

    # When request starts, and times out, health drops and hung detected
    watchdog.record_heartbeat(pid, {"is_handling_request": True})
    time.sleep(0.1)

    assert watchdog.is_healthy(pid, timeout=0.05) is False
    st_hung = watchdog.get_worker_status(pid)
    assert st_hung is not None
    assert st_hung["is_healthy"] is False
    assert watchdog.get_hung_workers(timeout=0.05) == [pid]

    # When request finishes, health restores
    watchdog.record_heartbeat(pid, {"is_handling_request": False})
    assert watchdog.is_healthy(pid) is True
    assert watchdog.get_hung_workers(timeout=0.05) == []
