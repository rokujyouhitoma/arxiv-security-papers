#!/usr/bin/env python3
"""
Zero-dependency, memory-efficient SkipList (probabilistic ordered key-value map).
Provides O(log N) search, insertion, deletion, and O(log N + M) range scan.
"""

from __future__ import annotations

import random
from typing import Any, Generic, Iterator, List, Optional, Tuple, TypeVar

K = TypeVar("K", bound=Any)
V = TypeVar("V", bound=Any)

DEFAULT_MAX_LEVEL: int = 16
MAX_ALLOWED_LEVEL: int = 32
DEFAULT_P: float = 0.5


class SkipListNode(Generic[K, V]):
    """Node in a SkipList holding a key, value, and forward level pointers."""

    __slots__ = ("forward", "key", "value")

    def __init__(
        self,
        key: Optional[K],
        value: Optional[V],
        level: int,
    ) -> None:
        self.key: Optional[K] = key
        self.value: Optional[V] = value
        self.forward: List[Optional[SkipListNode[K, V]]] = [None] * level


def _random_level(max_level: int, p: float) -> int:
    """Generates a random level for a new node."""
    lvl = 1
    while lvl < max_level and random.random() < p:
        lvl += 1
    return lvl


def _step_search(
    curr: SkipListNode[K, V],
    lvl: int,
    target_key: K,
) -> SkipListNode[K, V]:
    """Steps forward on level lvl while next node's key is less than target_key."""
    while True:
        nxt = curr.forward[lvl]
        if nxt is None or nxt.key is None or nxt.key >= target_key:
            break
        curr = nxt
    return curr


def _collect_update_path(
    header: SkipListNode[K, V],
    max_level: int,
    target_key: K,
) -> List[SkipListNode[K, V]]:
    """Finds the update path (predecessors) for target_key across all levels."""
    update: List[SkipListNode[K, V]] = [header] * max_level
    curr = header
    for lvl in range(max_level - 1, -1, -1):
        curr = _step_search(curr, lvl, target_key)
        update[lvl] = curr
    return update


def _link_new_node(
    new_node: SkipListNode[K, V],
    update: List[SkipListNode[K, V]],
    node_level: int,
) -> None:
    """Links new node into forward pointers at each level up to node_level."""
    for lvl in range(node_level):
        new_node.forward[lvl] = update[lvl].forward[lvl]
        update[lvl].forward[lvl] = new_node


def _unlink_node(
    target_node: SkipListNode[K, V],
    update: List[SkipListNode[K, V]],
    max_level: int,
) -> None:
    """Unlinks target_node from forward pointers at each level."""
    for lvl in range(max_level):
        if update[lvl].forward[lvl] == target_node:
            update[lvl].forward[lvl] = target_node.forward[lvl]


def _is_valid_node(curr: Optional[SkipListNode[K, V]]) -> bool:
    """Checks if node is present and holds both key and value."""
    if curr is None:
        return False
    return curr.key is not None and curr.value is not None


def _can_continue_range(
    curr: Optional[SkipListNode[K, V]],
    end_key: Optional[K],
) -> bool:
    """Checks if node is valid and strictly less than end_key."""
    if not _is_valid_node(curr):
        return False
    assert curr is not None and curr.key is not None
    if end_key is not None and curr.key >= end_key:
        return False
    return True


