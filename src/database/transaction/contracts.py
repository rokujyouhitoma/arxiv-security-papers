#!/usr/bin/env python3
"""
ARIES Crash Recovery HSM contracts and state tree builders.
Zero external dependencies: Pure Python 3.14 standard library.
"""

from __future__ import annotations

from core.hsm import HierarchicalStateMachine, StateNode, TransitionRule

# Event constants for ARIES Recovery HSM
EVENT_START_RECOVERY = "EVENT_START_RECOVERY"
EVENT_NO_RECOVERY = "EVENT_NO_RECOVERY"
EVENT_ANALYSIS_DONE = "EVENT_ANALYSIS_DONE"
EVENT_REDO_DONE = "EVENT_REDO_DONE"
EVENT_UNDO_DONE = "EVENT_UNDO_DONE"
EVENT_FAIL = "EVENT_FAIL"


def _add_recovery_operational_nodes(root: StateNode) -> None:
    """Builds the OPERATIONAL state hierarchy for ARIES Recovery HSM."""
    op = root.add_child(StateNode("OPERATIONAL", initial_child="IDLE"))
    op.add_child(StateNode("IDLE"))
    rec = op.add_child(StateNode("RECOVERY", initial_child="ANALYSIS"))
    rec.add_child(StateNode("ANALYSIS"))
    rec.add_child(StateNode("REDO"))
    rec.add_child(StateNode("UNDO"))


def _add_recovery_terminated_nodes(root: StateNode) -> None:
    """Builds the TERMINATED state hierarchy for ARIES Recovery HSM."""
    term = root.add_child(StateNode("TERMINATED", initial_child="COMPLETED"))
    term.add_child(StateNode("COMPLETED"))
    term.add_child(StateNode("NO_RECOVERY_NEEDED"))
    term.add_child(StateNode("FAILED"))


def _register_recovery_transition_rules(root: StateNode) -> None:
    """Registers transition pathways for ARIES Recovery HSM."""
    root.add_transition(
        TransitionRule("IDLE", EVENT_START_RECOVERY, "OPERATIONAL.RECOVERY.ANALYSIS")
    )
    root.add_transition(
        TransitionRule("IDLE", EVENT_NO_RECOVERY, "TERMINATED.NO_RECOVERY_NEEDED")
    )
    root.add_transition(
        TransitionRule("ANALYSIS", EVENT_ANALYSIS_DONE, "OPERATIONAL.RECOVERY.REDO")
    )
    root.add_transition(
        TransitionRule("REDO", EVENT_REDO_DONE, "OPERATIONAL.RECOVERY.UNDO")
    )
    root.add_transition(TransitionRule("UNDO", EVENT_UNDO_DONE, "TERMINATED.COMPLETED"))
    root.add_transition(TransitionRule("OPERATIONAL", EVENT_FAIL, "TERMINATED.FAILED"))


def build_aries_recovery_state_tree() -> HierarchicalStateMachine:
    """Constructs the ARIES Crash Recovery lifecycle HSM tree."""
    root = StateNode("ROOT", initial_child="OPERATIONAL")
    _add_recovery_operational_nodes(root)
    _add_recovery_terminated_nodes(root)
    _register_recovery_transition_rules(root)
    return HierarchicalStateMachine(root)
