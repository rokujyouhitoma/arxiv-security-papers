#!/usr/bin/env python3
"""
Unit and Integration Tests for Raft Distributed Consensus and SMR Engine.
Verifies Leader Election, Log Replication, Quorum Commit, Minority Fencing,
and Dynamic Re-election upon Leader Crash.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from database.distributed.raft import RaftCluster, RaftNode, RaftRole


class TestRaftConsensus(unittest.TestCase):
    """Tests for core Raft leader election and log replication algorithms."""

    def setUp(self) -> None:
        self.n1 = RaftNode("n1")
        self.n2 = RaftNode("n2")
        self.n3 = RaftNode("n3")

        # Interconnect all 3 nodes
        for node in [self.n1, self.n2, self.n3]:
            for peer in [self.n1, self.n2, self.n3]:
                if node.node_id != peer.node_id:
                    node.add_peer(peer)

    def test_leader_election(self) -> None:
        self.assertEqual(self.n1.role, RaftRole.FOLLOWER)

        # Trigger election on n1
        won = self.n1.start_election()
        self.assertTrue(won)
        self.assertEqual(self.n1.role, RaftRole.LEADER)
        self.assertEqual(self.n1.current_term, 1)

        # n2 and n3 should still be followers in term 1
        self.assertEqual(self.n2.role, RaftRole.FOLLOWER)
        self.assertEqual(self.n3.role, RaftRole.FOLLOWER)
        self.assertEqual(self.n2.current_term, 1)
        self.assertEqual(self.n3.current_term, 1)

    def test_log_replication_and_commit(self) -> None:
        self.n1.start_election()

        # Propose commands to leader
        success1 = self.n1.propose({"op": "SET", "key": "k1", "val": "v1"})
        success2 = self.n1.propose({"op": "SET", "key": "k2", "val": "v2"})

        self.assertTrue(success1)
        self.assertTrue(success2)

        # Verify logs on leader
        self.assertEqual(len(self.n1.log), 3)  # dummy(0) + 1 + 2
        self.assertEqual(self.n1.commit_index, 2)
        self.assertEqual(len(self.n1.state_machine), 2)

        # Verify logs replicated on followers
        self.assertEqual(len(self.n2.log), 3)
        self.assertEqual(len(self.n3.log), 3)
        self.assertEqual(self.n2.commit_index, 2)
        self.assertEqual(self.n3.commit_index, 2)
        self.assertEqual(self.n2.state_machine, self.n1.state_machine)
        self.assertEqual(self.n3.state_machine, self.n1.state_machine)

    def test_minority_partition_fails_commit(self) -> None:
        self.n1.start_election()

        # Isolate followers n2 and n3
        self.n2.is_online = False
        self.n3.is_online = False

        # Leader cannot achieve majority
        committed = self.n1.propose({"op": "SET", "key": "isolated", "val": "data"})
        self.assertFalse(committed)
        # Commit index should not advance
        self.assertEqual(self.n1.commit_index, 0)

    def test_leader_crash_and_re_election(self) -> None:
        self.n1.start_election()
        self.n1.propose({"op": "WRITE", "doc": "initial_doc"})

        # Leader n1 crashes
        self.n1.is_online = False

        # Node n2 notices heartbeat timeout and starts election
        won = self.n2.start_election()
        self.assertTrue(won)
        self.assertEqual(self.n2.role, RaftRole.LEADER)
        self.assertEqual(self.n2.current_term, 2)

        # Propose new command to new leader n2
        success = self.n2.propose({"op": "WRITE", "doc": "new_doc"})
        self.assertTrue(success)
        self.assertEqual(len(self.n2.state_machine), 2)
        self.assertEqual(self.n3.state_machine, self.n2.state_machine)


class TestRaftCluster(unittest.TestCase):
    """Tests for RaftCluster orchestration."""

    def test_cluster_orchestration_and_execution(self) -> None:
        cluster = RaftCluster(["node_alpha", "node_beta", "node_gamma"])
        self.assertIsNone(cluster.get_leader())

        # Executing command triggers automatic leader election
        success = cluster.execute({"action": "CREATE_TABLE", "table": "papers"})
        self.assertTrue(success)

        leader = cluster.get_leader()
        self.assertIsNotNone(leader)
        assert leader is not None
        self.assertEqual(leader.role, RaftRole.LEADER)
        self.assertEqual(len(leader.state_machine), 1)


if __name__ == "__main__":
    unittest.main()
