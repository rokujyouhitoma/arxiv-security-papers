#!/usr/bin/env python3
"""
Workflow, Saga, and Scheduler state contracts and HSM tree builders.
Pure Python 3.14 standard library. Zero external dependencies.
"""

from __future__ import annotations

from core.hsm import HierarchicalStateMachine, StateNode, TransitionRule

# Event constants
EVENT_START = "EVENT_START"
EVENT_EXECUTE = "EVENT_EXECUTE"
EVENT_COMMIT = "EVENT_COMMIT"
EVENT_COMPLETE = "EVENT_COMPLETE"
EVENT_FAIL = "EVENT_FAIL"
EVENT_FAULT = "EVENT_FAULT"
EVENT_COMPENSATE = "EVENT_COMPENSATE"
EVENT_SKIP = "EVENT_SKIP"
EVENT_ABORT = "EVENT_ABORT"
EVENT_RETRY = "EVENT_RETRY"
EVENT_MAX_RETRIES = "EVENT_MAX_RETRIES"
EVENT_ROLLBACK_DONE = "EVENT_ROLLBACK_DONE"
EVENT_ROLLBACK_FAIL = "EVENT_ROLLBACK_FAIL"

EVENT_STEP_OK = "EVENT_STEP_OK"
EVENT_COMMIT_ALL = "EVENT_COMMIT_ALL"

EVENT_DISPATCH = "EVENT_DISPATCH"
EVENT_IDLE = "EVENT_IDLE"
EVENT_PAUSE = "EVENT_PAUSE"
EVENT_RESUME = "EVENT_RESUME"
EVENT_DRAIN = "EVENT_DRAIN"
EVENT_STOP = "EVENT_STOP"


def _add_task_operational_nodes(root: StateNode) -> None:
    """Builds the OPERATIONAL state hierarchy for Task HSM."""
    op = root.add_child(StateNode("OPERATIONAL", initial_child="PENDING"))
    op.add_child(StateNode("PENDING"))
    running = op.add_child(StateNode("RUNNING", initial_child="PREPARING"))
    running.add_child(StateNode("PREPARING"))
    running.add_child(StateNode("EXECUTING"))
    running.add_child(StateNode("COMMITTING"))


def _add_task_fault_and_term_nodes(root: StateNode) -> None:
    """Builds the FAULTED and TERMINATED state hierarchy for Task HSM."""
    faulted = root.add_child(StateNode("FAULTED", initial_child="RETRYING"))
    faulted.add_child(StateNode("RETRYING"))
    comp = faulted.add_child(StateNode("COMPENSATING", initial_child="ROLLING_BACK"))
    comp.add_child(StateNode("ROLLING_BACK"))
    comp.add_child(StateNode("ROLLBACK_COMPLETED"))
    comp.add_child(StateNode("ROLLBACK_FAILED"))

    term = root.add_child(StateNode("TERMINATED", initial_child="SUCCESS"))
    term.add_child(StateNode("SUCCESS"))
    term.add_child(StateNode("FAILED"))
    term.add_child(StateNode("SKIPPED"))
    term.add_child(StateNode("ABORTED"))


def _register_task_forward_rules(root: StateNode) -> None:
    """Registers forward execution transition rules for Task HSM."""
    root.add_transition(
        TransitionRule("PENDING", EVENT_START, "OPERATIONAL.RUNNING.PREPARING")
    )
    root.add_transition(
        TransitionRule("PREPARING", EVENT_EXECUTE, "OPERATIONAL.RUNNING.EXECUTING")
    )
    root.add_transition(
        TransitionRule("EXECUTING", EVENT_COMMIT, "OPERATIONAL.RUNNING.COMMITTING")
    )
    root.add_transition(
        TransitionRule("COMMITTING", EVENT_COMPLETE, "TERMINATED.SUCCESS")
    )
    root.add_transition(TransitionRule("PENDING", EVENT_SKIP, "TERMINATED.SKIPPED"))


def _register_task_fault_rules(root: StateNode) -> None:
    """Registers fault and recovery transition rules for Task HSM."""
    root.add_transition(TransitionRule("RUNNING", EVENT_FAIL, "TERMINATED.FAILED"))
    root.add_transition(TransitionRule("RUNNING", EVENT_FAULT, "FAULTED.RETRYING"))
    root.add_transition(
        TransitionRule("RUNNING", EVENT_COMPENSATE, "FAULTED.COMPENSATING.ROLLING_BACK")
    )
    root.add_transition(
        TransitionRule("RETRYING", EVENT_RETRY, "OPERATIONAL.RUNNING.PREPARING")
    )
    root.add_transition(
        TransitionRule("RETRYING", EVENT_MAX_RETRIES, "TERMINATED.FAILED")
    )


def _register_task_comp_rules(root: StateNode) -> None:
    """Registers compensation transition rules for Task HSM."""
    root.add_transition(
        TransitionRule(
            "ROLLING_BACK",
            EVENT_ROLLBACK_DONE,
            "FAULTED.COMPENSATING.ROLLBACK_COMPLETED",
        )
    )
    root.add_transition(
        TransitionRule(
            "ROLLING_BACK",
            EVENT_ROLLBACK_FAIL,
            "FAULTED.COMPENSATING.ROLLBACK_FAILED",
        )
    )
    root.add_transition(
        TransitionRule("OPERATIONAL", EVENT_ABORT, "TERMINATED.ABORTED")
    )
    root.add_transition(TransitionRule("FAULTED", EVENT_ABORT, "TERMINATED.ABORTED"))


