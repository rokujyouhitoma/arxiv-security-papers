#!/usr/bin/env python3
"""
Unit tests for MVCC Transaction Tracking with Roaring Bitmap backend.
Verifies memory reduction on dense transaction IDs, snapshot isolation correctness,
clone speed, and backward compatibility.
"""

from typing import Set

from core.structures.roaring_bitmap import TYPE_BITMAP, RoaringBitmap
from database.transaction.mvcc import MVCCManager, TransactionSnapshot


def test_mvcc_roaring_bitmap_snapshot_isolation() -> None:
    """Verifies Snapshot Isolation visibility under RoaringBitmap tracking."""
    mvcc = MVCCManager()
    t1 = mvcc.begin_transaction()
    mvcc.insert(t1, "k1", "val_t1")

    # T2 starts before T1 commits -> cannot see k1
    t2 = mvcc.begin_transaction()
    assert mvcc.get(t2, "k1") is None

    # T1 commits -> T2 still cannot see k1 under SI
    mvcc.commit_transaction(t1)
    assert mvcc.get(t2, "k1") is None

    # T3 starts after T1 commits -> sees k1
    t3 = mvcc.begin_transaction()
    assert mvcc.get(t3, "k1") == "val_t1"


def test_mvcc_roaring_bitmap_dense_tx_compression() -> None:
    """Verifies memory footprint reduction on sequential committed transaction IDs."""
    mvcc = MVCCManager()
    count = 5000
    for _ in range(count):
        tx = mvcc.begin_transaction()
        mvcc.commit_transaction(tx)

    committed = mvcc.committed_txs
    assert len(committed) == count
    # 5,000 dense integers in a standard Python set consume >130 KB.
    # RoaringBitmap BitmapContainer uses 8 KB fixed.
    mem_size = committed.get_size_in_bytes()
    assert mem_size < 12000
    chunk0 = committed._chunks[0]
    assert chunk0.container_type() == TYPE_BITMAP


def test_mvcc_roaring_bitmap_snapshot_clone_integrity() -> None:
    """Verifies that snapshot clone is independent of subsequent commits."""
    mvcc = MVCCManager()
    t1 = mvcc.begin_transaction()
    mvcc.commit_transaction(t1)

    t2 = mvcc.begin_transaction()
    snap2 = mvcc.get_snapshot(t2)
    assert t1 in snap2.committed_tx_ids

    # T3 commits later; snap2 must remain unaffected
    t3 = mvcc.begin_transaction()
    mvcc.commit_transaction(t3)
    assert (t3 not in snap2.committed_tx_ids, t3 in mvcc.committed_txs) == (
        True,
        True,
    )


def test_mvcc_snapshot_set_input_backward_compatibility() -> None:
    """Verifies TransactionSnapshot accepts native Python Set[int] for backward compat."""
    legacy_active: Set[int] = {101, 102}
    legacy_committed: Set[int] = {90, 91, 92}
    snap = TransactionSnapshot(
        snapshot_tx_id=103,
        active_tx_ids=legacy_active,
        committed_tx_ids=legacy_committed,
    )

    assert (
        isinstance(snap.active_tx_ids, RoaringBitmap),
        isinstance(snap.committed_tx_ids, RoaringBitmap),
    ) == (
        True,
        True,
    )
    assert (101 in snap.active_tx_ids, 90 in snap.committed_tx_ids) == (True, True)
    assert (105 in snap.active_tx_ids, 89 in snap.committed_tx_ids) == (False, False)


def test_mvcc_aborted_transaction_tracking() -> None:
    """Verifies aborted transactions are tracked in aborted_txs RoaringBitmap."""
    mvcc = MVCCManager()
    tx1 = mvcc.begin_transaction()
    mvcc.insert(tx1, "k_abort", "temp_data")
    mvcc.abort_transaction(tx1)

    assert (tx1 in mvcc.aborted_txs, tx1 in mvcc.active_txs) == (True, False)
    t_after = mvcc.begin_transaction()
    assert mvcc.get(t_after, "k_abort") is None


def test_mvcc_vacuum_with_roaring_active_txs() -> None:
    """Verifies vacuum purges tuples older than min_active_tx computed from RoaringBitmap."""
    mvcc = MVCCManager()
    t1 = mvcc.begin_transaction()
    mvcc.insert(t1, "v_key", "v1")
    mvcc.commit_transaction(t1)

    t2 = mvcc.begin_transaction()
    mvcc.delete(t2, "v_key")
    mvcc.commit_transaction(t2)

    # With no active transactions, vacuum must purge the deleted version
    purged_count = mvcc.vacuum()
    assert purged_count > 0
    t3 = mvcc.begin_transaction()
    assert mvcc.get(t3, "v_key") is None
