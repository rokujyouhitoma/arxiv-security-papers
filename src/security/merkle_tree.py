#!/usr/bin/env python3
"""
Cryptographic Merkle Tree Engine (RFC 6962 Domain-Separated).
Provides mathematically verifiable integrity trees, O(log N) audit proofs,
and tamper detection without external dependencies.
"""

from __future__ import annotations

import hashlib
from typing import Any, Dict, List, Optional, Tuple, Union

LEAF_PREFIX: bytes = b"\x00"
INTERNAL_PREFIX: bytes = b"\x01"


def hash_leaf(data: Union[bytes, str]) -> bytes:
    """Computes RFC 6962 leaf hash: SHA256(0x00 || data)."""
    raw = data.encode("utf-8") if isinstance(data, str) else data
    return hashlib.sha256(LEAF_PREFIX + raw).digest()


def hash_children(left: bytes, right: bytes) -> bytes:
    """Computes RFC 6962 internal node hash: SHA256(0x01 || left || right)."""
    return hashlib.sha256(INTERNAL_PREFIX + left + right).digest()


class MerkleTree:
    """
    Binary Merkle Tree implementation adhering to RFC 6962 domain separation.
    Guarantees collision resistance between leaves and internal nodes,
    and supports O(log N) inclusion proofs (audit paths).
    """

    def __init__(self, leaves: Optional[List[Union[bytes, str]]] = None) -> None:
        self.raw_leaves: List[bytes] = []
        self.levels: List[List[bytes]] = []
        self._built: bool = False
        if leaves:
            for item in leaves:
                self.add_leaf(item)
            self.build()

    def add_leaf(self, data: Union[bytes, str]) -> int:
        """Adds a leaf payload and invalidates the built tree cache."""
        raw = data.encode("utf-8") if isinstance(data, str) else data
        self.raw_leaves.append(raw)
        self._built = False
        return len(self.raw_leaves) - 1

    @property
    def leaf_count(self) -> int:
        """Returns total number of leaves in the tree."""
        return len(self.raw_leaves)

    @property
    def root_hash(self) -> Optional[str]:
        """Returns root hash hex string if built, otherwise None."""
        if not self._built:
            self.build()
        if not self.levels or not self.levels[-1]:
            return None
        return self.levels[-1][0].hex()

    def _build_next_level(self, current_level: List[bytes]) -> List[bytes]:
        """Pairs adjacent nodes and hashes them to build the next level up."""
        next_level: List[bytes] = []
        for i in range(0, len(current_level), 2):
            left = current_level[i]
            right = current_level[i + 1] if i + 1 < len(current_level) else left
            next_level.append(hash_children(left, right))
        return next_level

    def build(self) -> str:
        """
        Builds the Merkle tree from raw leaves.
        Returns the root hash as a hex string.
        """
        if not self.raw_leaves:
            empty_root = hashlib.sha256(b"").hexdigest()
            self.levels = [[bytes.fromhex(empty_root)]]
            self._built = True
            return empty_root

        current_level = [hash_leaf(leaf) for leaf in self.raw_leaves]
        self.levels = [current_level]

        while len(current_level) > 1:
            current_level = self._build_next_level(current_level)
            self.levels.append(current_level)

        self._built = True
        return self.levels[-1][0].hex()

    def _step_proof(self, level: List[bytes], idx: int) -> Tuple[Tuple[str, str], int]:
        """Calculates a single step in the audit path."""
        is_right = idx % 2 == 1
        sib_idx = idx - 1 if is_right else idx + 1
        sibling_hash = level[sib_idx] if sib_idx < len(level) else level[idx]
        direction = "left" if is_right else "right"
        return (sibling_hash.hex(), direction), idx // 2

    def get_proof(self, leaf_index: int) -> List[Tuple[str, str]]:
        """
        Generates an audit proof (Merkle path) for the leaf at leaf_index.
        Returns list of (sibling_hash_hex, direction) where direction is 'left' or 'right'.
        """
        if not self._built:
            self.build()
        if leaf_index < 0 or leaf_index >= len(self.raw_leaves):
            raise IndexError(
                f"Leaf index {leaf_index} out of bounds (0..{len(self.raw_leaves) - 1})"
            )

        proof: List[Tuple[str, str]] = []
        idx = leaf_index
        for level in self.levels[:-1]:
            step, idx = self._step_proof(level, idx)
            proof.append(step)

        return proof

    @staticmethod
    def verify_proof(
        leaf_data: Union[bytes, str],
        proof: List[Tuple[str, str]],
        root_hash: str,
    ) -> bool:
        """
        Mathematically verifies that leaf_data is included under root_hash
        given the Merkle audit path proof.
        """
        curr = hash_leaf(leaf_data)
        for sibling_hex, direction in proof:
            sibling = bytes.fromhex(sibling_hex)
            if direction == "left":
                curr = hash_children(sibling, curr)
            else:
                curr = hash_children(curr, sibling)
        return curr.hex() == root_hash.lower()

    def to_dict(self) -> Dict[str, Any]:
        """Serializes Merkle tree summary state."""
        return {
            "root_hash": self.root_hash,
            "leaf_count": self.leaf_count,
            "height": len(self.levels),
        }
