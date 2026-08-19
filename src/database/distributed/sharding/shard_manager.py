#!/usr/bin/env python3
"""
Distributed Shard Manager and Partition Router.
Routes CRUD operations to responsible shard nodes using Consistent Hashing.
"""

from typing import Any, Dict, List, Optional

from .hash_ring import ConsistentHashRing


class ShardManager:
    """
    Manages partition shards and routes reads/writes across cluster nodes.
    """

    def __init__(
        self,
        node_ids: Optional[List[str]] = None,
        replication_factor: int = 3,
        vnodes: int = 128,
    ) -> None:
        self.ring = ConsistentHashRing(vnodes=vnodes)
        self.replication_factor = replication_factor
        # node_id -> local key-value dictionary
        self.shards: Dict[str, Dict[str, Any]] = {}

        if node_ids:
            for nid in node_ids:
                self.add_node(nid)

    def add_node(self, node_id: str) -> None:
        """Registers a new shard node in the cluster."""
        self.ring.add_node(node_id)
        if node_id not in self.shards:
            self.shards[node_id] = {}

    def remove_node(self, node_id: str) -> None:
        """Removes a shard node from the cluster."""
        self.ring.remove_node(node_id)
        self.shards.pop(node_id, None)

    def put(self, key: str, value: Any) -> List[str]:
        """
        Stores key-value pair across all replica nodes in the preference list.
        Returns list of nodes where the write was applied.
        """
        replica_nodes = self.ring.get_preference_list(key, self.replication_factor)
        written_nodes: List[str] = []

        for node_id in replica_nodes:
            if node_id in self.shards:
                self.shards[node_id][key] = value
                written_nodes.append(node_id)

        return written_nodes

    def get(self, key: str) -> Optional[Any]:
        """
        Retrieves the value for the key from the primary or fallback replicas.
        """
        replica_nodes = self.ring.get_preference_list(key, self.replication_factor)
        for node_id in replica_nodes:
            shard = self.shards.get(node_id)
            if shard is not None and key in shard:
                return shard[key]
        return None

    def rebalance(self, new_node_id: str) -> int:
        """
        Adds a new node and rebalances keys from existing shards to the new node.
        Returns the number of keys migrated to the new node.
        """
        # Collect all existing unique keys and values before addition
        all_data: Dict[str, Any] = {}
        for shard in self.shards.values():
            all_data.update(shard)

        # Add node to ring and storage
        self.add_node(new_node_id)

        migrated_count = 0
        for key, val in all_data.items():
            new_preference = self.ring.get_preference_list(key, self.replication_factor)
            if new_node_id in new_preference:
                self.shards[new_node_id][key] = val
                migrated_count += 1

        return migrated_count
