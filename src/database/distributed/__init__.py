#!/usr/bin/env python3
"""
Distributed Coordination, Consensus, 2PC, Saga, Sharding, and Anti-Entropy Subsystem.
Exports VectorClock, VersionedValue, PhiAccrualDetector, GossipNode,
QuorumCoordinator, HintedHandoffManager, MerkleTree, PNCounter, ORSet,
AntiEntropySynchronizer, Raft Consensus, Distributed 2PC, Saga Orchestrator,
and Consistent Hashing Sharding (ConsistentHashRing, ShardManager).
"""

from .anti_entropy import AntiEntropySynchronizer
from .crdt import ORSet, PNCounter
from .gossip import GossipNode, NodeState, NodeStatus
from .hinted_handoff import Hint, HintedHandoffManager
from .merkle_tree import MerkleNode, MerkleTree
from .phi_accrual import PhiAccrualDetector
from .quorum import QuorumCoordinator, QuorumReadError, QuorumReplica, QuorumWriteError
from .raft import (
    AppendEntriesArgs,
    AppendEntriesReply,
    LogEntry,
    RaftCluster,
    RaftNode,
    RaftRole,
    RequestVoteArgs,
    RequestVoteReply,
)
from .saga import SagaOrchestrator, SagaStatus, SagaStep, build_paper_pipeline_saga
from .sharding import ConsistentHashRing, ShardManager
from .two_pc import (
    DistributedDeadlockDetector,
    GlobalDecision,
    TwoPCCoordinator,
    TwoPCParticipant,
    TwoPCState,
    TxRecord,
    VoteType,
)
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
    # Raft Consensus & SMR
    "RaftRole",
    "LogEntry",
    "RequestVoteArgs",
    "RequestVoteReply",
    "AppendEntriesArgs",
    "AppendEntriesReply",
    "RaftNode",
    "RaftCluster",
    # Distributed 2PC & Deadlock Detection
    "TwoPCState",
    "VoteType",
    "GlobalDecision",
    "TxRecord",
    "TwoPCParticipant",
    "TwoPCCoordinator",
    "DistributedDeadlockDetector",
    # Saga Orchestration & Compensation
    "SagaStatus",
    "SagaStep",
    "SagaOrchestrator",
    "build_paper_pipeline_saga",
    # Consistent Hashing & Sharding
    "ConsistentHashRing",
    "ShardManager",
]
