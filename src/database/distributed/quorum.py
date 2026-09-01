#!/usr/bin/env python3
"""
Quorum Replication and Read Repair Engine.
Enforces Strict Quorum (W + R > N) for strong consistency in leaderless distributed topologies
and performs automatic background Read Repair for stale replicas.
"""

import time
from typing import Any, Dict, List, Optional

from .vector_clock import VectorClock
from .version_vector import ConflictResolutionStrategy, VersionedValue, resolve_conflict


class QuorumWriteError(Exception):
    """Raised when write quorum W cannot be achieved."""

    pass


class QuorumReadError(Exception):
    """Raised when read quorum R cannot be achieved."""

    pass


class QuorumReplica:
    """
    In-memory or local storage representation of a single replica node.
    """

    def __init__(self, node_id: str) -> None:
        self.node_id = node_id
        self._store: Dict[str, VersionedValue] = {}
        self.is_online: bool = True

    def get(self, key: str) -> Optional[VersionedValue]:
        """Retrieves key version if node is online."""
        if not self.is_online:
            return None
        return self._store.get(key)

    def put(self, key: str, val: VersionedValue) -> bool:
        """Stores key version if node is online."""
        if not self.is_online:
            return False
        self._store[key] = val
        return True


class QuorumCoordinator:
    """
    Coordinates distributed Quorum writes and reads across N replicas.
    """

    def __init__(
        self,
        replicas: List[QuorumReplica],
        w_quorum: int = 2,
        r_quorum: int = 2,
        coordinator_id: str = "coord",
    ) -> None:
        self.replicas = replicas
        self.w_quorum = w_quorum
        self.r_quorum = r_quorum
        self.coordinator_id = coordinator_id
        self.clock = VectorClock()

    @property
    def n_replicas(self) -> int:
        """Total replica count N."""
        return len(self.replicas)

    def is_strict_quorum(self) -> bool:
        """Checks if W + R > N (Pigeonhole principle guarantees strong consistency)."""
        return (self.w_quorum + self.r_quorum) > self.n_replicas

    def write(
        self,
        key: str,
        value: Any,
        client_clock: Optional[VectorClock] = None,
    ) -> VersionedValue:
        """
        Executes a distributed write with write quorum W.
        """
        base_clock = client_clock or self.clock
        new_clock = base_clock.increment(self.coordinator_id)
        self.clock = new_clock

        versioned_val = VersionedValue(
            value=value,
            clock=new_clock,
            timestamp=time.time(),
        )

        success_count = 0
        for replica in self.replicas:
            if replica.put(key, versioned_val):
                success_count += 1

        if success_count < self.w_quorum:
            raise QuorumWriteError(
                f"Write quorum failed: required {self.w_quorum}, succeeded {success_count}/{self.n_replicas}"
            )

        return versioned_val

    def _collect_responses(
        self, key: str
    ) -> List[tuple[QuorumReplica, Optional[VersionedValue]]]:
        """Collects read responses from all online replicas."""
        responses: List[tuple[QuorumReplica, Optional[VersionedValue]]] = []
        for replica in self.replicas:
            if replica.is_online:
                responses.append((replica, replica.get(key)))

        if len(responses) < self.r_quorum:
            raise QuorumReadError(
                f"Read quorum failed: required {self.r_quorum}, succeeded {len(responses)}/{self.n_replicas}"
            )
        return responses

    def _apply_read_repair(
        self,
        key: str,
        latest_version: VersionedValue,
        responses: List[tuple[QuorumReplica, Optional[VersionedValue]]],
    ) -> None:
        """Repairs stale or missing replicas with the latest version."""
        for replica, val in responses:
            if val is None or val.clock.happens_before(latest_version.clock):
                replica.put(key, latest_version)

    def _resolve_valid_versions(
        self,
        responses: List[tuple["QuorumReplica", "Optional[VersionedValue]"]],
    ) -> Optional["VersionedValue"]:
        valid_versions = [v for _, v in responses if v is not None]
        if not valid_versions:
            return None
        resolved = resolve_conflict(
            valid_versions, strategy=ConflictResolutionStrategy.LWW
        )
        return resolved[0] if resolved else None

    def read(
        self,
        key: str,
        enable_read_repair: bool = True,
    ) -> Optional[VersionedValue]:
        """
        Executes a distributed read with read quorum R and performs Read Repair.
        """
        responses = self._collect_responses(key)
        latest_version = self._resolve_valid_versions(responses)
        if latest_version is None:
            return None
        if enable_read_repair:
            self._apply_read_repair(key, latest_version, responses)
        return latest_version
