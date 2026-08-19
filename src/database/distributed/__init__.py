#!/usr/bin/env python3
"""
Distributed Coordination and Consensus Subsystem.
Exports VectorClock, VersionedValue, PhiAccrualDetector, GossipNode,
QuorumCoordinator, and HintedHandoffManager.
"""

from .gossip import GossipNode, NodeState, NodeStatus
from .hinted_handoff import Hint, HintedHandoffManager
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
]
