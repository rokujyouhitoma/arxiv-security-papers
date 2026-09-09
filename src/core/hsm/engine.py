#!/usr/bin/env python3
"""
Core Execution Engine for Hierarchical State Machine (HSM / Statecharts).
Provides deterministic LCCA transitions, event bubbling, guard evaluation,
and fail-secure error handling.
Zero external dependencies: Pure Python 3.14 standard library.
"""

from __future__ import annotations

import logging
from typing import Any, Callable, Dict, List, Optional

from .contracts import ActionCallback, EventContext, StateNode, TransitionRule
from .tree import (
    find_lcca,
    find_node_by_path,
    resolve_entry_path,
    resolve_exit_path,
    resolve_initial_leaf,
    validate_tree,
)

logger = logging.getLogger(__name__)

TransitionObserver = Callable[[StateNode, StateNode, EventContext], None]


class HierarchicalStateMachine:
    """
    Statecharts-compliant hierarchical state machine engine.
    Executes atomic state transitions with strict LCCA boundary resolution,
    bottom-up exit passes, transition actions, top-down entry passes,
    and automatic event bubbling up the composite state hierarchy.
    """

    def __init__(
        self,
        root: StateNode,
        initial_state: Optional[StateNode] = None,
        fail_secure_target: Optional[str] = None,
    ) -> None:
        validate_tree(root)
        self.root = root
        self.fail_secure_target = fail_secure_target
        self._observers: List[TransitionObserver] = []

        if initial_state is not None:
            self.current_state = initial_state
        else:
            leaf, initial_entries = resolve_initial_leaf(root)
            self.current_state = leaf
            self._enter_initial_nodes(initial_entries)

    def _enter_initial_nodes(self, nodes: List[StateNode]) -> None:
        init_ctx = EventContext(event_name="__INIT__")
        for node in nodes:
            if node.on_entry is not None:
                node.on_entry(init_ctx)

    def add_observer(self, observer: TransitionObserver) -> None:
        """Registers an observer to receive notification upon state transitions."""
        self._observers.append(observer)

    def _matches_name_or_path(self, node: StateNode, target: str) -> bool:
        return node.name == target or node.get_path() == target

    def is_in_state(self, state_name_or_path: str) -> bool:
        """
        Evaluates whether current active state matches or is a descendant
        of specified state name or dot path.
        """
        if self._matches_name_or_path(self.current_state, state_name_or_path):
            return True
        for ancestor in self.current_state.get_ancestors():
            if self._matches_name_or_path(ancestor, state_name_or_path):
                return True
        return False

    def get_state_path(self) -> str:
        """Returns dotted path of currently active state."""
        return self.current_state.get_path()

    def _evaluate_node_rules(
        self, rules: List[TransitionRule], context: EventContext
    ) -> Optional[TransitionRule]:
        for rule in rules:
            if rule.guard is None or rule.guard(context):
                return rule
        return None

    def _find_rule(
        self, event_name: str, context: EventContext
    ) -> Optional[tuple[StateNode, TransitionRule]]:
        curr: Optional[StateNode] = self.current_state
        while curr is not None:
            rules = curr.transitions.get(event_name, [])
            matched = self._evaluate_node_rules(rules, context)
            if matched is not None:
                return curr, matched
            curr = curr.parent
        return None

    def _resolve_target_node(
        self, source_node: StateNode, target_name: str
    ) -> Optional[StateNode]:
        if "." in target_name:
            return find_node_by_path(self.root, target_name)
        parent = source_node.parent
        if parent is not None and target_name in parent.children:
            return parent.children[target_name]
        return find_node_by_path(self.root, target_name)

    def _notify_observers(
        self, from_node: StateNode, to_node: StateNode, context: EventContext
    ) -> None:
        for obs in self._observers:
            try:
                obs(from_node, to_node, context)
            except Exception:
                logger.exception("HSM transition observer failed.")

    def _run_exit_nodes(self, nodes: List[StateNode], context: EventContext) -> None:
        for node in nodes:
            if node.on_exit is not None:
                node.on_exit(context)

    def _run_entry_nodes(self, nodes: List[StateNode], context: EventContext) -> None:
        for node in nodes:
            if node.on_entry is not None:
                node.on_entry(context)

    def _execute_pass(
        self,
        exit_nodes: List[StateNode],
        entry_nodes: List[StateNode],
        action: Optional[ActionCallback],
        context: EventContext,
    ) -> None:
        self._run_exit_nodes(exit_nodes, context)
        if action is not None:
            action(context)
        self._run_entry_nodes(entry_nodes, context)

    def _handle_fail_secure(self, error: Exception) -> None:
        logger.error("Uncaught exception in HSM transition: %s", error)
        if self.fail_secure_target:
            self.force_transition(self.fail_secure_target, reason="FAIL_SECURE")

    def _compute_transition_plan(
        self, target_node: StateNode
    ) -> tuple[List[StateNode], List[StateNode], StateNode]:
        lcca = find_lcca(self.current_state, target_node)
        exit_nodes = resolve_exit_path(self.current_state, lcca)
        entry_nodes = resolve_entry_path(target_node, lcca)

        final_leaf, descent_path = resolve_initial_leaf(target_node)
        entry_nodes.extend(descent_path)
        return exit_nodes, entry_nodes, final_leaf

    def _dispatch_transition(
        self,
        target_node: StateNode,
        action: Optional[ActionCallback],
        context: EventContext,
    ) -> bool:
        exit_nodes, entry_nodes, final_leaf = self._compute_transition_plan(target_node)
        prior_state = self.current_state
        try:
            self._execute_pass(exit_nodes, entry_nodes, action, context)
            self.current_state = final_leaf
            self._notify_observers(prior_state, final_leaf, context)
            return True
        except Exception as exc:
            self._handle_fail_secure(exc)
            raise

    def send_event(
        self, event_name: str, payload: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Dispatches an event to the HSM.
        Returns True if a valid transition was found and executed; False otherwise.
        """
        context = EventContext(event_name=event_name, payload=payload or {})
        match = self._find_rule(event_name, context)
        if match is None:
            return False

        source_node, rule = match
        target_node = self._resolve_target_node(source_node, rule.target_name)
        if target_node is None:
            return False

        return self._dispatch_transition(target_node, rule.action, context)

    def force_transition(self, target_path: str, reason: str = "FORCED") -> bool:
        """
        Executes an unconditional transition to target_path, executing
        all proper exit and entry lifecycle handlers.
        """
        target_node = find_node_by_path(self.root, target_path)
        if target_node is None:
            return False

        context = EventContext(event_name="__FORCE__", payload={"reason": reason})
        return self._dispatch_transition(target_node, None, context)
