#!/usr/bin/env python3
"""
Distributed Coordination, Consensus, and Anti-Entropy Subsystem.
Exports VectorClock, VersionedValue, PhiAccrualDetector, GossipNode,
QuorumCoordinator, HintedHandoffManager, MerkleTree, PNCounter, ORSet,
and AntiEntropySynchronizer.
"""

from .anti_entropy import AntiEntropySynchronizer
from .crdt import ORSet, PNCounter
from .gossip import GossipNode, NodeState, NodeStatus
from .hinted_handoff import Hint, HintedHandoffManager
from .merkle_tree import MerkleNode, MerkleTree
from .phi_accrual import PhiAccrualDetector
from .quorum import QuorumCoordinator, QuorumReadError, QuorumReplica, QuorumWriteError
from .vector_clock import VectorClock
from .version_vector import (
    ConflictResolutionStrategy,
    VersionedValue,
    prune_dominated_versions,
    resolve_conflict,
)

__all__ = [
    # Vector Clock and Version Vector
    "VectorClock",
    "VersionedValue",
    "ConflictResolutionStrategy",
    "resolve_conflict",
    "prune_dominated_versions",
    # Failure Detection & Gossip
    "PhiAccrualDetector",
    "NodeStatus",
    "NodeState",
    "GossipNode",
    # Quorum Replication & Hinted Handoff
    "QuorumReplica",
    "QuorumCoordinator",
    "QuorumWriteError",
    "QuorumReadError",
    "Hint",
    "HintedHandoffManager",
    # Merkle Tree & CRDTs & Anti-Entropy
    "MerkleNode",
    "MerkleTree",
    "PNCounter",
    "ORSet",
    "AntiEntropySynchronizer",
]
