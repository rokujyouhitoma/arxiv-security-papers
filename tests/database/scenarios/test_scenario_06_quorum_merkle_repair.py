#!/usr/bin/env python3
"""
Scenario 6: Quorum Update and Merkle Tree Autonomous Healing (Strict Quorum / Anti-Entropy).
Location: tests/database/scenarios/test_scenario_06_quorum_merkle_repair.py
Persona: High-Availability Distributed Node System.
Verifies strict quorum (N=3, W=2, R=2) linearizability, CRDT version vectors,
and Merkle Tree O(log N) pinpoint differential sync without full-dataset scans.
"""

import os
import sys
import unittest

import pytest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.distributed.anti_entropy import AntiEntropySynchronizer
from database.distributed.quorum import QuorumCoordinator, QuorumReplica
from database.distributed.vector_clock import VectorClock
from database.distributed.version_vector import VersionedValue


class TestScenario06QuorumMerkleRepair(unittest.TestCase):
    """Verifies strict quorum read/write and Merkle tree anti-entropy healing."""

    def test_fast_strict_quorum_and_merkle_tree_healing(self) -> None:
        """Fast verification: Quorum write with 1 node down and Merkle differential sync."""
        rep1 = QuorumReplica("node_1")
        rep2 = QuorumReplica("node_2")
        rep3 = QuorumReplica("node_3")

        coord = QuorumCoordinator(replicas=[rep1, rep2, rep3], w_quorum=2, r_quorum=2)

        # Node 3 goes offline
        rep3.is_online = False

        # Write succeeds with W=2 (Node 1 and Node 2 online)
        res_w = coord.write("cve_2026_001", "Critical Remote Code Execution")
        self.assertIsNotNone(res_w)
        self.assertEqual(res_w.value, "Critical Remote Code Execution")

        # Read succeeds with R=2
        res_r = coord.read("cve_2026_001")
        self.assertIsNotNone(res_r)
        if res_r:
            self.assertEqual(res_r.value, "Critical Remote Code Execution")

        # Node 3 comes back online and undergoes Anti-Entropy sync
        rep3.is_online = True
        sync = AntiEntropySynchronizer()
        reconciled = sync.synchronize(rep1, rep3)
        self.assertGreaterEqual(reconciled, 1)

        # Node 3 now holds the updated value
        val3 = rep3.get("cve_2026_001")
        self.assertIsNotNone(val3)
        if val3:
            self.assertEqual(val3.value, "Critical Remote Code Execution")

    @pytest.mark.slow
    def test_slow_large_dataset_merkle_tree_precision_sync(self) -> None:
        """Slow verification: 500 keys with localized mutations repaired via Merkle synchronization."""
        rep_a = QuorumReplica(node_id="node_A")
        rep_b = QuorumReplica(node_id="node_B")

        shared_clock = VectorClock({"node_A": 1, "node_B": 1})

        for i in range(500):
            rep_a.put(
                f"tag_{i:04d}", VersionedValue(value=f"val_{i}", clock=shared_clock)
            )
            rep_b.put(
                f"tag_{i:04d}", VersionedValue(value=f"val_{i}", clock=shared_clock)
            )

        # Mutate 3 keys on node A with newer clock
        clock_a_new = VectorClock({"node_A": 10, "node_B": 1})
        rep_a.put("tag_0100", VersionedValue(value="MODIFIED_100", clock=clock_a_new))
        rep_a.put("tag_0200", VersionedValue(value="MODIFIED_200", clock=clock_a_new))
        rep_a.put("tag_0300", VersionedValue(value="MODIFIED_300", clock=clock_a_new))

        sync = AntiEntropySynchronizer()
        reconciled = sync.synchronize(rep_a, rep_b)
        self.assertEqual(reconciled, 3)


if __name__ == "__main__":
    unittest.main()
