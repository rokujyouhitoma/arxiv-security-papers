#!/usr/bin/env python3
"""
Multi-Version Concurrency Control (MVCC) Subsystem.
Implements tuple versioning (xmin/xmax), Snapshot Isolation (SI),
non-blocking readers, and garbage collection (VACUUM).
"""

import threading
import time
from typing import Any, Dict, List, Optional, Set


class VersionedTuple:
    """Represents a multi-version record tuple with transaction visibility metadata."""

    def __init__(
        self,
        tuple_id: str,
        data: Any,
        xmin: int,
        xmax: int = 0,
        created_at: Optional[float] = None,
    ) -> None:
        self.tuple_id = tuple_id
        self.data = data
        self.xmin = xmin
        self.xmax = xmax
        self.created_at = created_at if created_at is not None else time.time()

    def is_deleted(self) -> bool:
        """Returns True if marked as deleted by a transaction."""
        return self.xmax != 0

    def __repr__(self) -> str:
        return (
            f"<VersionedTuple id={self.tuple_id!r} xmin={self.xmin} "
            f"xmax={self.xmax} data={self.data!r}>"
        )


class TransactionSnapshot:
    """
    Immutable transaction snapshot for Snapshot Isolation (SI).
    Captures active and committed transactions at transaction begin time.
    """

    def __init__(
        self,
        snapshot_tx_id: int,
        active_tx_ids: Set[int],
        committed_tx_ids: Set[int],
    ) -> None:
        self.snapshot_tx_id = snapshot_tx_id
        self.active_tx_ids = set(active_tx_ids)
        self.committed_tx_ids = set(committed_tx_ids)

    def is_visible(self, version: VersionedTuple) -> bool:
        """
        Determines if a versioned tuple is visible under this snapshot.
        Rules:
        1. Created by this transaction: visible unless deleted by this transaction.
        2. Created by an active/uncommitted transaction at snapshot time: invisible.
        3. Created by a transaction committed before snapshot: visible, unless
           deleted by a transaction committed before snapshot or by this transaction.
        """
        # Rule 1: Check creation (xmin)
        if version.xmin == self.snapshot_tx_id:
            # Created by self: visible unless deleted by self
            return version.xmax != self.snapshot_tx_id

        if version.xmin in self.active_tx_ids:
            # Creator was still in flight at snapshot time
            return False

        if version.xmin not in self.committed_tx_ids:
            # Creator has not committed
            return False

        # Rule 2: Check deletion (xmax)
        if version.xmax == 0:
            return True

        if version.xmax == self.snapshot_tx_id:
            # Deleted by self
            return False

        if version.xmax in self.active_tx_ids:
            # Deleter was still in flight at snapshot time, so delete not yet effective
            return True

        if version.xmax in self.committed_tx_ids:
            # Deleter was already committed at snapshot time, tuple is dead
            return False

        # Deleter uncommitted
        return True


