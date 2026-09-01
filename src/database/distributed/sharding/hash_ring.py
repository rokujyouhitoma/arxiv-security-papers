#!/usr/bin/env python3
"""
Consistent Hash Ring with Virtual Nodes (vnodes).
Maps keys to nodes using consistent hashing with O(log M) binary search resolution.
"""

import bisect
import hashlib
from typing import Dict, List, Optional, Set


def _hash_key(key: str) -> int:
    """Computes a 64-bit integer hash from a key string using SHA-256."""
    digest = hashlib.sha256(key.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], byteorder="big", signed=False)


class ConsistentHashRing:
    """
    A token ring implementing consistent hashing with virtual nodes.
    """

    def __init__(self, vnodes: int = 128) -> None:
        self.vnodes = max(1, vnodes)
        self.ring: Dict[int, str] = {}
        self.sorted_tokens: List[int] = []
        self.nodes: Set[str] = set()

    def add_node(self, node_id: str) -> None:
        """Adds a physical node and its virtual nodes to the token ring."""
        if node_id in self.nodes:
            return
        self.nodes.add(node_id)
        for i in range(self.vnodes):
            vnode_key = f"{node_id}#vnode_{i}"
            token = _hash_key(vnode_key)
            self.ring[token] = node_id
            bisect.insort(self.sorted_tokens, token)

    def remove_node(self, node_id: str) -> None:
        """Removes a physical node and all its virtual nodes from the ring."""
        if node_id not in self.nodes:
            return
        self.nodes.remove(node_id)
        for i in range(self.vnodes):
            vnode_key = f"{node_id}#vnode_{i}"
            token = _hash_key(vnode_key)
            self.ring.pop(token, None)
        self.sorted_tokens = sorted(self.ring.keys())

    def get_node(self, key: str) -> Optional[str]:
        """
        Resolves the primary node responsible for the given key in O(log M) time.
        """
        if not self.sorted_tokens:
            return None
        h = _hash_key(key)
        idx = bisect.bisect_right(self.sorted_tokens, h)
        if idx >= len(self.sorted_tokens):
            idx = 0
        token = self.sorted_tokens[idx]
        return self.ring[token]

    def _collect_distinct_nodes(self, start_idx: int, target_count: int) -> List[str]:
        preference_nodes: List[str] = []
        seen_nodes: Set[str] = set()
        total_tokens = len(self.sorted_tokens)
        for offset in range(total_tokens):
            idx = (start_idx + offset) % total_tokens
            node_id = self.ring[self.sorted_tokens[idx]]
            if node_id not in seen_nodes:
                seen_nodes.add(node_id)
                preference_nodes.append(node_id)
                if len(preference_nodes) == target_count:
                    break
        return preference_nodes

    def get_preference_list(self, key: str, n: int) -> List[str]:
        """
        Returns a list of up to N distinct physical nodes responsible for replicating the key.
        """
        if not self.sorted_tokens:
            return []
        if n <= 0:
            return []
        target_count = min(n, len(self.nodes))
        start_idx = bisect.bisect_right(self.sorted_tokens, _hash_key(key))
        return self._collect_distinct_nodes(start_idx, target_count)