def build_task_state_tree() -> HierarchicalStateMachine:
    """Constructs the Task lifecycle HSM tree."""
    root = StateNode("ROOT", initial_child="OPERATIONAL")
    _add_task_operational_nodes(root)
    _add_task_fault_and_term_nodes(root)
    _register_task_forward_rules(root)
    _register_task_fault_rules(root)
    _register_task_comp_rules(root)
    return HierarchicalStateMachine(root)


def _add_saga_nodes(root: StateNode) -> None:
    """Builds node tree for Saga HSM."""
    fwd = root.add_child(StateNode("FORWARD", initial_child="STEP_SUCCESS"))
    fwd.add_child(StateNode("EXECUTING_STEP"))
    fwd.add_child(StateNode("STEP_SUCCESS"))

    comp = root.add_child(StateNode("COMPENSATION", initial_child="ROLLING_BACK"))
    comp.add_child(StateNode("ROLLING_BACK"))
    comp.add_child(StateNode("ROLLBACK_COMPLETED"))
    comp.add_child(StateNode("ROLLBACK_FAILED"))

    term = root.add_child(StateNode("TERMINATED", initial_child="COMMITTED"))
    term.add_child(StateNode("COMMITTED"))
    term.add_child(StateNode("ABORTED"))


def _register_saga_rules(root: StateNode) -> None:
    """Registers transition rules for Saga HSM."""
    root.add_transition(
        TransitionRule("STEP_SUCCESS", EVENT_EXECUTE, "FORWARD.EXECUTING_STEP")
    )
    root.add_transition(
        TransitionRule("EXECUTING_STEP", EVENT_STEP_OK, "FORWARD.STEP_SUCCESS")
    )
    root.add_transition(
        TransitionRule("FORWARD", EVENT_COMMIT_ALL, "TERMINATED.COMMITTED")
    )
    root.add_transition(
        TransitionRule("FORWARD", EVENT_COMPENSATE, "COMPENSATION.ROLLING_BACK")
    )
    root.add_transition(
        TransitionRule(
            "ROLLING_BACK",
            EVENT_ROLLBACK_DONE,
            "COMPENSATION.ROLLBACK_COMPLETED",
        )
    )
    root.add_transition(
        TransitionRule(
            "ROLLING_BACK",
            EVENT_ROLLBACK_FAIL,
            "COMPENSATION.ROLLBACK_FAILED",
        )
    )
    root.add_transition(
        TransitionRule("COMPENSATION", EVENT_ABORT, "TERMINATED.ABORTED")
    )


def build_saga_state_tree() -> HierarchicalStateMachine:
    """Constructs the Saga Transaction HSM tree."""
    root = StateNode("ROOT", initial_child="FORWARD")
    _add_saga_nodes(root)
    _register_saga_rules(root)
    return HierarchicalStateMachine(root)


def _add_scheduler_nodes(root: StateNode) -> None:
    """Builds node tree for WorkflowScheduler HSM."""
    op = root.add_child(StateNode("OPERATIONAL", initial_child="IDLE"))
    op.add_child(StateNode("IDLE"))
    op.add_child(StateNode("DISPATCHING"))
    op.add_child(StateNode("BACKPRESSURE_PAUSED"))

    trans = root.add_child(StateNode("TRANSITIONING", initial_child="DRAINING"))
    trans.add_child(StateNode("DRAINING"))

    term = root.add_child(StateNode("TERMINATED", initial_child="STOPPED"))
    term.add_child(StateNode("STOPPED"))
    term.add_child(StateNode("FAILED"))


def _register_scheduler_rules(root: StateNode) -> None:
    """Registers transition rules for WorkflowScheduler HSM."""
    root.add_transition(
        TransitionRule("IDLE", EVENT_DISPATCH, "OPERATIONAL.DISPATCHING")
    )
    root.add_transition(TransitionRule("DISPATCHING", EVENT_IDLE, "OPERATIONAL.IDLE"))
    root.add_transition(
        TransitionRule("OPERATIONAL", EVENT_PAUSE, "OPERATIONAL.BACKPRESSURE_PAUSED")
    )
    root.add_transition(
        TransitionRule("BACKPRESSURE_PAUSED", EVENT_RESUME, "OPERATIONAL.IDLE")
    )
    root.add_transition(
        TransitionRule("OPERATIONAL", EVENT_DRAIN, "TRANSITIONING.DRAINING")
    )
    root.add_transition(TransitionRule("DRAINING", EVENT_STOP, "TERMINATED.STOPPED"))
    root.add_transition(TransitionRule("OPERATIONAL", EVENT_FAIL, "TERMINATED.FAILED"))
    root.add_transition(
        TransitionRule("TRANSITIONING", EVENT_FAIL, "TERMINATED.FAILED")
    )


def build_scheduler_state_tree() -> HierarchicalStateMachine:
    """Constructs the WorkflowScheduler lifecycle HSM tree."""
    root = StateNode("ROOT", initial_child="OPERATIONAL")
    _add_scheduler_nodes(root)
    _register_scheduler_rules(root)
    return HierarchicalStateMachine(root)
