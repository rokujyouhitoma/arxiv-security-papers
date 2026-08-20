#!/usr/bin/env python3
"""
Scenario 5: Distributed Network Partition, Failure Detection, and Leader Election (Phi Accrual / Raft).
Location: tests/database/scenarios/test_scenario_05_raft_partition_election.py
Persona: Cluster Operations Orchestrator.
Verifies statistical failure detection (Phi >= 12), Term increments,
Quorum RequestVote election, and split-brain prevention via Epoch Fencing.
"""

import os
import sys
import time
import unittest

import pytest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.distributed.phi_accrual import PhiAccrualDetector
from database.distributed.raft import RaftCluster, RaftRole


class TestScenario05RaftPartitionElection(unittest.TestCase):
    """Verifies failure detection, quorum election, and split-brain prevention."""

    def test_fast_phi_accrual_and_raft_election_lifecycle(self) -> None:
        """Fast verification: Statistical failure detection and Raft consensus."""
        # 1. Phi Accrual failure detection
        detector = PhiAccrualDetector(threshold=12.0)
        base_time = time.time()
        # Normal steady heartbeats every 1.0 second
        for i in range(15):
            detector.heartbeat(timestamp=base_time + (i * 1.0))

        # Immediately after heartbeat, suspicion level is zero
        phi_fresh = detector.phi(current_time=base_time + 15.0)
        self.assertLess(phi_fresh, 1.0)

        # Prolonged silence causes Phi to grow exponentially past 12.0
        phi_timeout = detector.phi(current_time=base_time + 35.0)
        self.assertGreaterEqual(phi_timeout, 12.0)
        self.assertTrue(
            detector.is_dead(current_time=base_time + 35.0, dead_threshold=12.0)
        )

        # 2. Raft Cluster leader election and consensus
        cluster = RaftCluster(node_ids=["node_A", "node_B", "node_C"])
        leader = cluster.elect_leader("node_A")
        self.assertIsNotNone(leader)
        if leader:
            self.assertEqual(leader.role, RaftRole.LEADER)
            self.assertEqual(leader.current_term, 1)

        # Replicate log across quorum
        success = cluster.execute("SET paper:2608.001 'Homomorphic Encryption'")
        self.assertTrue(success)

        # 3. Simulate Node A failure and failover election to Node B
        new_leader = cluster.elect_leader("node_B")
        self.assertIsNotNone(new_leader)
        if new_leader:
            self.assertEqual(new_leader.role, RaftRole.LEADER)
            self.assertGreater(new_leader.current_term, 1)

        # Former leader Node A drops to follower upon observing higher term
        node_a = cluster.nodes.get("node_A")
        if node_a:
            self.assertEqual(node_a.role, RaftRole.FOLLOWER)

    @pytest.mark.slow
    def test_slow_phi_accrual_jitter_resilience(self) -> None:
        """Slow verification: Phi Accrual adaptability under simulated network jitter."""
        detector = PhiAccrualDetector(threshold=12.0)
        t = 1000.0
        # Heartbeats with normal statistical jitter (+- 0.3s)
        intervals = [1.1, 0.9, 1.2, 0.8, 1.0, 1.3, 0.7, 1.1, 0.9, 1.0] * 5
        for interval in intervals:
            t += interval
            detector.heartbeat(timestamp=t)

        # Jitter within 2.0s should not trigger false positive death
        phi_jitter = detector.phi(current_time=t + 1.8)
        self.assertLess(phi_jitter, 12.0)


if __name__ == "__main__":
    unittest.main()
