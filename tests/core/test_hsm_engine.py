#!/usr/bin/env python3
"""
Unit and integration tests for Hierarchical State Machine (HSM / Statecharts) core engine.
"""

from __future__ import annotations

from typing import List

import pytest

from core.hsm import (
    EventContext,
    HierarchicalStateMachine,
    StateNode,
    TransitionRule,
    find_lcca,
    find_node_by_path,
    resolve_entry_path,
    resolve_exit_path,
    resolve_initial_leaf,
    validate_tree,
)


def test_event_context_immutability() -> None:
    ctx = EventContext(event_name="START_JOB", payload={"job_id": "job-101"})
    assert ctx.event_name == "START_JOB"
    assert ctx.payload["job_id"] == "job-101"
    assert ctx.timestamp > 0

    with pytest.raises(AttributeError):
        ctx.event_name = "MUTATE"  # type: ignore[misc]


def test_state_node_attributes_and_path() -> None:
    root = StateNode("ROOT")
    operational = root.add_child(StateNode("OPERATIONAL", initial_child="ACTIVE"))
    active = operational.add_child(StateNode("ACTIVE", initial_child="IDLE"))
    idle = active.add_child(StateNode("IDLE"))

    assert root.is_root() is True
    assert operational.is_root() is False
    assert idle.is_leaf() is True
    assert active.is_leaf() is False

    assert idle.depth == 3
    assert active.depth == 2
    assert operational.depth == 1
    assert root.depth == 0

    assert idle.get_path() == "OPERATIONAL.ACTIVE.IDLE"
    assert active.get_path() == "OPERATIONAL.ACTIVE"
    assert operational.get_path() == "OPERATIONAL"

    ancestor_names = [n.name for n in idle.get_ancestors()]
    assert ancestor_names == ["IDLE", "ACTIVE", "OPERATIONAL", "ROOT"]


def test_lcca_and_path_resolution() -> None:
    root = StateNode("ROOT")
    op = root.add_child(StateNode("OPERATIONAL"))
    active = op.add_child(StateNode("ACTIVE"))
    idle = active.add_child(StateNode("IDLE"))
    busy = active.add_child(StateNode("BUSY"))

    term = root.add_child(StateNode("TERMINATED"))
    stopped = term.add_child(StateNode("STOPPED"))

    # Sibling leaves
    assert find_lcca(idle, busy) == active
    exit_path = resolve_exit_path(idle, active)
    assert [n.name for n in exit_path] == ["IDLE"]
    entry_path = resolve_entry_path(busy, active)
    assert [n.name for n in entry_path] == ["BUSY"]

    # Self transition
    assert find_lcca(idle, idle) == active

    # Cross composite hierarchy
    assert find_lcca(idle, stopped) == root
    exit_cross = resolve_exit_path(idle, root)
    assert [n.name for n in exit_cross] == ["IDLE", "ACTIVE", "OPERATIONAL"]
    entry_cross = resolve_entry_path(stopped, root)
    assert [n.name for n in entry_cross] == ["TERMINATED", "STOPPED"]


def test_initial_leaf_resolution() -> None:
    root = StateNode("ROOT", initial_child="OPERATIONAL")
    op = root.add_child(StateNode("OPERATIONAL", initial_child="ACTIVE"))
    active = op.add_child(StateNode("ACTIVE", initial_child="IDLE"))
    idle = active.add_child(StateNode("IDLE"))

    leaf, intermediate = resolve_initial_leaf(root)
    assert leaf == idle
    assert [n.name for n in intermediate] == ["OPERATIONAL", "ACTIVE", "IDLE"]


def test_find_node_by_path() -> None:
    root = StateNode("ROOT")
    op = root.add_child(StateNode("OPERATIONAL"))
    active = op.add_child(StateNode("ACTIVE"))
    idle = active.add_child(StateNode("IDLE"))

    assert find_node_by_path(root, "OPERATIONAL.ACTIVE.IDLE") == idle
    assert find_node_by_path(root, "ACTIVE.IDLE") is None
    assert find_node_by_path(root, "") is None


