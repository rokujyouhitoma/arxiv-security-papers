#!/usr/bin/env python3
"""
Unit and Integration Tests for Phi Accrual Failure Detector and Gossip Protocol.
Verifies continuous suspicion level (Phi) calculation, jitter resilience,
and multi-node Gossip membership state propagation.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from database.distributed import GossipNode, NodeStatus, PhiAccrualDetector


class TestPhiAccrualDetector(unittest.TestCase):
    """Tests for Phi Accrual failure detection algorithm."""

    def test_steady_heartbeat_and_suspicion_growth(self) -> None:
        detector = PhiAccrualDetector(threshold=8.0, window_size=100)

        # Simulate regular heartbeats every 1.0s
        t = 1000.0
        for _ in range(20):
            detector.heartbeat(t)
            t += 1.0

        # At t=1020.0 (right after heartbeat), Phi should be very low
        phi_immediate = detector.phi(current_time=1020.0)
        self.assertLess(phi_immediate, 1.0)
        self.assertTrue(detector.is_available(current_time=1020.0))

        # As time progresses without heartbeat, Phi should increase monotonically
        phi_1s = detector.phi(current_time=1021.0)
        phi_2s = detector.phi(current_time=1022.0)
        phi_4s = detector.phi(current_time=1024.0)
        phi_8s = detector.phi(current_time=1028.0)

        self.assertGreater(phi_2s, phi_1s)
        self.assertGreater(phi_4s, phi_2s)
        self.assertGreater(phi_8s, phi_4s)

        # After enough elapsed time, Phi reaches DEAD threshold (>= 12.0)
        self.assertTrue(detector.is_dead(current_time=1030.0, dead_threshold=12.0))

    def test_jitter_resilience_and_recovery(self) -> None:
        detector = PhiAccrualDetector(threshold=8.0, min_std_dev=0.5)

        t = 1000.0
        intervals = [0.9, 1.1, 0.8, 1.2, 1.0, 0.95, 1.05] * 5
        for inv in intervals:
            t += inv
            detector.heartbeat(t)

        # Jitter: delayed by 2.0s
        self.assertFalse(detector.is_dead(current_time=t + 2.0, dead_threshold=12.0))

        # Heartbeat resumes
        t += 2.0
        detector.heartbeat(t)
        phi_recovered = detector.phi(current_time=t + 0.1)
        self.assertLess(phi_recovered, 2.0)
        self.assertTrue(detector.is_available(current_time=t + 0.1))


class TestGossipProtocol(unittest.TestCase):
    """Tests for multi-node Gossip state dissemination and failure detection."""

    def test_gossip_state_propagation_3_nodes(self) -> None:
        # Create 3 nodes: A, B, C
        node_a = GossipNode(node_id="nodeA", generation=100)
        node_b = GossipNode(node_id="nodeB", generation=100)
        node_c = GossipNode(node_id="nodeC", generation=100)

        # Node A increments heartbeat
        node_a.heartbeat()
        node_a.heartbeat()
        self.assertEqual(node_a.heartbeat_seq, 2)

        # Step 1: Node A gossips to Node B
        msg_a = node_a.prepare_gossip_message()
        node_b.process_gossip_message(msg_a, timestamp=1000.0)

        self.assertIn("nodeA", node_b.members)
        self.assertEqual(node_b.members["nodeA"].heartbeat_seq, 2)

        # Step 2: Node B gossips to Node C
        msg_b = node_b.prepare_gossip_message()
        node_c.process_gossip_message(msg_b, timestamp=1000.0)

        self.assertIn("nodeA", node_c.members)
        self.assertEqual(node_c.members["nodeA"].heartbeat_seq, 2)

    def test_gossip_failure_state_transition(self) -> None:
        node_a = GossipNode(node_id="nodeA", generation=100)
        node_b = GossipNode(node_id="nodeB", generation=100)

        # Establish initial heartbeats from Node B to Node A
        t = 1000.0
        for _ in range(10):
            node_b.heartbeat()
            node_a.process_gossip_message(node_b.prepare_gossip_message(), timestamp=t)
            t += 1.0

        # Check status at t=1010.0 -> Node B is ALIVE
        states = node_a.check_failure_states(current_time=1010.0)
        self.assertEqual(states["nodeB"], NodeStatus.ALIVE)

        # Node B crashes (no more messages from Node B)
        # Advance time by 15 seconds
        dead_states = node_a.check_failure_states(current_time=1025.0)
        self.assertEqual(dead_states["nodeB"], NodeStatus.DEAD)


if __name__ == "__main__":
    unittest.main()
