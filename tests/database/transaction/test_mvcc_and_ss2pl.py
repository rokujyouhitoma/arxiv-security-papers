#!/usr/bin/env python3
"""
Unit and Integration Tests for MVCC and SS2PL Subsystems.
Verifies Snapshot Isolation, First-Committer-Wins conflict resolution,
VACUUM garbage collection, Strict 2-Phase Locking, and Deadlock Detection.
"""

import os
import sys
import threading
import time
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from database.lock_manager import (
    DeadlockError,
    LockManager,
    LockMode,
    WaitForGraph,
    is_compatible,
)
from database.mvcc import MVCCManager
from database.sql.transaction import TransactionManager


class TestMVCCSnapshotIsolation(unittest.TestCase):
    """Tests for MVCC multi-versioning and Snapshot Isolation."""

    def test_mvcc_non_blocking_readers_and_snapshot_isolation(self) -> None:
        mvcc = MVCCManager()

        # Seed data in initial committed transaction
        tx0 = mvcc.begin_transaction()
        mvcc.insert(tx0, "paper:001", {"title": "Zero Trust Security", "views": 10})
        mvcc.commit_transaction(tx0)

        # Tx1 starts (reads version 1)
        tx1 = mvcc.begin_transaction()
        self.assertEqual(mvcc.get(tx1, "paper:001")["title"], "Zero Trust Security")

        # Tx2 starts and updates paper:001
        tx2 = mvcc.begin_transaction()
        mvcc.update(tx2, "paper:001", {"title": "Zero Trust Security v2", "views": 20})

        # Tx1 still reads the old committed version (Snapshot Isolation)
        self.assertEqual(mvcc.get(tx1, "paper:001")["title"], "Zero Trust Security")
        self.assertEqual(mvcc.get(tx1, "paper:001")["views"], 10)

        # Tx2 commits
        mvcc.commit_transaction(tx2)

        # Tx1 still sees the snapshot from its begin time (Repeatable Read)
        self.assertEqual(mvcc.get(tx1, "paper:001")["title"], "Zero Trust Security")

        # Tx3 starting after Tx2 commit sees the updated version
        tx3 = mvcc.begin_transaction()
        self.assertEqual(mvcc.get(tx3, "paper:001")["title"], "Zero Trust Security v2")
        self.assertEqual(mvcc.get(tx3, "paper:001")["views"], 20)

        mvcc.commit_transaction(tx1)
        mvcc.commit_transaction(tx3)

    def test_mvcc_write_conflict_detection(self) -> None:
        mvcc = MVCCManager()
        tx0 = mvcc.begin_transaction()
        mvcc.insert(tx0, "paper:002", {"status": "draft"})
        mvcc.commit_transaction(tx0)

        tx1 = mvcc.begin_transaction()
        tx2 = mvcc.begin_transaction()

        # Tx1 updates
        mvcc.update(tx1, "paper:002", {"status": "published"})

        # Tx2 concurrently attempts to update the same tuple -> conflict
        with self.assertRaises(ValueError):
            mvcc.update(tx2, "paper:002", {"status": "archived"})

        mvcc.commit_transaction(tx1)
        mvcc.abort_transaction(tx2)

    def test_mvcc_delete_and_rollback(self) -> None:
        mvcc = MVCCManager()
        tx0 = mvcc.begin_transaction()
        mvcc.insert(tx0, "paper:003", {"tag": "crypto"})
        mvcc.commit_transaction(tx0)

        # Tx1 deletes but aborts
        tx1 = mvcc.begin_transaction()
        deleted = mvcc.delete(tx1, "paper:003")
        self.assertTrue(deleted)
        self.assertIsNone(mvcc.get(tx1, "paper:003"))
        mvcc.abort_transaction(tx1)

        # Tx2 sees the resurrected tuple
        tx2 = mvcc.begin_transaction()
        self.assertEqual(mvcc.get(tx2, "paper:003")["tag"], "crypto")
        mvcc.commit_transaction(tx2)

    def test_mvcc_vacuum_garbage_collection(self) -> None:
        mvcc = MVCCManager()
        tx0 = mvcc.begin_transaction()
        mvcc.insert(tx0, "paper:temp", {"val": 1})
        mvcc.commit_transaction(tx0)

        # Update and delete
        tx1 = mvcc.begin_transaction()
        mvcc.update(tx1, "paper:temp", {"val": 2})
        mvcc.commit_transaction(tx1)

        tx2 = mvcc.begin_transaction()
        mvcc.delete(tx2, "paper:temp")
        mvcc.commit_transaction(tx2)

        # Vacuum should purge dead versions
        purged = mvcc.vacuum()
        self.assertGreaterEqual(purged, 1)


