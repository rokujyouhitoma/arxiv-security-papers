#!/usr/bin/env python3
"""
Hierarchy tree traversal, LCCA resolution, and tree validation utilities for HSM.
Zero external dependencies: Pure Python 3.14 standard library.
"""

from __future__ import annotations

from typing import List, Optional, Set

from .contracts import StateNode


def _find_common_ancestor(
    target: StateNode, source_ids: Set[int]
) -> Optional[StateNode]:
    curr: Optional[StateNode] = target
    while curr is not None:
        if id(curr) in source_ids:
            return curr
        curr = curr.parent
    return None


def find_lcca(source: StateNode, target: StateNode) -> Optional[StateNode]:
    """
    Finds Lowest Common Composite Ancestor (LCCA) between source and target.
    Handles intra-state, cross-hierarchy, ancestor, and self-transitions deterministically.
    Time Complexity: O(Depth) <= O(4) = O(1).
    """
    if source == target:
        return source.parent

    source_ids = {id(n) for n in source.get_ancestors()}
    if id(target) in source_ids:
        return target.parent

    return _find_common_ancestor(target, source_ids)


def resolve_exit_path(source: StateNode, lcca: Optional[StateNode]) -> List[StateNode]:
    """
    Calculates bottom-up exit path from source up to (excluding) LCCA.
    """
    exit_path: List[StateNode] = []
    curr: Optional[StateNode] = source
    while curr is not None and curr != lcca:
        exit_path.append(curr)
        curr = curr.parent
    return exit_path


def resolve_entry_path(target: StateNode, lcca: Optional[StateNode]) -> List[StateNode]:
    """
    Calculates top-down entry path from (excluding) LCCA down to target.
    """
    entry_path: List[StateNode] = []
    curr: Optional[StateNode] = target
    while curr is not None and curr != lcca:
        entry_path.append(curr)
        curr = curr.parent
    entry_path.reverse()
    return entry_path


def resolve_initial_leaf(
    composite: StateNode,
) -> tuple[StateNode, List[StateNode]]:
    """
    Recursively descends initial_child links to find active leaf node.
    """
    descendants: List[StateNode] = []
    curr = composite
    while curr.initial_child and curr.initial_child in curr.children:
        curr = curr.children[curr.initial_child]
        descendants.append(curr)
    return curr, descendants


def _filter_non_empty(parts: List[str]) -> List[str]:
    return [p for p in parts if p]


def _parse_path_segments(root: StateNode, path: str) -> List[str]:
    if not path:
        return []
    segments = _filter_non_empty([s.strip() for s in path.split(".")])
    if segments and root.name == segments[0]:
        return segments[1:]
    return segments


def _descend_path(root: StateNode, segments: List[str]) -> Optional[StateNode]:
    curr = root
    for seg in segments:
        child = curr.children.get(seg)
        if child is None:
            return None
        curr = child
    return curr


def find_node_by_path(root: StateNode, path: str) -> Optional[StateNode]:
    """
    Resolves a dot-separated path from root (e.g. 'OPERATIONAL.ACTIVE.IDLE').
    """
    if not path:
        return None
    segments = _parse_path_segments(root, path)
    if not segments:
        return root if root.name == path.strip() else None
    return _descend_path(root, segments)


def validate_tree(root: StateNode, max_depth: int = 6) -> None:
    """
    Validates tree depth and guards against cyclical node relationships.
    """
    visited_ids: Set[int] = set()

    def _walk(node: StateNode, depth: int) -> None:
        if depth > max_depth:
            raise ValueError(
                f"State hierarchy exceeds max depth of {max_depth} at '{node.name}'"
            )
        if id(node) in visited_ids:
            raise ValueError(
                f"Cyclic reference detected in state tree at '{node.name}'"
            )
        visited_ids.add(id(node))
        for child in node.children.values():
            if child.parent != node:
                raise ValueError(
                    f"Invalid parent reference in child '{child.name}' of '{node.name}'"
                )
            _walk(child, depth + 1)

    _walk(root, 0)
