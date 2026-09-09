#!/usr/bin/env python3
"""
Contracts and data models for the Hierarchical State Machine (HSM / Statecharts) core engine.
Zero external dependencies: Pure Python 3.14 standard library.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

GuardCondition = Callable[["EventContext"], bool]
ActionCallback = Callable[["EventContext"], None]
LifecycleCallback = Callable[["EventContext"], None]


@dataclass(frozen=True)
class EventContext:
    """
    Carries event payload, source origin, and high-resolution timestamp across transitions.
    Immutable value object ensuring thread-safety and tamper resistance.
    """

    event_name: str
    payload: Dict[str, Any] = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)


@dataclass
class TransitionRule:
    """
    Encapsulates a transition pathway with guard validation and side-effect action.
    """

    source_name: str
    event_name: str
    target_name: str
    guard: Optional[GuardCondition] = None
    action: Optional[ActionCallback] = None


class StateNode:
    """
    Represents a composite or leaf node in the state hierarchy.
    Maintains parent-child links, initial child specifications, entry/exit callbacks,
    and registered transition rules.
    """

    def __init__(
        self,
        name: str,
        parent: Optional[StateNode] = None,
        initial_child: Optional[str] = None,
        on_entry: Optional[LifecycleCallback] = None,
        on_exit: Optional[LifecycleCallback] = None,
    ) -> None:
        self.name = name
        self.parent = parent
        self.initial_child = initial_child
        self.on_entry = on_entry
        self.on_exit = on_exit
        self.children: Dict[str, StateNode] = {}
        self.transitions: Dict[str, List[TransitionRule]] = {}

    def is_leaf(self) -> bool:
        """Returns True if the node has no children."""
        return len(self.children) == 0

    def is_root(self) -> bool:
        """Returns True if this node is the top-level root node."""
        return self.parent is None

    @property
    def depth(self) -> int:
        """Calculates 0-indexed hierarchy depth from root."""
        depth = 0
        curr: Optional[StateNode] = self.parent
        while curr is not None:
            depth += 1
            curr = curr.parent
        return depth

    def get_path(self) -> str:
        """
        Returns dotted hierarchical path (e.g. 'OPERATIONAL.ACTIVE.PROCESSING').
        Omits leading 'ROOT' node name if present.
        """
        if self.parent is None:
            return "" if self.name == "ROOT" else self.name
        parent_path = self.parent.get_path()
        if not parent_path:
            return self.name
        return f"{parent_path}.{self.name}"

    def get_ancestors(self) -> List[StateNode]:
        """
        Returns list of ancestors starting from self up to the root.
        """
        ancestors: List[StateNode] = []
        curr: Optional[StateNode] = self
        while curr is not None:
            ancestors.append(curr)
            curr = curr.parent
        return ancestors

    def add_child(self, child: StateNode) -> StateNode:
        """Attaches a child state node and binds parent relationship."""
        child.parent = self
        self.children[child.name] = child
        return child

    def add_transition(self, rule: TransitionRule) -> None:
        """Registers a transition rule mapped to its triggering event name."""
        if rule.event_name not in self.transitions:
            self.transitions[rule.event_name] = []
        self.transitions[rule.event_name].append(rule)
