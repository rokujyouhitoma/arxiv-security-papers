#!/usr/bin/env python3
"""
Public exports for Hierarchical State Machine (HSM / Statecharts) core engine.
Zero external dependencies: Pure Python 3.14 standard library.
"""

from __future__ import annotations

from .contracts import (
    ActionCallback,
    EventContext,
    GuardCondition,
    LifecycleCallback,
    StateNode,
    TransitionRule,
)
from .engine import HierarchicalStateMachine, TransitionObserver
from .tree import (
    find_lcca,
    find_node_by_path,
    resolve_entry_path,
    resolve_exit_path,
    resolve_initial_leaf,
    validate_tree,
)

__all__ = [
    "ActionCallback",
    "EventContext",
    "GuardCondition",
    "HierarchicalStateMachine",
    "LifecycleCallback",
    "StateNode",
    "TransitionObserver",
    "TransitionRule",
    "find_lcca",
    "find_node_by_path",
    "resolve_entry_path",
    "resolve_exit_path",
    "resolve_initial_leaf",
    "validate_tree",
]