class TestLockManagerAndDeadlockDetection(unittest.TestCase):
    """Tests for SS2PL Locking and Wait-For Graph Deadlock Detection."""

    def test_lock_compatibility(self) -> None:
        self.assertTrue(is_compatible(LockMode.SHARED, LockMode.SHARED))
        self.assertFalse(is_compatible(LockMode.SHARED, LockMode.EXCLUSIVE))
        self.assertFalse(is_compatible(LockMode.EXCLUSIVE, LockMode.SHARED))
        self.assertFalse(is_compatible(LockMode.EXCLUSIVE, LockMode.EXCLUSIVE))
        self.assertTrue(is_compatible(LockMode.INTENT_SHARED, LockMode.INTENT_SHARED))

    def test_ss2pl_shared_and_exclusive_locks(self) -> None:
        lock_mgr = LockManager()

        # Multiple transactions can acquire SHARED locks on same resource
        self.assertTrue(
            lock_mgr.acquire_lock(
                tx_id=1, resource_id="tbl:papers", mode=LockMode.SHARED
            )
        )
        self.assertTrue(
            lock_mgr.acquire_lock(
                tx_id=2, resource_id="tbl:papers", mode=LockMode.SHARED
            )
        )

        # Tx3 cannot acquire EXCLUSIVE lock while Tx1/Tx2 hold SHARED
        self.assertFalse(
            lock_mgr.acquire_lock(
                tx_id=3, resource_id="tbl:papers", mode=LockMode.EXCLUSIVE, timeout=0.05
            )
        )

        # Tx1 and Tx2 commit (SS2PL release all locks)
        lock_mgr.release_all_locks(tx_id=1)
        lock_mgr.release_all_locks(tx_id=2)

        # Now Tx3 can acquire EXCLUSIVE lock
        self.assertTrue(
            lock_mgr.acquire_lock(
                tx_id=3, resource_id="tbl:papers", mode=LockMode.EXCLUSIVE, timeout=0.1
            )
        )
        lock_mgr.release_all_locks(tx_id=3)

    def test_wait_for_graph_cycle_detection(self) -> None:
        wfg = WaitForGraph()
        # 1 -> 2, 2 -> 3, 3 -> 1 (Cycle)
        wfg.add_edge(1, 2)
        wfg.add_edge(2, 3)
        self.assertIsNone(wfg.detect_cycle())

        wfg.add_edge(3, 1)
        cycle = wfg.detect_cycle()
        self.assertIsNotNone(cycle)
        self.assertEqual(len(cycle), 4)  # [1, 2, 3, 1]

        # Break cycle
        wfg.remove_edge(3, 1)
        self.assertIsNone(wfg.detect_cycle())

    def test_lock_manager_deadlock_detection_and_abort(self) -> None:
        lock_mgr = LockManager()

        # Setup 2 threads: T1 holds A wants B; T2 holds B wants A
        t1_held_a = threading.Event()
        t2_held_b = threading.Event()
        deadlock_caught = []

        def worker1() -> None:
            try:
                lock_mgr.acquire_lock(
                    tx_id=10, resource_id="res:A", mode=LockMode.EXCLUSIVE
                )
                t1_held_a.set()
                t2_held_b.wait(timeout=2.0)
                time.sleep(0.05)
                # Request B (held by T2)
                lock_mgr.acquire_lock(
                    tx_id=10, resource_id="res:B", mode=LockMode.EXCLUSIVE, timeout=1.0
                )
            except DeadlockError as e:
                deadlock_caught.append((10, e))
            finally:
                lock_mgr.release_all_locks(tx_id=10)

        def worker2() -> None:
            try:
                t1_held_a.wait(timeout=2.0)
                lock_mgr.acquire_lock(
                    tx_id=20, resource_id="res:B", mode=LockMode.EXCLUSIVE
                )
                t2_held_b.set()
                time.sleep(0.05)
                # Request A (held by T1) -> will form cycle T1->T2->T1
                lock_mgr.acquire_lock(
                    tx_id=20, resource_id="res:A", mode=LockMode.EXCLUSIVE, timeout=1.0
                )
            except DeadlockError as e:
                deadlock_caught.append((20, e))
            finally:
                lock_mgr.release_all_locks(tx_id=20)

        th1 = threading.Thread(target=worker1)
        th2 = threading.Thread(target=worker2)
        th1.start()
        th2.start()
        th1.join()
        th2.join()

        # Exactly one transaction should have been aborted due to DeadlockError
        self.assertGreaterEqual(len(deadlock_caught), 1)


class TestTransactionManagerIntegration(unittest.TestCase):
    """Tests for integrated TransactionManager with MVCC and SS2PL."""

    def test_transaction_manager_full_lifecycle(self) -> None:
        tx_mgr = TransactionManager()
        tx_mgr.begin()
        self.assertTrue(tx_mgr.is_active)

        # Acquire lock and stage mutation
        locked = tx_mgr.acquire_lock("table:papers", mode=LockMode.EXCLUSIVE)
        self.assertTrue(locked)

        tx_mgr.stage_mutation("INSERT", {"id": "p1", "title": "Secure AI"})
        mutations = tx_mgr.commit()

        self.assertEqual(len(mutations), 1)
        self.assertFalse(tx_mgr.is_active)
        # Lock should be released
        self.assertFalse(tx_mgr.lock_mgr.is_locked("table:papers"))


if __name__ == "__main__":
    unittest.main()
