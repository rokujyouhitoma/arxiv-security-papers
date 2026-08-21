"""Consistent Hashing Router for distributed spider domain partitioning."""

from __future__ import annotations

import bisect
import hashlib
from typing import Dict, List, Optional


class ConsistentHashRouter:
    """Routes domain requests to worker nodes using Consistent Hashing with virtual nodes."""

    def __init__(
        self, nodes: Optional[List[str]] = None, virtual_nodes: int = 100
    ) -> None:
        self.virtual_nodes: int = virtual_nodes
        self._ring: List[int] = []
        self._ring_map: Dict[int, str] = {}
        self._nodes: set[str] = set()

        if nodes:
            for node in nodes:
                self.add_node(node)

    def add_node(self, node: str) -> None:
        """Adds a worker node to the hash ring with virtual nodes."""
        self._nodes.add(node)
        for i in range(self.virtual_nodes):
            vkey = f"{node}#vn{i}"
            vhash = self._hash(vkey)
            self._ring.append(vhash)
            self._ring_map[vhash] = node
        self._ring.sort()

    def remove_node(self, node: str) -> None:
        """Removes a worker node from the hash ring."""
        if node not in self._nodes:
            return
        self._nodes.remove(node)
        for i in range(self.virtual_nodes):
            vkey = f"{node}#vn{i}"
            vhash = self._hash(vkey)
            if vhash in self._ring_map:
                del self._ring_map[vhash]
        self._ring = sorted(self._ring_map.keys())

    def get_node(self, domain: str) -> Optional[str]:
        """Maps a domain to the closest worker node in the ring."""
        if not self._ring:
            return None
        val = self._hash(domain.lower())
        idx = bisect.bisect_right(self._ring, val)
        if idx == len(self._ring):
            idx = 0
        return self._ring_map[self._ring[idx]]

    def _hash(self, key: str) -> int:
        return int(hashlib.md5(key.encode("utf-8")).hexdigest(), 16)
