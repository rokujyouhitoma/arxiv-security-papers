#!/usr/bin/env python3
"""
B+Tree Index Engine for Paged Database Storage.
Supports O(log N) point lookups, range scans, and node balancing across 4096-byte pages.
"""

from typing import Dict, List, Optional, Tuple

from ..pager import Pager
from .node import BTreeNode, ScalarKey, compare_keys


class BPlusTree:
    """
    B+Tree implementation integrated with 4KB Database Pager.
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

        if root_page_id is not None:
            self.root_page_id = root_page_id
        else:
            self.root_page_id = self._allocate_page_id()
            root = BTreeNode(page_id=self.root_page_id, is_leaf=True)
            self._write_node(root)

    def _allocate_page_id(self) -> int:
        pid = self._next_page_id
        self._next_page_id += 1
        return pid

    def _read_node(self, page_id: int) -> BTreeNode:
        if self.pager is not None:
            raw_bytes = self.pager.read_page(page_id)
            return BTreeNode.deserialize(page_id, raw_bytes)
        if page_id in self._nodes:
            return self._nodes[page_id]
        node = BTreeNode(page_id=page_id, is_leaf=True)
        self._nodes[page_id] = node
        return node

    def _write_node(self, node: BTreeNode) -> None:
        if self.pager is not None:
            raw_bytes = node.serialize()
            self.pager.write_page(node.page_id, raw_bytes)
        else:
            self._nodes[node.page_id] = node

    def _find_leaf(self, key: ScalarKey) -> BTreeNode:
        """Navigates from root down to the target leaf node."""
        current = self._read_node(self.root_page_id)
        while not current.is_leaf:
            child_idx = 0
            for idx, k in enumerate(current.keys):
                if compare_keys(key, k) < 0:
                    break
                child_idx = idx + 1
            current = self._read_node(current.children[child_idx])
        return current

    def insert(self, key: ScalarKey, row_id: int) -> None:
        """Inserts a key and row_id into the B+Tree."""
        root = self._read_node(self.root_page_id)
        split_info = self._insert_internal(root, key, row_id)
        if split_info is not None:
            promoted_key, sibling_page_id = split_info
            new_root_id = self._allocate_page_id()
            new_root = BTreeNode(page_id=new_root_id, is_leaf=False)
            new_root.keys = [promoted_key]
            new_root.children = [self.root_page_id, sibling_page_id]
            self._write_node(new_root)
            self.root_page_id = new_root_id

    def _insert_internal(
        self, node: BTreeNode, key: ScalarKey, row_id: int
    ) -> Optional[Tuple[ScalarKey, int]]:
        if node.is_leaf:
            node.insert_leaf_entry(key, row_id)
            if node.is_full():
                new_page_id = self._allocate_page_id()
                promoted_key, sibling = node.split(new_page_id)
                self._write_node(node)
                self._write_node(sibling)
                return promoted_key, sibling.page_id
            self._write_node(node)
            return None

        # Interior node: route to child
        child_idx = 0
        for idx, k in enumerate(node.keys):
            if compare_keys(key, k) < 0:
                break
            child_idx = idx + 1

        child = self._read_node(node.children[child_idx])
        split_res = self._insert_internal(child, key, row_id)
        if split_res is not None:
            promoted_key, sibling_id = split_res
            node.keys.insert(child_idx, promoted_key)
            node.children.insert(child_idx + 1, sibling_id)
            if node.is_full():
                new_page_id = self._allocate_page_id()
                p_key, sibling = node.split(new_page_id)
                self._write_node(node)
                self._write_node(sibling)
                return p_key, sibling.page_id
            self._write_node(node)
        return None

    def search(self, key: ScalarKey) -> List[int]:
        """Returns matching row_ids for an exact key match in O(log N)."""
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

    def range_scan(
        self,
        min_key: Optional[ScalarKey] = None,
        max_key: Optional[ScalarKey] = None,
        include_min: bool = True,
        include_max: bool = True,
    ) -> List[int]:
        """
        Executes a range scan returning all matching row_ids in O(log N + M).
        """
        results: List[int] = []
        current: Optional[BTreeNode] = (
            self._find_leaf(min_key) if min_key is not None else self._find_first_leaf()
        )

        while current is not None:
            for idx, k in enumerate(current.keys):
                in_bounds, should_stop = self._key_in_bounds(
                    k, min_key, max_key, include_min, include_max
                )
                if should_stop:
                    return results
                if in_bounds:
                    results.extend(current.values[idx])

            if current.next_leaf is not None:
                current = self._read_node(current.next_leaf)
            else:
                break

        return results

    def _find_first_leaf(self) -> BTreeNode:
        """Finds the leftmost leaf node."""
        current = self._read_node(self.root_page_id)
        while not current.is_leaf:
            current = self._read_node(current.children[0])
        return current

    def delete(self, key: ScalarKey, row_id: int) -> bool:
        """Removes a row_id entry from a key."""
        leaf = self._find_leaf(key)
        for idx, k in enumerate(leaf.keys):
            if k == key:
                if row_id in leaf.values[idx]:
                    leaf.values[idx].remove(row_id)
                    if not leaf.values[idx]:
                        leaf.keys.pop(idx)
                        leaf.values.pop(idx)
                    self._write_node(leaf)
                    return True
        return False
