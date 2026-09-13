#!/usr/bin/env python3
"""
B+Tree Index Engine for Paged Database Storage.
Implements Lehman-Yao B-link tree latch-free concurrent search, atomic half-split,
and fine-grained page latching across 4096-byte pages.
"""

import threading
from typing import Dict, List, Optional, Set, Tuple

from ..pager import Pager
from .node import BTreeNode, ScalarKey, compare_keys


class CyclicPointerError(RuntimeError):
    """Raised when a circular right-link or excessive hops are detected during B-link traversal."""

    pass


class BPlusTree:
    """
    B-link Tree implementation integrated with 4KB Database Pager.
    Supports latch-free point lookups and range scans with Lehman-Yao right-drift.
    """

    def __init__(
        self,
        pager: Optional[Pager] = None,
        root_page_id: Optional[int] = None,
        column_name: str = "id",
    ) -> None:
        self.pager = pager
        self.column_name = column_name
        self._nodes: Dict[int, BTreeNode] = {}
        self._next_page_id = 1
        self._root_lock = threading.RLock()
        self._alloc_lock = threading.Lock()
        self._nodes_lock = threading.Lock()
        self._page_latches: Dict[int, threading.RLock] = {}
        self._latch_dict_lock = threading.Lock()

        if root_page_id is not None:
            self.root_page_id = root_page_id
        else:
            self.root_page_id = self._allocate_page_id()
            root = BTreeNode(page_id=self.root_page_id, is_leaf=True)
            self._write_node(root)

    def _allocate_page_id(self) -> int:
        with self._alloc_lock:
            pid = self._next_page_id
            self._next_page_id += 1
            return pid

    def _get_page_latch(self, page_id: int) -> threading.RLock:
        with self._latch_dict_lock:
            if page_id not in self._page_latches:
                self._page_latches[page_id] = threading.RLock()
            return self._page_latches[page_id]

    def max_safe_hops(self) -> int:
        count = len(self._nodes)
        if self.pager is not None:
            count = max(count, getattr(self.pager, "page_count", 0))
        return max(1024, count, self._next_page_id)

    def _read_node(self, page_id: int) -> BTreeNode:
        if self.pager is not None:
            raw_bytes = self.pager.read_page(page_id)
            return BTreeNode.deserialize(page_id, raw_bytes)
        with self._nodes_lock:
            if page_id in self._nodes:
                raw = self._nodes[page_id].serialize()
                return BTreeNode.deserialize(page_id, raw)
            node = BTreeNode(page_id=page_id, is_leaf=True)
            self._nodes[page_id] = node
            return node

    def _write_node(self, node: BTreeNode) -> None:
        raw_bytes = node.serialize()
        if self.pager is not None:
            self.pager.write_page(node.page_id, raw_bytes)
        else:
            with self._nodes_lock:
                self._nodes[node.page_id] = BTreeNode.deserialize(
                    node.page_id, raw_bytes
                )

    def _step_right(
        self, curr: BTreeNode, visited: Set[int], hops: int
    ) -> Tuple[BTreeNode, int]:
        if curr.right_link is None:
            return curr, hops
        next_id = curr.right_link
        if next_id in visited:
            raise CyclicPointerError(f"B-link cycle detected at page {next_id}")
        visited.add(next_id)
        next_node = self._read_node(next_id)
        hops += 1
        if hops > self.max_safe_hops():
            raise CyclicPointerError(f"B-link cycle detected at page {curr.page_id}")
        return next_node, hops

    def _move_right(self, node: BTreeNode, key: ScalarKey) -> BTreeNode:
        """Navigates right along sibling pointers if key exceeds high_key."""
        curr = node
        hops = 0
        visited = {curr.page_id}
        while curr.high_key is not None and compare_keys(key, curr.high_key) > 0:
            if curr.right_link is None:
                break
            curr, hops = self._step_right(curr, visited, hops)
        return curr

    def _find_child_idx(self, node: BTreeNode, key: ScalarKey) -> int:
        child_idx = 0
        for idx, k in enumerate(node.keys):
            if compare_keys(key, k) < 0:
                break
            child_idx = idx + 1
        return child_idx

    def _find_leaf_with_path(self, key: ScalarKey) -> Tuple[BTreeNode, List[int]]:
        ancestors: List[int] = []
        with self._root_lock:
            curr_id = self.root_page_id
        current = self._read_node(curr_id)
        while not current.is_leaf:
            current = self._move_right(current, key)
            ancestors.append(current.page_id)
            child_idx = self._find_child_idx(current, key)
            current = self._read_node(current.children[child_idx])
        current = self._move_right(current, key)
        return current, ancestors

    def _find_leaf(self, key: ScalarKey) -> BTreeNode:
        """Navigates from root down to target leaf node using Lehman-Yao right-drift."""
        leaf, _ = self._find_leaf_with_path(key)
        return leaf

    def _acquire_latched_leaf(
        self, key: ScalarKey
    ) -> Tuple[BTreeNode, threading.RLock, List[int]]:
        leaf, ancestors = self._find_leaf_with_path(key)
        latch = self._get_page_latch(leaf.page_id)
        latch.acquire()
        leaf = self._read_node(leaf.page_id)
        while leaf.high_key is not None and compare_keys(key, leaf.high_key) > 0:
            if leaf.right_link is None:
                break
            next_latch = self._get_page_latch(leaf.right_link)
            next_latch.acquire()
            latch.release()
            latch = next_latch
            leaf = self._read_node(leaf.right_link)
        return leaf, latch, ancestors

    def _split_and_propagate_leaf(
        self, leaf: BTreeNode, latch: threading.RLock, ancestors: List[int]
    ) -> None:
        new_page_id = self._allocate_page_id()
        promoted_key, sibling = leaf.split(new_page_id)
        # Phase 1: Pre-persist new right node
        self._write_node(sibling)
        # Phase 2: Update original node with high_key & right_link, then write
        self._write_node(leaf)
        # Readers can now access sibling via leaf.right_link
        latch.release()
        # Phase 3: Propagate split upward
        self._propagate_split(leaf.page_id, promoted_key, sibling.page_id, ancestors)

    def insert(self, key: ScalarKey, row_id: int) -> None:
        """Inserts a key and row_id using Lehman-Yao B-link concurrency."""
        leaf, latch, ancestors = self._acquire_latched_leaf(key)
        leaf.insert_leaf_entry(key, row_id)
        if leaf.is_full():
            self._split_and_propagate_leaf(leaf, latch, ancestors)
        else:
            self._write_node(leaf)
            latch.release()

    def _create_new_root(
        self, left_id: int, promoted_key: ScalarKey, right_id: int
    ) -> None:
        new_root_id = self._allocate_page_id()
        new_root = BTreeNode(page_id=new_root_id, is_leaf=False)
        new_root.keys = [promoted_key]
        new_root.children = [left_id, right_id]
        self._write_node(new_root)
        self.root_page_id = new_root_id

    def _find_parent_for_key(self, key: ScalarKey, child_page_id: int) -> int:
        with self._root_lock:
            curr = self._read_node(self.root_page_id)
        while not curr.is_leaf:
            curr = self._move_right(curr, key)
            if child_page_id in curr.children:
                return curr.page_id
            child_idx = self._find_child_idx(curr, key)
            next_node = self._read_node(curr.children[child_idx])
            if next_node.is_leaf:
                return curr.page_id
            curr = next_node
        return self.root_page_id

    def _find_parent_id(
        self, ancestors: List[int], promoted_key: ScalarKey, left_child_id: int
    ) -> int:
        if ancestors:
            return ancestors.pop()
        return self._find_parent_for_key(promoted_key, left_child_id)

    def _drift_parent_latch(
        self, parent: BTreeNode, latch: threading.RLock, key: ScalarKey
    ) -> Tuple[BTreeNode, threading.RLock]:
        curr = parent
        curr_latch = latch
        while curr.high_key is not None and compare_keys(key, curr.high_key) > 0:
            if curr.right_link is None:
                break
            next_latch = self._get_page_latch(curr.right_link)
            next_latch.acquire()
            curr_latch.release()
            curr_latch = next_latch
            curr = self._read_node(curr.right_link)
        return curr, curr_latch

    def _insert_child_into_parent(
        self, parent: BTreeNode, left_id: int, key: ScalarKey, right_id: int
    ) -> None:
        if left_id in parent.children:
            idx = parent.children.index(left_id)
        else:
            idx = self._find_child_idx(parent, key)
        parent.keys.insert(idx, key)
        parent.children.insert(idx + 1, right_id)

    def _split_and_propagate_interior(
        self, parent: BTreeNode, latch: threading.RLock, ancestors: List[int]
    ) -> None:
        new_parent_id = self._allocate_page_id()
        p_key, sibling = parent.split(new_parent_id)
        self._write_node(sibling)
        self._write_node(parent)
        latch.release()
        self._propagate_split(parent.page_id, p_key, sibling.page_id, ancestors)

    def _propagate_split(
        self,
        left_child_id: int,
        promoted_key: ScalarKey,
        right_child_id: int,
        ancestors: List[int],
    ) -> None:
        with self._root_lock:
            if left_child_id == self.root_page_id:
                self._create_new_root(left_child_id, promoted_key, right_child_id)
                return

        parent_id = self._find_parent_id(ancestors, promoted_key, left_child_id)
        parent_latch = self._get_page_latch(parent_id)
        parent_latch.acquire()
        parent = self._read_node(parent_id)

        parent, parent_latch = self._drift_parent_latch(
            parent, parent_latch, promoted_key
        )
        self._insert_child_into_parent(
            parent, left_child_id, promoted_key, right_child_id
        )

        if parent.is_full():
            self._split_and_propagate_interior(parent, parent_latch, ancestors)
        else:
            self._write_node(parent)
            parent_latch.release()

    def search(self, key: ScalarKey) -> List[int]:
        """Returns matching row_ids for an exact key match in latch-free O(log N)."""
        leaf = self._find_leaf(key)
        for idx, k in enumerate(leaf.keys):
            if compare_keys(k, key) == 0:
                return list(leaf.values[idx])
        return []

    def _is_below_min(
        self, k: ScalarKey, min_key: Optional[ScalarKey], include_min: bool
    ) -> bool:
        if min_key is None:
            return False
        cmp = compare_keys(k, min_key)
        return cmp < 0 if include_min else cmp <= 0

    def _is_above_max(
        self, k: ScalarKey, max_key: Optional[ScalarKey], include_max: bool
    ) -> bool:
        if max_key is None:
            return False
        cmp = compare_keys(k, max_key)
        return cmp > 0 if include_max else cmp >= 0

    def _key_in_bounds(
        self,
        k: ScalarKey,
        min_key: Optional[ScalarKey],
        max_key: Optional[ScalarKey],
        include_min: bool,
        include_max: bool,
    ) -> Tuple[bool, bool]:
        """Returns (in_bounds, should_stop)."""
        if self._is_above_max(k, max_key, include_max):
            return False, True
        if self._is_below_min(k, min_key, include_min):
            return False, False
        return True, False

    def _scan_leaf_keys(
        self,
        current: BTreeNode,
        min_key: Optional[ScalarKey],
        max_key: Optional[ScalarKey],
        include_min: bool,
        include_max: bool,
        results: List[int],
    ) -> bool:
        """Scans keys in current leaf; returns True if scanning should stop."""
        for idx, k in enumerate(current.keys):
            in_bounds, should_stop = self._key_in_bounds(
                k, min_key, max_key, include_min, include_max
            )
            if should_stop:
                return True
            if in_bounds:
                results.extend(current.values[idx])
        return False

    def _find_first_leaf(self) -> BTreeNode:
        """Finds the leftmost leaf node."""
        with self._root_lock:
            curr_id = self.root_page_id
        current = self._read_node(curr_id)
        while not current.is_leaf:
            current = self._read_node(current.children[0])
        return current

    def _step_scan_leaf(
        self, current: BTreeNode, hops: int, visited: Set[int]
    ) -> Tuple[Optional[BTreeNode], int]:
        if current.right_link is None:
            return None, hops
        next_id = current.right_link
        if next_id in visited:
            raise CyclicPointerError(f"B-link cycle in range_scan at {next_id}")
        visited.add(next_id)
        hops += 1
        if hops > self.max_safe_hops():
            raise CyclicPointerError(f"B-link max hops exceeded in range_scan ({hops})")
        return self._read_node(next_id), hops

    def range_scan(
        self,
        min_key: Optional[ScalarKey] = None,
        max_key: Optional[ScalarKey] = None,
        include_min: bool = True,
        include_max: bool = True,
    ) -> List[int]:
        """Executes range scan returning matching row_ids across right_link sibling chain."""
        results: List[int] = []
        current: Optional[BTreeNode] = (
            self._find_leaf(min_key) if min_key is not None else self._find_first_leaf()
        )
        hops = 0
        visited = {current.page_id} if current is not None else set()
        while current is not None:
            should_stop = self._scan_leaf_keys(
                current, min_key, max_key, include_min, include_max, results
            )
            if should_stop:
                break
            current, hops = self._step_scan_leaf(current, hops, visited)
        return results

    def _delete_entry_from_leaf(
        self, leaf: BTreeNode, key: ScalarKey, row_id: int
    ) -> bool:
        for idx, k in enumerate(leaf.keys):
            if compare_keys(k, key) == 0:
                if row_id in leaf.values[idx]:
                    leaf.values[idx].remove(row_id)
                    if not leaf.values[idx]:
                        leaf.keys.pop(idx)
                        leaf.values.pop(idx)
                    self._write_node(leaf)
                    return True
        return False

    def delete(self, key: ScalarKey, row_id: int) -> bool:
        """Removes a row_id entry from a key under leaf latch."""
        leaf, latch, _ = self._acquire_latched_leaf(key)
        try:
            return self._delete_entry_from_leaf(leaf, key, row_id)
        finally:
            latch.release()
