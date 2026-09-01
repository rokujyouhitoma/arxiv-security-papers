#!/usr/bin/env python3
"""
Merkle Tree (Hierarchical Cryptographic Hash Tree) Engine.
Enables O(log N) difference detection and minimal bandwidth anti-entropy synchronization.
"""

import hashlib
from typing import Dict, List, Optional, Set


class MerkleNode:
    """A single node within a cryptographic Merkle Tree."""

    def __init__(
        self,
        hash_val: str,
        left: Optional["MerkleNode"] = None,
        right: Optional["MerkleNode"] = None,
        key: Optional[str] = None,
        keys_in_subtree: Optional[Set[str]] = None,
    ) -> None:
        self.hash_val = hash_val
        self.left = left
        self.right = right
        self.key = key
        self.keys_in_subtree = keys_in_subtree or set()

    @property
    def is_leaf(self) -> bool:
        """Returns True if this node is a leaf node."""
        return self.left is None and self.right is None


def _hash_str(data: str) -> str:
    """Computes SHA-256 hex digest of a string."""
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


class MerkleTree:
    """
    Merkle Tree constructed from key-value pairs for rapid range difference detection.
    """

    def __init__(self, data: Optional[Dict[str, str]] = None) -> None:
        self.data: Dict[str, str] = data or {}
        self.root: Optional[MerkleNode] = self._build_tree(self.data)

    def _build_tree(self, data: Dict[str, str]) -> Optional[MerkleNode]:
        """Constructs balanced Merkle Tree from dictionary items."""
        if not data:
            return MerkleNode(hash_val=_hash_str(""), keys_in_subtree=set())

        sorted_keys = sorted(data.keys())
        leaves: List[MerkleNode] = []

        for k in sorted_keys:
            val = data[k]
            leaf_hash = _hash_str(f"{k}:{val}")
            leaves.append(
                MerkleNode(
                    hash_val=leaf_hash,
                    key=k,
                    keys_in_subtree={k},
                )
            )

        return self._build_sub_tree(leaves)

    def _build_sub_tree(self, nodes: List[MerkleNode]) -> MerkleNode:
        """Recursively pairs nodes to construct the tree root."""
        if len(nodes) == 1:
            return nodes[0]

        parent_layer: List[MerkleNode] = []
        for i in range(0, len(nodes), 2):
            left = nodes[i]
            if i + 1 < len(nodes):
                right: Optional[MerkleNode] = nodes[i + 1]
                assert right is not None
                combined_hash = _hash_str(left.hash_val + right.hash_val)
                combined_keys = left.keys_in_subtree | right.keys_in_subtree
            else:
                right = None
                combined_hash = _hash_str(left.hash_val + left.hash_val)
                combined_keys = set(left.keys_in_subtree)

            parent = MerkleNode(
                hash_val=combined_hash,
                left=left,
                right=right,
                keys_in_subtree=combined_keys,
            )
            parent_layer.append(parent)

        return self._build_sub_tree(parent_layer)

    @property
    def root_hash(self) -> str:
        """Returns the root hash of the Merkle Tree."""
        if self.root is None:
            return _hash_str("")
        return self.root.hash_val

    def find_diff_keys(self, other: "MerkleTree") -> List[str]:
        """
        Compares this Merkle Tree with another and returns all differing keys in O(log N).
        """
        diffs: Set[str] = set()
        self._diff_recursive(self.root, other.root, diffs)
        return sorted(diffs)

    def _handle_null_nodes(
        self, n1: Optional[MerkleNode], n2: Optional[MerkleNode], diffs: Set[str]
    ) -> bool:
        if n1 is None and n2 is None:
            return True
        if n1 is None:
            diffs.update(n2.keys_in_subtree)  # type: ignore[union-attr]
            return True
        if n2 is None:
            diffs.update(n1.keys_in_subtree)
            return True
        return False

    def _diff_recursive(
        self,
        n1: Optional[MerkleNode],
        n2: Optional[MerkleNode],
        diffs: Set[str],
    ) -> None:
        """Recursively traverses mismatching branches."""
        if self._handle_null_nodes(n1, n2, diffs):
            return
        if n1.hash_val == n2.hash_val:  # type: ignore[union-attr]
            return
        if n1.is_leaf or n2.is_leaf:  # type: ignore[union-attr]
            diffs.update(n1.keys_in_subtree | n2.keys_in_subtree)  # type: ignore[union-attr]
            return
        self._diff_recursive(n1.left, n2.left, diffs)  # type: ignore[union-attr]
        self._diff_recursive(n1.right, n2.right, diffs)  # type: ignore[union-attr]
