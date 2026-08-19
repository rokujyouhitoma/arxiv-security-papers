#!/usr/bin/env python3
"""
B+Tree Node Implementation for 4096-Byte Paged Database Storage.
Supports Interior and Leaf node serialization and splitting.
"""

import json
from typing import Any, Dict, List, Optional, Tuple, Union

ScalarKey = Union[int, float, str]


def compare_keys(k1: ScalarKey, k2: ScalarKey) -> int:
    """Safely compares two scalar keys of potentially different types (-1, 0, 1)."""
    if isinstance(k1, (int, float)) and isinstance(k2, (int, float)):
        return 1 if k1 > k2 else (-1 if k1 < k2 else 0)
    str_k1, str_k2 = str(k1), str(k2)
    return 1 if str_k1 > str_k2 else (-1 if str_k1 < str_k2 else 0)


class BTreeNode:
    """
    Represents a single B+Tree node stored inside a 4096-byte database page.
    """

    MAX_KEYS = 32  # Balanced fanout for 4KB page safety

    def __init__(
        self,
        page_id: int,
        is_leaf: bool = True,
        next_leaf: Optional[int] = None,
        prev_leaf: Optional[int] = None,
    ) -> None:
        self.page_id = page_id
        self.is_leaf = is_leaf
        self.keys: List[ScalarKey] = []
        # For leaf nodes: values are lists of integer row_ids associated with each key
        self.values: List[List[int]] = []
        # For interior nodes: children are page_ids (len(children) == len(keys) + 1)
        self.children: List[int] = []
        self.next_leaf = next_leaf
        self.prev_leaf = prev_leaf

    def is_full(self) -> bool:
        return len(self.keys) >= self.MAX_KEYS

    def serialize(self) -> bytes:
        """Serializes node structure to 4096-byte page payload."""
        data: Dict[str, Any] = {
            "page_id": self.page_id,
            "is_leaf": self.is_leaf,
            "keys": self.keys,
            "values": self.values if self.is_leaf else [],
            "children": self.children if not self.is_leaf else [],
            "next_leaf": self.next_leaf,
            "prev_leaf": self.prev_leaf,
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
            next_leaf=data.get("next_leaf"),
            prev_leaf=data.get("prev_leaf"),
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

    def split(self, new_page_id: int) -> Tuple[ScalarKey, "BTreeNode"]:
        """
        Splits this node into two nodes and returns (promoted_key, new_sibling_node).
        """
        mid = len(self.keys) // 2
        sibling = BTreeNode(
            page_id=new_page_id,
            is_leaf=self.is_leaf,
            next_leaf=self.next_leaf,
            prev_leaf=self.page_id if self.is_leaf else None,
        )

        if self.is_leaf:
            promoted_key = self.keys[mid]
            sibling.keys = self.keys[mid:]
            sibling.values = self.values[mid:]
            self.keys = self.keys[:mid]
            self.values = self.values[:mid]
            self.next_leaf = new_page_id
        else:
            promoted_key = self.keys[mid]
            sibling.keys = self.keys[mid + 1 :]
            sibling.children = self.children[mid + 1 :]
            self.keys = self.keys[:mid]
            self.children = self.children[: mid + 1]

        return promoted_key, sibling
