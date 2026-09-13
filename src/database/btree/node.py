#!/usr/bin/env python3
"""
B+Tree Node Implementation for 4096-Byte Paged Database Storage.
Supports Lehman-Yao B-link tree High Key and Right Link serialization and splitting.
"""

import json
from typing import Any, Dict, List, Optional, Tuple, Union

ScalarKey = Union[int, float, str]


def _cmp_values(v1: Any, v2: Any) -> int:
    if v1 > v2:
        return 1
    if v1 < v2:
        return -1
    return 0


def compare_keys(k1: ScalarKey, k2: ScalarKey) -> int:
    """Safely compares two scalar keys of potentially different types (-1, 0, 1)."""
    if isinstance(k1, (int, float)) and isinstance(k2, (int, float)):
        return _cmp_values(k1, k2)
    return _cmp_values(str(k1), str(k2))


class BTreeNode:
    """
    Represents a single B-link Tree node stored inside a 4096-byte database page.
    Maintains High Key and Right Link invariants for latch-free concurrent traversal.
    """

    MAX_KEYS = 32  # Balanced fanout for 4KB page safety

    def __init__(
        self,
        page_id: int,
        is_leaf: bool = True,
        next_leaf: Optional[int] = None,
        prev_leaf: Optional[int] = None,
        high_key: Optional[ScalarKey] = None,
        right_link: Optional[int] = None,
    ) -> None:
        self.page_id = page_id
        self.is_leaf = is_leaf
        self.keys: List[ScalarKey] = []
        # For leaf nodes: values are lists of integer row_ids associated with each key
        self.values: List[List[int]] = []
        # For interior nodes: children are page_ids (len(children) == len(keys) + 1)
        self.children: List[int] = []
        self.prev_leaf = prev_leaf
        self.high_key: Optional[ScalarKey] = high_key
        self.right_link: Optional[int] = (
            right_link if right_link is not None else next_leaf
        )

    @property
    def next_leaf(self) -> Optional[int]:
        """Maintains backward compatibility with B+Tree leaf sibling pointer."""
        return self.right_link if self.is_leaf else None

    @next_leaf.setter
    def next_leaf(self, val: Optional[int]) -> None:
        self.right_link = val

    def is_full(self) -> bool:
        return len(self.keys) >= self.MAX_KEYS

    def serialize(self) -> bytes:
        """Serializes node structure to 4096-byte page payload with zero padding."""
        data: Dict[str, Any] = {
            "page_id": self.page_id,
            "is_leaf": self.is_leaf,
            "keys": self.keys,
            "values": self.values if self.is_leaf else [],
            "children": self.children if not self.is_leaf else [],
            "next_leaf": self.next_leaf,
            "prev_leaf": self.prev_leaf,
            "high_key": self.high_key,
            "right_link": self.right_link,
        }
        encoded = json.dumps(data, ensure_ascii=False).encode("utf-8")
        if len(encoded) > 4096:
            raise ValueError(
                f"BTreeNode {self.page_id} payload exceeds 4096 bytes ({len(encoded)} bytes)"
            )
        return encoded.ljust(4096, b"\x00")

    @classmethod
    def deserialize(
        cls, page_id: int, raw_bytes: Union[bytes, bytearray]
    ) -> "BTreeNode":
        """Deserializes node structure from raw 4096-byte page."""
        raw_str = bytes(raw_bytes).rstrip(b"\x00").decode("utf-8", errors="replace")
        if not raw_str.strip():
            return cls(page_id=page_id, is_leaf=True)
        data = json.loads(raw_str)
        node = cls(
            page_id=data.get("page_id", page_id),
            is_leaf=data.get("is_leaf", True),
            prev_leaf=data.get("prev_leaf"),
            high_key=data.get("high_key"),
            right_link=data.get("right_link", data.get("next_leaf")),
        )
        node.keys = data.get("keys", [])
        node.values = data.get("values", [])
        node.children = data.get("children", [])
        return node

    def insert_leaf_entry(self, key: ScalarKey, row_id: int) -> None:
        """Inserts a key and row_id into a leaf node maintaining sorted key order."""
        for idx, k in enumerate(self.keys):
            cmp = compare_keys(k, key)
            if cmp == 0:
                if row_id not in self.values[idx]:
                    self.values[idx].append(row_id)
                return
            if cmp > 0:
                self.keys.insert(idx, key)
                self.values.insert(idx, [row_id])
                return
        self.keys.append(key)
        self.values.append([row_id])

    def _split_leaf(self, sibling: "BTreeNode", mid: int) -> ScalarKey:
        promoted_key = self.keys[mid]
        sibling.keys = self.keys[mid:]
        sibling.values = self.values[mid:]
        self.keys = self.keys[:mid]
        self.values = self.values[:mid]
        self.high_key = self.keys[-1]
        self.right_link = sibling.page_id
        return promoted_key

    def _split_interior(self, sibling: "BTreeNode", mid: int) -> ScalarKey:
        promoted_key = self.keys[mid]
        sibling.keys = self.keys[mid + 1 :]
        sibling.children = self.children[mid + 1 :]
        self.keys = self.keys[:mid]
        self.children = self.children[: mid + 1]
        self.high_key = promoted_key
        self.right_link = sibling.page_id
        return promoted_key

    def split(self, new_page_id: int) -> Tuple[ScalarKey, "BTreeNode"]:
        """
        Splits this node into two nodes under Lehman-Yao B-link invariants
        and returns (promoted_key, new_sibling_node).
        """
        mid = len(self.keys) // 2
        sibling = BTreeNode(
            page_id=new_page_id,
            is_leaf=self.is_leaf,
            prev_leaf=self.page_id if self.is_leaf else None,
            high_key=self.high_key,
            right_link=self.right_link,
        )

        if self.is_leaf:
            promoted_key = self._split_leaf(sibling, mid)
        else:
            promoted_key = self._split_interior(sibling, mid)

        return promoted_key, sibling
