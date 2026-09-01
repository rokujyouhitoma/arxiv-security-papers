#!/usr/bin/env python3
"""
Raft Cluster Orchestrator and State Machine Manager.
Manages multi-node Raft clusters, peer interconnection, and client command execution.
"""

from typing import Any, Dict, List, Optional

from .node import RaftNode
from .types import RaftRole


class RaftCluster:
    """
    Manages a cluster of interconnected Raft consensus nodes.
    """

    def __init__(self, node_ids: Optional[List[str]] = None) -> None:
        self.nodes: Dict[str, RaftNode] = {}
        if node_ids:
            for nid in node_ids:
                self.add_node(nid)

    def add_node(self, node_id: str) -> RaftNode:
        """Adds and interconnects a new Raft node in the cluster."""
        new_node = RaftNode(node_id)
        for existing in self.nodes.values():
            existing.add_peer(new_node)
            new_node.add_peer(existing)
        self.nodes[node_id] = new_node
        return new_node

    def get_leader(self) -> Optional[RaftNode]:
        """Returns the current online cluster leader if one exists."""
        for node in self.nodes.values():
            if node.is_online and node.role == RaftRole.LEADER:
                return node
        return None

    def _elect_specific(self, candidate_id: str) -> Optional[RaftNode]:
        candidate = self.nodes.get(candidate_id)
        if candidate and candidate.start_election():
            return candidate
        return None

    def _elect_any(self) -> Optional[RaftNode]:
        for node in self.nodes.values():
            if node.is_online and node.start_election():
                return node
        return None

    def elect_leader(self, candidate_id: Optional[str] = None) -> Optional[RaftNode]:
        """Triggers leader election on the specified candidate or first online node."""
        if candidate_id:
            res = self._elect_specific(candidate_id)
            if res is not None:
                return res
        return self._elect_any()

    def execute(self, command: Any) -> bool:
        """
        Executes a client command through the active cluster leader.
        Returns True if committed across the majority of nodes.
        """
        leader = self.get_leader()
        if leader is None:
            leader = self.elect_leader()
        if leader is None:
            return False

        return leader.propose(command)
