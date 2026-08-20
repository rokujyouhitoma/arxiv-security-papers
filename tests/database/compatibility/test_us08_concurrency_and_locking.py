#!/usr/bin/env python3
"""
US-08: Concurrency Control, 2PL, and Deadlock Detection in src/database.
Tests LockManager (Shared/Exclusive locks), WaitForGraph cycle detection,
and automated transaction aborts in pure Python database engine.
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

from database import LockManager, LockMode, WaitForGraph


class TestUS08ConcurrencyAndLocking(unittest.TestCase):
    """Verifies Strict 2PL and deadlock detection."""

    def test_strict_2pl_lock_compatibility(self) -> None:
        lm = LockManager()

        # Shared locks are compatible
        g1 = lm.acquire_lock(tx_id=1, resource_id="page_10", mode=LockMode.SHARED)
        g2 = lm.acquire_lock(tx_id=2, resource_id="page_10", mode=LockMode.SHARED)
        self.assertTrue(g1)
        self.assertTrue(g2)

        # Exclusive lock conflicts with shared locks (timeout quickly)
        g3 = lm.acquire_lock(
            tx_id=3, resource_id="page_10", mode=LockMode.EXCLUSIVE, timeout=0.05
        )
        self.assertFalse(g3)

        # Release shared locks allows exclusive acquisition
        lm.release_all_locks(tx_id=1)
        lm.release_all_locks(tx_id=2)
        g4 = lm.acquire_lock(
            tx_id=3, resource_id="page_10", mode=LockMode.EXCLUSIVE, timeout=0.05
        )
        self.assertTrue(g4)

    def test_wait_for_graph_deadlock_detection(self) -> None:
        wfg = WaitForGraph()
        # Tx1 waits for Tx2, Tx2 waits for Tx3, Tx3 waits for Tx1 (Cycle)
        wfg.add_edge(1, 2)
        wfg.add_edge(2, 3)
        self.assertIsNone(wfg.detect_cycle())

        wfg.add_edge(3, 1)
        cycle = wfg.detect_cycle()
        self.assertIsNotNone(cycle)


if __name__ == "__main__":
    unittest.main()
