#!/usr/bin/env python3
"""
Anti-Entropy Background Synchronizer.
Utilizes Merkle Tree difference detection to perform minimal-bandwidth
bidirectional data reconciliation across distributed replicas.
"""

from typing import Dict, Optional

from .merkle_tree import MerkleTree
from .quorum import QuorumReplica
from .version_vector import ConflictResolutionStrategy, VersionedValue, resolve_conflict


class AntiEntropySynchronizer:
    """
    Synchronizes two replicas by constructing and comparing Merkle Trees.
    """

    @staticmethod
    def _build_replica_tree(replica: QuorumReplica) -> MerkleTree:
        """Constructs a Merkle Tree from the replica's key-value store."""
        data_map: Dict[str, str] = {}
        for key, versioned_val in replica._store.items():
            data_map[key] = f"{versioned_val.value}:{versioned_val.clock.to_json()}"
        return MerkleTree(data_map)

    @staticmethod
    def _needs_update(
        val: "Optional[VersionedValue]", latest: "VersionedValue"
    ) -> bool:
        if val is None:
            return True
        return val.clock.happens_before(latest.clock)

    def _update_replica_if_needed(
        self,
        replica: QuorumReplica,
        key: str,
        val: Optional[VersionedValue],
        latest: VersionedValue,
    ) -> int:
        if self._needs_update(val, latest):
            replica.put(key, latest)
            return 1
        return 0

    def _sync_key(
        self,
        key: str,
        replica_a: QuorumReplica,
        replica_b: QuorumReplica,
    ) -> int:
        """Synchronizes a single key across two replicas."""
        val_a = replica_a.get(key)
        val_b = replica_b.get(key)
        versions = [v for v in (val_a, val_b) if v is not None]
        if not versions:
            return 0
        resolved = resolve_conflict(versions, strategy=ConflictResolutionStrategy.LWW)
        if not resolved:
            return 0
        latest = resolved[0]
        cnt_a = self._update_replica_if_needed(replica_a, key, val_a, latest)
        cnt_b = self._update_replica_if_needed(replica_b, key, val_b, latest)
        return cnt_a + cnt_b

    def synchronize(
        self,
        replica_a: QuorumReplica,
        replica_b: QuorumReplica,
    ) -> int:
        """
        Detects differences between replica A and B via Merkle Tree comparison
        and reconciles outdated records. Returns number of reconciled keys.
        """
        if not replica_a.is_online or not replica_b.is_online:
            return 0

        tree_a = self._build_replica_tree(replica_a)
        tree_b = self._build_replica_tree(replica_b)

        if tree_a.root_hash == tree_b.root_hash:
            return 0

        diff_keys = tree_a.find_diff_keys(tree_b)
        reconciled_count = 0

        for key in diff_keys:
            reconciled_count += self._sync_key(key, replica_a, replica_b)

        return reconciled_count
