#!/usr/bin/env python3
"""
Unit and Integration Tests for Distributed 2PC (Two-Phase Commit)
and Distributed Deadlock Detection Engine.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "src")
        ),
    )

from database.distributed.two_pc import (
    DistributedDeadlockDetector,
    GlobalDecision,
    TwoPCCoordinator,
    TwoPCParticipant,
    TwoPCState,
    VoteType,
)


class TestTwoPhaseCommit(unittest.TestCase):
    """Tests for distributed 2PC coordinator and participant transactions."""

    def setUp(self) -> None:
        self.coord = TwoPCCoordinator("coord-1")
        self.p1 = TwoPCParticipant("part-1")
        self.p2 = TwoPCParticipant("part-2")
        self.p3 = TwoPCParticipant("part-3")
        self.participants = {
            "part-1": self.p1,
            "part-2": self.p2,
            "part-3": self.p3,
        }

    def test_successful_two_phase_commit(self) -> None:
        resources = {
            "part-1": ["table:users"],
            "part-2": ["table:orders"],
            "part-3": ["table:audit_log"],
        }

        decision = self.coord.execute_transaction(
            tx_id="tx-100",
            participants=self.participants,
            resources_map=resources,
        )

        self.assertEqual(decision, GlobalDecision.GLOBAL_COMMIT)
        self.assertEqual(self.coord.get_tx_state("tx-100"), TwoPCState.COMMITTED)
        self.assertEqual(self.p1.get_tx_state("tx-100"), TwoPCState.COMMITTED)
        self.assertEqual(self.p2.get_tx_state("tx-100"), TwoPCState.COMMITTED)
        self.assertEqual(self.p3.get_tx_state("tx-100"), TwoPCState.COMMITTED)

        # Locks should be fully released after commit
        self.assertEqual(len(self.p1.resource_owners), 0)
        self.assertEqual(len(self.p2.resource_owners), 0)
        self.assertEqual(len(self.p3.resource_owners), 0)

    def test_abort_when_single_participant_fails(self) -> None:
        resources = {
            "part-1": ["table:users"],
            "part-2": ["table:orders"],
            "part-3": ["table:audit_log"],
        }

        # Force participant 2 to abort
        decision = self.coord.execute_transaction(
            tx_id="tx-101",
            participants=self.participants,
            resources_map=resources,
            force_abort_on="part-2",
        )

        self.assertEqual(decision, GlobalDecision.GLOBAL_ABORT)
        self.assertEqual(self.coord.get_tx_state("tx-101"), TwoPCState.ABORTED)
        self.assertEqual(self.p1.get_tx_state("tx-101"), TwoPCState.ABORTED)
        self.assertEqual(self.p2.get_tx_state("tx-101"), TwoPCState.ABORTED)
        self.assertEqual(self.p3.get_tx_state("tx-101"), TwoPCState.ABORTED)

        # Locks should be cleanly released on abort
        self.assertEqual(len(self.p1.resource_owners), 0)
        self.assertEqual(len(self.p2.resource_owners), 0)
        self.assertEqual(len(self.p3.resource_owners), 0)

    def test_lock_conflict_triggers_abort(self) -> None:
        # Pre-lock resource on p1 with a pending prepared tx
        vote = self.p1.prepare("tx-locked", ["row:999"])
        self.assertEqual(vote, VoteType.VOTE_COMMIT)
        self.assertEqual(self.p1.get_tx_state("tx-locked"), TwoPCState.PREPARED)

        # Try to execute a 2PC transaction that touches the same row
        decision = self.coord.execute_transaction(
            tx_id="tx-102",
            participants={"part-1": self.p1},
            resources_map={"part-1": ["row:999"]},
        )

        self.assertEqual(decision, GlobalDecision.GLOBAL_ABORT)
        self.assertEqual(self.p1.get_tx_state("tx-102"), TwoPCState.ABORTED)

        # Original tx lock is still held
        self.assertEqual(self.p1.resource_owners.get("row:999"), "tx-locked")


class TestDistributedDeadlockDetector(unittest.TestCase):
    """Tests for Wait-For Graph (WFG) cycle and deadlock detection."""

    def setUp(self) -> None:
        self.detector = DistributedDeadlockDetector()

    def test_no_deadlock(self) -> None:
        self.detector.add_wait_edge("T1", "T2")
        self.detector.add_wait_edge("T2", "T3")
        self.assertIsNone(self.detector.detect_cycle())
        self.assertIsNone(self.detector.select_victim())

    def test_cycle_detection_and_victim_selection(self) -> None:
        # T1 -> T2 -> T3 -> T1 (Cycle)
        self.detector.add_wait_edge("T1", "T2")
        self.detector.add_wait_edge("T2", "T3")
        self.detector.add_wait_edge("T3", "T1")

        cycle = self.detector.detect_cycle()
        self.assertIsNotNone(cycle)
        assert cycle is not None
        self.assertIn("T1", cycle)
        self.assertIn("T2", cycle)
        self.assertIn("T3", cycle)

        victim = self.detector.select_victim(cycle)
        self.assertEqual(victim, "T3")

        # Break deadlock by clearing victim
        self.detector.clear_tx(victim)
        self.assertIsNone(self.detector.detect_cycle())


if __name__ == "__main__":
    unittest.main()