def test_tree_validation_errors() -> None:
    root = StateNode("ROOT")
    child = root.add_child(StateNode("CHILD"))

    # Valid tree
    validate_tree(root, max_depth=2)

    # Exceed max depth
    with pytest.raises(ValueError, match="exceeds max depth"):
        validate_tree(root, max_depth=0)

    # Cyclic reference
    child.children["LOOP"] = root
    root.parent = child
    with pytest.raises(ValueError, match="Cyclic reference"):
        validate_tree(root, max_depth=5)


def test_hsm_lifecycle_entry_exit_sequence() -> None:
    calls: List[str] = []

    root = StateNode("ROOT", initial_child="OPERATIONAL")

    op = root.add_child(
        StateNode(
            "OPERATIONAL",
            initial_child="ACTIVE",
            on_entry=lambda ctx: calls.append("ENTRY_OP"),
            on_exit=lambda ctx: calls.append("EXIT_OP"),
        )
    )

    active = op.add_child(
        StateNode(
            "ACTIVE",
            initial_child="IDLE",
            on_entry=lambda ctx: calls.append("ENTRY_ACTIVE"),
            on_exit=lambda ctx: calls.append("EXIT_ACTIVE"),
        )
    )

    idle = active.add_child(
        StateNode(
            "IDLE",
            on_entry=lambda ctx: calls.append("ENTRY_IDLE"),
            on_exit=lambda ctx: calls.append("EXIT_IDLE"),
        )
    )

    busy = active.add_child(
        StateNode(
            "BUSY",
            on_entry=lambda ctx: calls.append("ENTRY_BUSY"),
            on_exit=lambda ctx: calls.append("EXIT_BUSY"),
        )
    )

    term = root.add_child(
        StateNode(
            "TERMINATED",
            initial_child="STOPPED",
            on_entry=lambda ctx: calls.append("ENTRY_TERM"),
            on_exit=lambda ctx: calls.append("EXIT_TERM"),
        )
    )
    stopped = term.add_child(
        StateNode(
            "STOPPED",
            on_entry=lambda ctx: calls.append("ENTRY_STOPPED"),
            on_exit=lambda ctx: calls.append("EXIT_STOPPED"),
        )
    )

    # Transitions
    idle.add_transition(
        TransitionRule(
            source_name="IDLE",
            event_name="JOB_RECEIVED",
            target_name="BUSY",
            action=lambda ctx: calls.append(f"ACTION_JOB_{ctx.payload.get('id')}"),
        )
    )

    busy.add_transition(
        TransitionRule(
            source_name="BUSY",
            event_name="JOB_DONE",
            target_name="IDLE",
            action=lambda ctx: calls.append("ACTION_DONE"),
        )
    )

    # Event bubbling: registered on parent OPERATIONAL, triggers from any child!
    op.add_transition(
        TransitionRule(
            source_name="OPERATIONAL",
            event_name="SIGTERM",
            target_name="TERMINATED.STOPPED",
            action=lambda ctx: calls.append("ACTION_EMERGENCY_EXIT"),
        )
    )

    # Boot HSM
    hsm = HierarchicalStateMachine(root=root)
    assert calls == ["ENTRY_OP", "ENTRY_ACTIVE", "ENTRY_IDLE"]
    assert hsm.current_state == idle
    assert hsm.get_state_path() == "OPERATIONAL.ACTIVE.IDLE"
    assert hsm.is_in_state("IDLE") is True
    assert hsm.is_in_state("ACTIVE") is True
    assert hsm.is_in_state("OPERATIONAL") is True
    assert hsm.is_in_state("STOPPED") is False

    # 1. Sibling transition: IDLE -> BUSY
    calls.clear()
    ok = hsm.send_event("JOB_RECEIVED", payload={"id": "42"})
    assert ok is True
    assert calls == ["EXIT_IDLE", "ACTION_JOB_42", "ENTRY_BUSY"]
    assert hsm.current_state == busy
    assert hsm.get_state_path() == "OPERATIONAL.ACTIVE.BUSY"

    # 2. Return transition: BUSY -> IDLE
    calls.clear()
    ok = hsm.send_event("JOB_DONE")
    assert ok is True
    assert calls == ["EXIT_BUSY", "ACTION_DONE", "ENTRY_IDLE"]
    assert hsm.current_state == idle

    # 3. Bubbling transition: SIGTERM handled by OPERATIONAL parent
    calls.clear()
    ok = hsm.send_event("SIGTERM")
    assert ok is True
    assert calls == [
        "EXIT_IDLE",
        "EXIT_ACTIVE",
        "EXIT_OP",
        "ACTION_EMERGENCY_EXIT",
        "ENTRY_TERM",
        "ENTRY_STOPPED",
    ]
    assert hsm.current_state == stopped
    assert hsm.get_state_path() == "TERMINATED.STOPPED"


