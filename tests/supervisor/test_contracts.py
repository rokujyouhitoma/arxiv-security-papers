#!/usr/bin/env python3
"""
Tests for Supervisor contracts, interfaces, and declarative WorkerSpec models.
"""

from __future__ import annotations

from supervisor.contracts import (
    DefaultLifecycleHook,
    LifecycleHook,
    ServiceRole,
    ServiceState,
    WorkerSpec,
)


class CustomTestHook(LifecycleHook):
    def __init__(self) -> None:
        self.setup_called = False
        self.health_called = False
        self.teardown_called = False

    def setup(self) -> bool:
        self.setup_called = True
        return True

    def health_check(self) -> bool:
        self.health_called = True
        return True

    def teardown(self) -> None:
        self.teardown_called = True


def test_service_enums() -> None:
    assert ServiceRole.STATELESS_POOL.value == "STATELESS_POOL"
    assert ServiceRole.STATEFUL_SERVICE.value == "STATEFUL_SERVICE"
    assert ServiceRole.ONESHOT_TASK.value == "ONESHOT_TASK"

    assert ServiceState.READY.value == "READY"
    assert ServiceState.ACTIVE.value == "ACTIVE"


def test_default_lifecycle_hook() -> None:
    hook = DefaultLifecycleHook()
    assert hook.setup() is True
    assert hook.health_check() is True
    hook.on_flush()
    hook.teardown()


def test_custom_lifecycle_hook() -> None:
    hook = CustomTestHook()
    assert hook.setup() is True
    assert hook.setup_called is True
    assert hook.health_check() is True
    assert hook.health_called is True
    hook.teardown()
    assert hook.teardown_called is True


def test_worker_spec_dataclass() -> None:
    spec = WorkerSpec(
        name="custom_worker",
        target_count=3,
        worker_class="sync",
        role=ServiceRole.STATELESS_POOL,
        sync_interval=5.0,
        metadata={"key": "val"},
    )
    assert spec.name == "custom_worker"
    assert spec.target_count == 3
    assert spec.worker_class == "sync"
    assert spec.role == ServiceRole.STATELESS_POOL
    assert spec.sync_interval == 5.0

    d = spec.to_dict()
    assert d["name"] == "custom_worker"
    assert d["target_count"] == 3
    assert d["worker_class"] == "sync"
    assert d["role"] == "STATELESS_POOL"
    assert d["metadata"] == {"key": "val"}
