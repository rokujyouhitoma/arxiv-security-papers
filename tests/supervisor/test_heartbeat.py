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


def test_heartbeat_sync_from_disk(tmp_path) -> None:
    """Verifies that HeartbeatWatchdog accurately loads worker state from disk files."""
    import json

    state_dir = str(tmp_path / "supervisor")
    import os

    os.makedirs(state_dir, exist_ok=True)

    watchdog = HeartbeatWatchdog(timeout=5.0, base_dir=state_dir)
    pid = 77777
    watchdog.register_worker(pid, "web")

    # Initially requests_handled is 0
    st_init = watchdog.get_worker_status(pid)
    assert st_init is not None
    assert st_init["requests_handled"] == 0

    # Worker writes heartbeat file
    heartbeat_file = os.path.join(state_dir, f"heartbeat_{pid}.json")
    with open(heartbeat_file, "w", encoding="utf-8") as f:
        json.dump(
            {
                "pid": pid,
                "requests_handled": 42,
                "is_handling_request": False,
                "uptime": 12.3,
            },
            f,
        )

    # get_worker_status automatically syncs from disk
    st_synced = watchdog.get_worker_status(pid)
    assert st_synced is not None
    assert st_synced["requests_handled"] == 42
    assert st_synced["uptime"] == 12.3

    # Cleanup upon worker removal
    watchdog.remove_worker(pid)
    assert not os.path.exists(heartbeat_file)


def test_idle_seconds_tracking_and_reset() -> None:
    """Verifies that idle_seconds increases while idle and resets when requests are processed."""
    watchdog = HeartbeatWatchdog(timeout=5.0)
    pid = 88888
    watchdog.register_worker(pid, "search")

    time.sleep(0.12)
    st1 = watchdog.get_worker_status(pid)
    assert st1 is not None
    assert st1["idle_seconds"] >= 0.1

    # While handling request, idle_seconds drops to 0.0
    watchdog.record_heartbeat(pid, {"is_handling_request": True})
    st2 = watchdog.get_worker_status(pid)
    assert st2 is not None
    assert st2["idle_seconds"] == 0.0

    # When request completes (requests_handled increments), idle_seconds resets
    watchdog.record_heartbeat(
        pid, {"is_handling_request": False, "requests_handled": 1}
    )
    st3 = watchdog.get_worker_status(pid)
    assert st3 is not None
    assert st3["idle_seconds"] < 0.1

    # Over time without requests, idle_seconds grows again
    time.sleep(0.12)
    st4 = watchdog.get_worker_status(pid)
    assert st4 is not None
    assert st4["idle_seconds"] >= 0.1
