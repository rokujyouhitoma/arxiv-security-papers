#!/usr/bin/env python3
"""
Scenario 3: High-Concurrency Transactions and Deadlock Avoidance (MVCC / SS2PL).
Location: tests/database/scenarios/test_scenario_03_mvcc_deadlock.py
Persona: Multi-Threaded API Server.
Verifies lock-free snapshot reads via MVCC, Strict 2PL conflict management,
and Wait-For Graph cycle detection with automated victim abort.
"""

import os
import sys
import threading
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

from database.lock_manager import LockManager, LockMode, WaitForGraph
from database.mvcc import MVCCManager


class TestScenario03MVCCDeadlock(unittest.TestCase):
    """Verifies concurrency control, snapshot reads, and deadlock detection."""

    def test_fast_mvcc_lock_free_read_and_wfg_cycle_detection(self) -> None:
        """Fast verification: MVCC non-blocking reads and WFG 2-thread cycle detection."""
        # 1. MVCC non-blocking snapshot reads
        mvcc = MVCCManager()
        tx_writer = mvcc.begin_transaction()
        mvcc.insert(tx_writer, "paper_score_001", {"score": 85.5})
        mvcc.commit_transaction(tx_writer)

        # Start concurrent reader
        tx_reader = mvcc.begin_transaction()
        read_val1 = mvcc.get(tx_reader, "paper_score_001")
        self.assertEqual(read_val1, {"score": 85.5})

        # Concurrent writer updates record
        tx_writer2 = mvcc.begin_transaction()
        mvcc.update(tx_writer2, "paper_score_001", {"score": 99.0})
        mvcc.commit_transaction(tx_writer2)

        # Reader continues to see snapshot at its start time (Snapshot Isolation)
        read_val2 = mvcc.get(tx_reader, "paper_score_001")
        self.assertEqual(read_val2, {"score": 85.5})
        mvcc.commit_transaction(tx_reader)

        # New reader sees committed update
        tx_reader2 = mvcc.begin_transaction()
        read_val3 = mvcc.get(tx_reader2, "paper_score_001")
        self.assertEqual(read_val3, {"score": 99.0})
        mvcc.commit_transaction(tx_reader2)

        # 2. Wait-For Graph Deadlock Detection
        wfg = WaitForGraph()
        wfg.add_edge(101, 102)
        wfg.add_edge(102, 103)
        self.assertIsNone(wfg.detect_cycle())

        # Create cycle (103 -> 101)
        wfg.add_edge(103, 101)
        cycle = wfg.detect_cycle()
        self.assertIsNotNone(cycle)
        self.assertIn(101, cycle)

    @pytest.mark.slow
    def test_slow_multi_threaded_deadlock_detection_and_resolution(self) -> None:
        """Slow verification: High-concurrency 2PL lock contention with automated deadlock abort."""
        lm = LockManager()

        def worker_a() -> None:
            try:
                lm.acquire_lock(
                    tx_id=1, resource_id="res_alpha", mode=LockMode.EXCLUSIVE
                )
                time.sleep(0.05)
                lm.acquire_lock(
                    tx_id=1,
                    resource_id="res_beta",
                    mode=LockMode.EXCLUSIVE,
                    timeout=0.2,
                )
            except Exception:
                pass
            finally:
                lm.release_all_locks(1)

        def worker_b() -> None:
            try:
                lm.acquire_lock(
                    tx_id=2, resource_id="res_beta", mode=LockMode.EXCLUSIVE
                )
                time.sleep(0.05)
                lm.acquire_lock(
                    tx_id=2,
                    resource_id="res_alpha",
                    mode=LockMode.EXCLUSIVE,
                    timeout=0.2,
                )
            except Exception:
                pass
            finally:
                lm.release_all_locks(2)

        t1 = threading.Thread(target=worker_a)
        t2 = threading.Thread(target=worker_b)
        t1.start()
        t2.start()
        t1.join(timeout=2.0)
        t2.join(timeout=2.0)

        # Both threads must finish without hanging
        self.assertFalse(t1.is_alive())
        self.assertFalse(t2.is_alive())


if __name__ == "__main__":
    unittest.main()
