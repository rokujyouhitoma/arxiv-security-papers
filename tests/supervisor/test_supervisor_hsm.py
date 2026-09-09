#!/usr/bin/env python3
"""
Integration tests for Supervisor Hierarchical State Machine (HSM / Statecharts) governance.
"""

from __future__ import annotations

from typing import Any

from core.hsm import HierarchicalStateMachine
from supervisor.arbiter import Arbiter, ManagedPool
from supervisor.config import SupervisorConfig
from supervisor.contracts import (
    ServiceRole,
    ServiceState,
    WorkerSpec,
    build_supervisor_state_tree,
)


def test_service_state_hierarchical_paths() -> None:
    # Operational tier
    assert ServiceState.READY.super_state == "OPERATIONAL"
    assert ServiceState.READY.hierarchical_path == "OPERATIONAL.READY"
    assert ServiceState.ACTIVE.super_state == "OPERATIONAL"
    assert ServiceState.ACTIVE.hierarchical_path == "OPERATIONAL.ACTIVE.IDLE"
    assert ServiceState.OPERATIONAL.super_state == "OPERATIONAL"

    # Transitioning tier
    assert ServiceState.DRAINING.super_state == "TRANSITIONING"
    assert ServiceState.DRAINING.hierarchical_path == "TRANSITIONING.DRAINING"
    assert ServiceState.TRANSITIONING.super_state == "TRANSITIONING"

    # Terminated tier
    assert ServiceState.STOPPED.super_state == "TERMINATED"
    assert ServiceState.STOPPED.hierarchical_path == "TERMINATED.STOPPED"
    assert ServiceState.FAILED.super_state == "TERMINATED"
    assert ServiceState.FAILED.hierarchical_path == "TERMINATED.FAILED"
    assert ServiceState.COMPLETED.super_state == "TERMINATED"
    assert ServiceState.COMPLETED.hierarchical_path == "TERMINATED.COMPLETED"


def test_build_supervisor_state_tree_lifecycle() -> None:
    tree = build_supervisor_state_tree("test_lifecycle")
    hsm = HierarchicalStateMachine(root=tree)

    # Initial state: OPERATIONAL.READY
    assert hsm.get_state_path() == "OPERATIONAL.READY"
    assert hsm.is_in_state("OPERATIONAL") is True
    assert hsm.is_in_state("READY") is True

    # START -> ACTIVE.IDLE
    assert hsm.send_event("START") is True
    assert hsm.get_state_path() == "OPERATIONAL.ACTIVE.IDLE"
    assert hsm.is_in_state("ACTIVE") is True

    # DISPATCH -> ACTIVE.PROCESSING
    assert hsm.send_event("DISPATCH") is True
    assert hsm.get_state_path() == "OPERATIONAL.ACTIVE.PROCESSING"

    # FINISH -> ACTIVE.IDLE
    assert hsm.send_event("FINISH") is True
    assert hsm.get_state_path() == "OPERATIONAL.ACTIVE.IDLE"

    # PAUSE / RESUME cycle
    assert hsm.send_event("DISPATCH") is True
    assert hsm.send_event("PAUSE") is True
    assert hsm.get_state_path() == "OPERATIONAL.ACTIVE.PAUSED"
    assert hsm.send_event("RESUME") is True
    assert hsm.get_state_path() == "OPERATIONAL.ACTIVE.IDLE"

    # SIGQUIT -> TRANSITIONING.DRAINING.CLOSING_LISTENERS
    assert hsm.send_event("SIGQUIT") is True
    assert hsm.get_state_path() == "TRANSITIONING.DRAINING.CLOSING_LISTENERS"

    # Drain steps: CLOSING -> WAITING -> FLUSHING -> STOPPED
    assert hsm.send_event("LISTENERS_CLOSED") is True
    assert hsm.get_state_path() == "TRANSITIONING.DRAINING.WAITING_INFLIGHT"
    assert hsm.send_event("INFLIGHT_DRAINED") is True
    assert hsm.get_state_path() == "TRANSITIONING.DRAINING.FLUSHING_BUFFERS"
    assert hsm.send_event("BUFFERS_FLUSHED") is True
    assert hsm.get_state_path() == "TERMINATED.STOPPED"
    assert hsm.is_in_state("TERMINATED") is True


def test_managed_pool_hsm_binding() -> None:
    spec = WorkerSpec(
        name="worker_pool_alpha",
        target_count=3,
        role=ServiceRole.STATELESS_POOL,
    )
    pool = ManagedPool(spec)

    assert pool.state == ServiceState.READY
    assert pool.state_path == "OPERATIONAL.READY"
    assert pool.hsm.is_in_state("OPERATIONAL") is True

    # State update to ACTIVE
    pool.state = ServiceState.ACTIVE
    assert pool.state == ServiceState.ACTIVE
    assert pool.state_path == "OPERATIONAL.ACTIVE.IDLE"

    # State update to DRAINING
    pool.state = ServiceState.DRAINING
    assert pool.state == ServiceState.DRAINING
    assert pool.state_path == "TRANSITIONING.DRAINING.CLOSING_LISTENERS"

    # State update to COMPLETED
    pool.state = ServiceState.COMPLETED
    assert pool.state == ServiceState.COMPLETED
    assert pool.state_path == "TERMINATED.COMPLETED"


def test_arbiter_hsm_state_transitions(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path))
    arbiter = Arbiter(cfg)

    assert arbiter.state == ServiceState.READY
    assert arbiter.state_path == "OPERATIONAL.READY"
    assert arbiter.hsm.is_in_state("OPERATIONAL") is True

    arbiter.state = ServiceState.ACTIVE
    assert arbiter.state == ServiceState.ACTIVE
    assert arbiter.state_path == "OPERATIONAL.ACTIVE.IDLE"

    arbiter.state = ServiceState.STOPPED
    assert arbiter.state == ServiceState.STOPPED
    assert arbiter.hsm.is_in_state("TERMINATED") is True
    assert arbiter.state_path == "TERMINATED.STOPPED"


def test_arbiter_status_command_hsm_metadata(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path), workers=2)
    arbiter = Arbiter(cfg)
    status = arbiter.handle_control_command({"cmd": "status"})

    assert status["status"] == "ok"
    assert status["arbiter_state"] == "READY"
    assert status["arbiter_state_path"] == "OPERATIONAL.READY"
    assert "default" in status["pools"]
    pool_meta = status["pools"]["default"]
    assert pool_meta["state"] == "READY"
    assert pool_meta["state_path"] == "OPERATIONAL.READY"
    assert pool_meta["super_state"] == "OPERATIONAL"


def test_arbiter_shutdown_hsm_states(tmp_path: Any) -> None:
    cfg = SupervisorConfig(workspace_dir=str(tmp_path), workers=1)
    arbiter = Arbiter(cfg)
    arbiter.state = ServiceState.ACTIVE
    arbiter.shutdown()

    assert arbiter.state == ServiceState.STOPPED
    assert arbiter.state_path == "TERMINATED.STOPPED"
    for pool in arbiter.pools.values():
        assert pool.state == ServiceState.STOPPED
        assert pool.state_path == "TERMINATED.STOPPED"
