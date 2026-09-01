#!/usr/bin/env python3
"""
Gossip Protocol and Peer Membership Management.
Propagates cluster states, node generations, and heartbeat sequences
with integrated Phi Accrual failure detection.
"""

import enum
import time
from typing import Any, Dict, Optional


from .phi_accrual import PhiAccrualDetector


class NodeStatus(enum.Enum):
    """Lifecycle states of a cluster member node."""

    ALIVE = "ALIVE"
    SUSPECT = "SUSPECT"
    DEAD = "DEAD"


class NodeState:
    """Represents the known state and failure detector of a member node."""

    def __init__(
        self,
        node_id: str,
        generation: int = 1,
        heartbeat_seq: int = 0,
        status: NodeStatus = NodeStatus.ALIVE,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.node_id = node_id
        self.generation = generation
        self.heartbeat_seq = heartbeat_seq
        self.status = status
        self.metadata = metadata or {}
        self.detector = PhiAccrualDetector()

    def to_dict(self) -> Dict[str, Any]:
        """Serializes node state into dictionary."""
        return {
            "node_id": self.node_id,
            "generation": self.generation,
            "heartbeat_seq": self.heartbeat_seq,
            "status": self.status.value,
            "metadata": self.metadata,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "NodeState":
        """Deserializes node state from dictionary."""
        return cls(
            node_id=data["node_id"],
            generation=int(data.get("generation", 1)),
            heartbeat_seq=int(data.get("heartbeat_seq", 0)),
            status=NodeStatus(data.get("status", "ALIVE")),
            metadata=data.get("metadata", {}),
        )


class GossipNode:
    """
    A participant node in the Gossip network managing cluster membership and heartbeats.
    """

    def __init__(
        self,
        node_id: str,
        generation: Optional[int] = None,
    ) -> None:
        self.node_id = node_id
        self.generation = generation if generation is not None else int(time.time())
        self.heartbeat_seq: int = 0
        self.members: Dict[str, NodeState] = {}

        # Register self
        self_state = NodeState(
            node_id=self.node_id,
            generation=self.generation,
            heartbeat_seq=self.heartbeat_seq,
            status=NodeStatus.ALIVE,
        )
        self.members[self.node_id] = self_state

    def heartbeat(self) -> None:
        """Increments self heartbeat sequence."""
        self.heartbeat_seq += 1
        self.members[self.node_id].heartbeat_seq = self.heartbeat_seq

    def add_peer(self, peer_id: str, generation: int = 1) -> None:
        """Explicitly registers a new peer in membership table."""
        if peer_id not in self.members:
            self.members[peer_id] = NodeState(
                node_id=peer_id,
                generation=generation,
                heartbeat_seq=0,
                status=NodeStatus.ALIVE,
            )

    def prepare_gossip_message(self) -> Dict[str, Any]:
        """Prepares full membership digest for Gossip propagation."""
        return {
            "sender_id": self.node_id,
            "members": [m.to_dict() for m in self.members.values()],
        }

    def _merge_new_peer(
        self, peer_id: str, in_gen: int, in_seq: int, in_meta: dict, now: float
    ) -> None:
        new_state = NodeState(
            node_id=peer_id,
            generation=in_gen,
            heartbeat_seq=in_seq,
            status=NodeStatus.ALIVE,
            metadata=in_meta,
        )
        new_state.detector.heartbeat(now)
        self.members[peer_id] = new_state

    def _update_existing_peer(
        self, peer_id: str, in_gen: int, in_seq: int, in_meta: dict, now: float
    ) -> None:
        existing = self.members[peer_id]
        newer = in_gen > existing.generation or (
            in_gen == existing.generation and in_seq > existing.heartbeat_seq
        )
        if newer:
            existing.generation = in_gen
            existing.heartbeat_seq = in_seq
            existing.metadata.update(in_meta)
            existing.status = NodeStatus.ALIVE
            existing.detector.heartbeat(now)

    def process_gossip_message(
        self,
        payload: Dict[str, Any],
        timestamp: Optional[float] = None,
    ) -> None:
        """
        Merges incoming gossip payload into local membership view.
        Updates PhiAccrual detector on receiving newer heartbeats.
        """
        now = timestamp if timestamp is not None else time.time()
        for item in payload.get("members", []):
            peer_id = item.get("node_id")
            if not peer_id:
                continue
            in_gen = int(item.get("generation", 1))
            in_seq = int(item.get("heartbeat_seq", 0))
            in_meta = item.get("metadata", {})
            if peer_id not in self.members:
                self._merge_new_peer(peer_id, in_gen, in_seq, in_meta, now)
            else:
                self._update_existing_peer(peer_id, in_gen, in_seq, in_meta, now)

    @staticmethod
    def _phi_to_status(phi_val: float) -> "NodeStatus":
        if phi_val >= 12.0:
            return NodeStatus.DEAD
        if phi_val >= 8.0:
            return NodeStatus.SUSPECT
        return NodeStatus.ALIVE

    def check_failure_states(
        self,
        current_time: Optional[float] = None,
    ) -> Dict[str, NodeStatus]:
        """
        Evaluates Phi Accrual for all peers and transitions states:
        Phi >= 12 -> DEAD, Phi >= 8 -> SUSPECT, Phi < 8 -> ALIVE.
        """
        now = current_time if current_time is not None else time.time()
        states_summary: Dict[str, NodeStatus] = {}
        for peer_id, state in self.members.items():
            if peer_id == self.node_id:
                states_summary[peer_id] = NodeStatus.ALIVE
                continue
            state.status = self._phi_to_status(state.detector.phi(now))
            states_summary[peer_id] = state.status
        return states_summary