def test_hsm_guard_conditions() -> None:
    root = StateNode("ROOT", initial_child="STATE_A")
    a = root.add_child(StateNode("STATE_A"))
    root.add_child(StateNode("STATE_B"))
    c = root.add_child(StateNode("STATE_C"))

    # Two rules for NEXT_STEP: one guarded by count > 10
    a.add_transition(
        TransitionRule(
            source_name="STATE_A",
            event_name="NEXT_STEP",
            target_name="STATE_B",
            guard=lambda ctx: ctx.payload.get("count", 0) > 10,
        )
    )
    a.add_transition(
        TransitionRule(
            source_name="STATE_A",
            event_name="NEXT_STEP",
            target_name="STATE_C",
            guard=lambda ctx: ctx.payload.get("count", 0) <= 10,
        )
    )

    hsm = HierarchicalStateMachine(root=root)
    assert hsm.current_state == a

    # Transition with count=5 goes to STATE_C
    ok = hsm.send_event("NEXT_STEP", payload={"count": 5})
    assert ok is True
    assert hsm.current_state == c


def test_hsm_fail_secure_trap() -> None:
    root = StateNode("ROOT", initial_child="RUNNING")
    running = root.add_child(StateNode("RUNNING"))
    term = root.add_child(StateNode("TERMINATED"))
    failed = term.add_child(StateNode("FAILED"))

    def _exploding_action(_ctx: EventContext) -> None:
        raise RuntimeError("Simulated internal fault")

    running.add_transition(
        TransitionRule(
            source_name="RUNNING",
            event_name="TRIGGER_CRASH",
            target_name="RUNNING",
            action=_exploding_action,
        )
    )

    hsm = HierarchicalStateMachine(
        root=root,
        fail_secure_target="TERMINATED.FAILED",
    )
    assert hsm.current_state == running

    with pytest.raises(RuntimeError, match="Simulated internal fault"):
        hsm.send_event("TRIGGER_CRASH")

    # Fail secure has trapped and forced transition to TERMINATED.FAILED
    assert hsm.current_state == failed
    assert hsm.get_state_path() == "TERMINATED.FAILED"


def test_hsm_observers() -> None:
    history: List[str] = []

    root = StateNode("ROOT", initial_child="READY")
    ready = root.add_child(StateNode("READY"))
    root.add_child(StateNode("ACTIVE"))

    ready.add_transition(
        TransitionRule(
            source_name="READY",
            event_name="ACTIVATE",
            target_name="ACTIVE",
        )
    )

    hsm = HierarchicalStateMachine(root=root)
    hsm.add_observer(
        lambda src, dst, ctx: history.append(f"{src.name}->{dst.name}:{ctx.event_name}")
    )

    hsm.send_event("ACTIVATE")
    assert history == ["READY->ACTIVE:ACTIVATE"]
