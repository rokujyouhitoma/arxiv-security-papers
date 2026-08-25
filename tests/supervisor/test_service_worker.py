#!/usr/bin/env python3
"""
Unit tests for ManagedServiceWorker and LifecycleHook in Process Supervisor.
"""

import threading
import time
from typing import Any, Dict, List, Optional
from unittest.mock import MagicMock

from supervisor.config import SupervisorConfig
from supervisor.contracts import LifecycleHook
from supervisor.workers.service_worker import ManagedServiceWorker


class MockServiceHook(LifecycleHook):
    def __init__(self) -> None:
        self.setup_called = False
        self.flush_called = 0
        self.teardown_called = False
        self.healthy = True

    def setup(self) -> bool:
        self.setup_called = True
        return True

    def health_check(self) -> bool:
        return self.healthy

    def on_flush(self) -> None:
        self.flush_called += 1

    def teardown(self) -> None:
        self.teardown_called = True


def test_managed_service_worker_lifecycle(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    hook = MockServiceHook()
    pulses: List[Optional[Dict[str, Any]]] = []

    worker = ManagedServiceWorker(
        worker_id="service_test_01",
        config=cfg,
        service_name="custom_indexer",
        hook=hook,
        sync_interval=0.1,
        pulse_callback=lambda pid, meta: pulses.append(meta),
    )

    t = threading.Thread(target=worker.run, daemon=True)
    t.start()
    time.sleep(0.3)

    assert worker.alive is True
    assert hook.setup_called is True
    assert hook.flush_called > 0

    worker.alive = False
    t.join(timeout=2.0)

    assert hook.teardown_called is True
    assert len(pulses) > 0
    assert pulses[0] is not None
    assert pulses[0]["service"] == "custom_indexer"
    assert pulses[0]["is_healthy"] is True


def test_managed_service_worker_setup_failure(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    hook = MagicMock(spec=LifecycleHook)
    hook.setup.return_value = False

    pulses: List[Optional[Dict[str, Any]]] = []
    worker = ManagedServiceWorker(
        worker_id="service_fail_01",
        config=cfg,
        service_name="failing_service",
        hook=hook,
        pulse_callback=lambda pid, meta: pulses.append(meta),
    )

    worker.run()
    assert len(pulses) == 1
    assert pulses[0] is not None
    assert pulses[0]["state"] == "FAILED"