class MVCCManager:
    """
    Coordinates multi-version concurrency control, transaction snapshots,
    conflict detection (First-Committer-Wins), and version cleanup.
    """

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._tx_counter = 1000
        self._active_txs: Set[int] = set()
        self._committed_txs: Set[int] = set()
        self._aborted_txs: Set[int] = set()
        self._snapshots: Dict[int, TransactionSnapshot] = {}
        # tuple_id -> List[VersionedTuple] (oldest to newest)
        self._versions: Dict[str, List[VersionedTuple]] = {}

    def begin_transaction(self, tx_id: Optional[int] = None) -> int:
        """Starts a new MVCC transaction and captures its Snapshot Isolation view."""
        with self._lock:
            if tx_id is None:
                self._tx_counter += 1
                assigned_id = self._tx_counter
            else:
                assigned_id = tx_id

            self._active_txs.add(assigned_id)
            snapshot = TransactionSnapshot(
                snapshot_tx_id=assigned_id,
                active_tx_ids=self._active_txs - {assigned_id},
                committed_tx_ids=self._committed_txs,
            )
            self._snapshots[assigned_id] = snapshot
            return assigned_id

    def get_snapshot(self, tx_id: int) -> TransactionSnapshot:
        """Retrieves or creates snapshot for transaction."""
        with self._lock:
            if tx_id not in self._snapshots:
                self.begin_transaction(tx_id)
            return self._snapshots[tx_id]

    def insert(self, tx_id: int, tuple_id: str, data: Any) -> VersionedTuple:
        """Inserts a new tuple version created by tx_id."""
        with self._lock:
            snapshot = self.get_snapshot(tx_id)
            # Check write-write conflict with existing visible version
            existing_versions = self._versions.get(tuple_id, [])
            for ver in reversed(existing_versions):
                if snapshot.is_visible(ver) and not ver.is_deleted():
                    raise ValueError(
                        f"Write-write conflict: tuple {tuple_id!r} already exists"
                    )

            version = VersionedTuple(tuple_id=tuple_id, data=data, xmin=tx_id)
            if tuple_id not in self._versions:
                self._versions[tuple_id] = []
            self._versions[tuple_id].append(version)
            return version

    def update(self, tx_id: int, tuple_id: str, new_data: Any) -> VersionedTuple:
        """Updates a tuple by marking the visible version's xmax and adding a new version."""
        with self._lock:
            snapshot = self.get_snapshot(tx_id)
            existing_versions = self._versions.get(tuple_id, [])
            target_version: Optional[VersionedTuple] = None

            for ver in reversed(existing_versions):
                if snapshot.is_visible(ver):
                    target_version = ver
                    break

            if target_version is None:
                raise KeyError(
                    f"Tuple {tuple_id!r} not found or not visible to Tx {tx_id}"
                )

            # Check if already modified by another concurrent transaction
            if (
                target_version.xmax != 0
                and target_version.xmax != tx_id
                and target_version.xmax in self._active_txs
            ):
                raise ValueError(
                    f"Write-write conflict on tuple {tuple_id!r} by concurrent Tx {target_version.xmax}"
                )

            target_version.xmax = tx_id
            new_version = VersionedTuple(tuple_id=tuple_id, data=new_data, xmin=tx_id)
            self._versions[tuple_id].append(new_version)
            return new_version

    def delete(self, tx_id: int, tuple_id: str) -> bool:
        """Deletes a tuple by setting xmax on the visible version."""
        with self._lock:
            snapshot = self.get_snapshot(tx_id)
            existing_versions = self._versions.get(tuple_id, [])
            for ver in reversed(existing_versions):
                if snapshot.is_visible(ver):
                    if (
                        ver.xmax != 0
                        and ver.xmax != tx_id
                        and ver.xmax in self._active_txs
                    ):
                        raise ValueError(
                            f"Write-write conflict on tuple {tuple_id!r} by concurrent Tx {ver.xmax}"
                        )
                    ver.xmax = tx_id
                    return True
            return False

    def get(self, tx_id: int, tuple_id: str) -> Optional[Any]:
        """Gets visible tuple data for transaction under Snapshot Isolation."""
        with self._lock:
            snapshot = self.get_snapshot(tx_id)
            for ver in reversed(self._versions.get(tuple_id, [])):
                if snapshot.is_visible(ver):
                    return ver.data
            return None

    def get_all_visible(self, tx_id: int) -> Dict[str, Any]:
        """Returns all currently visible tuples for transaction."""
        with self._lock:
            snapshot = self.get_snapshot(tx_id)
            result: Dict[str, Any] = {}
            for tuple_id, version_list in self._versions.items():
                for ver in reversed(version_list):
                    if snapshot.is_visible(ver):
                        result[tuple_id] = ver.data
                        break
            return result

    def commit_transaction(self, tx_id: int) -> None:
        """Commits transaction, making its modifications globally visible."""
        with self._lock:
            self._active_txs.discard(tx_id)
            self._committed_txs.add(tx_id)
            self._snapshots.pop(tx_id, None)

    def abort_transaction(self, tx_id: int) -> None:
        """Rolls back transaction, discarding its versions and resetting xmax."""
        with self._lock:
            self._active_txs.discard(tx_id)
            self._aborted_txs.add(tx_id)
            self._snapshots.pop(tx_id, None)

            # Cleanup versions created or modified by tx_id
            for tuple_id, version_list in list(self._versions.items()):
                cleaned: List[VersionedTuple] = []
                for ver in version_list:
                    if ver.xmin == tx_id:
                        # Version was created by aborted tx; discard it
                        continue
                    if ver.xmax == tx_id:
                        # Version was deleted by aborted tx; revert deletion
                        ver.xmax = 0
                    cleaned.append(ver)

                if cleaned:
                    self._versions[tuple_id] = cleaned
                else:
                    self._versions.pop(tuple_id, None)

    def vacuum(self) -> int:
        """
        Garbage-collects old tuple versions that are no longer visible to any active snapshot.
        Returns count of purged versions.
        """
        with self._lock:
            if not self._active_txs:
                min_active_tx = self._tx_counter + 1
            else:
                min_active_tx = min(self._active_txs)

            purged_count = 0
            for tuple_id, version_list in list(self._versions.items()):
                retained: List[VersionedTuple] = []
                for ver in version_list:
                    # If tuple was deleted and commited before min_active_tx, it can never be seen
                    if (
                        ver.xmax != 0
                        and ver.xmax in self._committed_txs
                        and ver.xmax < min_active_tx
                    ):
                        purged_count += 1
                        continue
                    retained.append(ver)

                if retained:
                    self._versions[tuple_id] = retained
                else:
                    self._versions.pop(tuple_id, None)
                    purged_count += 1

            return purged_count
