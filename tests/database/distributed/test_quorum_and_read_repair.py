#!/usr/bin/env python3
"""
Unit and Integration Tests for Quorum Replication, Read Repair, and Hinted Handoff.
Verifies Strict Quorum (W + R > N) strong consistency, automated background
Read Repair for stale replicas, and hinted write delivery upon node recovery.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.distributed import (
    HintedHandoffManager,
    QuorumCoordinator,
    QuorumReadError,
    QuorumReplica,
    QuorumWriteError,
    VectorClock,
    VersionedValue,
)


class TestQuorumReplicationAndReadRepair(unittest.TestCase):
    """Tests for QuorumCoordinator and Read Repair mechanisms."""

    def setUp(self) -> None:
        self.r1 = QuorumReplica("r1")
        self.r2 = QuorumReplica("r2")
        self.r3 = QuorumReplica("r3")
        self.replicas = [self.r1, self.r2, self.r3]
        self.coord = QuorumCoordinator(self.replicas, w_quorum=2, r_quorum=2)

    def test_strict_quorum_property(self) -> None:
        # N=3, W=2, R=2 -> 2+2=4 > 3 (Strict Quorum)
        self.assertTrue(self.coord.is_strict_quorum())

        # Weak config: W=1, R=1 -> 1+1=2 <= 3
        weak_coord = QuorumCoordinator(self.replicas, w_quorum=1, r_quorum=1)
        self.assertFalse(weak_coord.is_strict_quorum())

    def test_quorum_write_and_read_healthy_cluster(self) -> None:
        written = self.coord.write("user:100", {"name": "Alice"})
        self.assertIsNotNone(written)
        self.assertEqual(written.value, {"name": "Alice"})

        # Read back
        read_val = self.coord.read("user:100")
        self.assertIsNotNone(read_val)
        self.assertEqual(read_val.value, {"name": "Alice"})

    def test_quorum_write_and_read_with_one_node_down(self) -> None:
        # Node r3 fails
        self.r3.is_online = False

        # Write should succeed with W=2 (r1, r2)
        written = self.coord.write("paper:001", "Secure Multi-Party Computation")
        self.assertEqual(written.value, "Secure Multi-Party Computation")

        # Read should succeed with R=2 (r1, r2)
        read_val = self.coord.read("paper:001")
        self.assertIsNotNone(read_val)
        self.assertEqual(read_val.value, "Secure Multi-Party Computation")

        # Two nodes down -> Write must fail
        self.r2.is_online = False
        with self.assertRaises(QuorumWriteError):
            self.coord.write("paper:002", "Zero-Knowledge Proofs")

        with self.assertRaises(QuorumReadError):
            self.coord.read("paper:001")

    def test_read_repair_automatic_healing(self) -> None:
        # Write v1 to all replicas
        self.coord.write("key:config", "version_1")

        # Manually update r1, r2 to version_2 with a newer vector clock, leaving r3 stale
        newer_clock = VectorClock({"coord": 2})
        v2 = VersionedValue("version_2", clock=newer_clock, timestamp=200.0)
        self.r1.put("key:config", v2)
        self.r2.put("key:config", v2)

        # r3 still has version_1 (stale)
        self.assertEqual(self.r3.get("key:config").value, "version_1")

        # Read with Read Repair enabled
        result = self.coord.read("key:config", enable_read_repair=True)
        self.assertIsNotNone(result)
        self.assertEqual(result.value, "version_2")

        # Verify r3 was healed by Read Repair!
        self.assertEqual(self.r3.get("key:config").value, "version_2")
        self.assertEqual(self.r3.get("key:config").clock, newer_clock)


class TestHintedHandoff(unittest.TestCase):
    """Tests for Hinted Handoff buffering and node recovery flushing."""

    def test_hinted_handoff_lifecycle(self) -> None:
        manager = HintedHandoffManager()
        r_down = QuorumReplica("r_backup")
        r_down.is_online = False

        v = VersionedValue("payload_while_offline", clock=VectorClock({"coord": 1}))

        # Store hints while node is offline
        manager.store_hint("r_backup", "doc:99", v)
        self.assertEqual(manager.hint_count("r_backup"), 1)
        self.assertEqual(manager.flush_hints_for_node(r_down), 0)

        # Node recovers
        r_down.is_online = True
        applied = manager.flush_hints_for_node(r_down)
        self.assertEqual(applied, 1)
        self.assertEqual(manager.hint_count("r_backup"), 0)

        # Verify data landed on recovered replica
        recovered_val = r_down.get("doc:99")
        self.assertIsNotNone(recovered_val)
        self.assertEqual(recovered_val.value, "payload_while_offline")


if __name__ == "__main__":
    unittest.main()