class SkipList(Generic[K, V]):
    """
    Probabilistic ordered dictionary with O(log N) operations.
    Maintains keys in strictly ascending sorted order.
    """

    def __init__(
        self,
        max_level: int = DEFAULT_MAX_LEVEL,
        p: float = DEFAULT_P,
    ) -> None:
        self.max_level = min(max(1, max_level), MAX_ALLOWED_LEVEL)
        self.p = max(0.01, min(0.99, p))
        self.header: SkipListNode[K, V] = SkipListNode(None, None, self.max_level)
        self.level: int = 1
        self._size: int = 0

    def __len__(self) -> int:
        return self._size

    def __contains__(self, key: K) -> bool:
        return self.get(key) is not None or self._key_exists(key)

    def _find_exact(self, key: K) -> Optional[SkipListNode[K, V]]:
        """Finds node with matching key if present."""
        curr = self.header
        for lvl in range(self.level - 1, -1, -1):
            curr = _step_search(curr, lvl, key)
        candidate = curr.forward[0]
        if candidate is not None and candidate.key == key:
            return candidate
        return None

    def _key_exists(self, key: K) -> bool:
        return self._find_exact(key) is not None

    def get(self, key: K, default: Optional[V] = None) -> Optional[V]:
        """Gets value for key, or default if not found."""
        node = self._find_exact(key)
        if node is not None:
            return node.value
        return default

    def insert(self, key: K, value: V) -> None:
        """Inserts or updates a key-value pair."""
        update = _collect_update_path(self.header, self.max_level, key)
        candidate = update[0].forward[0]
        if candidate is not None and candidate.key == key:
            candidate.value = value
            return

        lvl = _random_level(self.max_level, self.p)
        if lvl > self.level:
            self.level = lvl

        new_node: SkipListNode[K, V] = SkipListNode(key, value, lvl)
        _link_new_node(new_node, update, lvl)
        self._size += 1

    def put(self, key: K, value: V) -> None:
        """Alias for insert(key, value)."""
        self.insert(key, value)

    def delete(self, key: K) -> bool:
        """Deletes key if present. Returns True if deleted, False otherwise."""
        update = _collect_update_path(self.header, self.max_level, key)
        candidate = update[0].forward[0]
        if candidate is None or candidate.key != key:
            return False

        _unlink_node(candidate, update, self.level)
        self._size -= 1
        self._adjust_level_after_deletion()
        return True

    def remove(self, key: K) -> bool:
        """Alias for delete(key)."""
        return self.delete(key)

    def _adjust_level_after_deletion(self) -> None:
        while self.level > 1 and self.header.forward[self.level - 1] is None:
            self.level -= 1

    def clear(self) -> None:
        """Removes all elements from the skip list."""
        self.header = SkipListNode(None, None, self.max_level)
        self.level = 1
        self._size = 0

    def items(self) -> List[Tuple[K, V]]:
        """Returns all (key, value) pairs sorted ascending by key."""
        res: List[Tuple[K, V]] = []
        curr = self.header.forward[0]
        while curr is not None:
            if curr.key is not None and curr.value is not None:
                res.append((curr.key, curr.value))
            curr = curr.forward[0]
        return res

    def keys(self) -> List[K]:
        """Returns all keys sorted ascending."""
        res: List[K] = []
        curr = self.header.forward[0]
        while curr is not None:
            if curr.key is not None:
                res.append(curr.key)
            curr = curr.forward[0]
        return res

    def values(self) -> List[V]:
        """Returns all values in ascending key order."""
        res: List[V] = []
        curr = self.header.forward[0]
        while curr is not None:
            if curr.value is not None:
                res.append(curr.value)
            curr = curr.forward[0]
        return res

    def __iter__(self) -> Iterator[Tuple[K, V]]:
        curr = self.header.forward[0]
        while curr is not None:
            if curr.key is not None and curr.value is not None:
                yield (curr.key, curr.value)
            curr = curr.forward[0]

    def _find_start_node(self, start_key: Optional[K]) -> Optional[SkipListNode[K, V]]:
        """Finds first node >= start_key in O(log N)."""
        if start_key is None:
            return self.header.forward[0]
        curr = self.header
        for lvl in range(self.level - 1, -1, -1):
            curr = _step_search(curr, lvl, start_key)
        return curr.forward[0]

    def range(
        self,
        start_key: Optional[K] = None,
        end_key: Optional[K] = None,
    ) -> List[Tuple[K, V]]:
        """
        Scans range [start_key, end_key) in ascending order in O(log N + M).
        """
        res: List[Tuple[K, V]] = []
        curr = self._find_start_node(start_key)
        while _can_continue_range(curr, end_key):
            assert curr is not None and curr.key is not None and curr.value is not None
            res.append((curr.key, curr.value))
            curr = curr.forward[0]
        return res
