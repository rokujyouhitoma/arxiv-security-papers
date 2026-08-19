#!/usr/bin/env python3
"""
Transaction Control Language (TCL) Transaction & Snapshot Manager.
Provides atomic transaction boundaries, staged buffer mutations,
MVCC Snapshot Isolation, and SS2PL lock management.
"""

from typing import Any, Dict, List, Optional

from ..lock_manager import LockManager, LockMode
from ..mvcc import MVCCManager, TransactionSnapshot


class TransactionError(Exception):
    """Raised when an illegal transaction state transition is attempted."""

    pass


class TransactionManager:
    """
    Manages transaction states, staging buffers, rollback snapshots,
    MVCC versioning, and SS2PL multi-resource locks.
    """

    def __init__(
        self,
        mvcc_manager: Optional[MVCCManager] = None,
        lock_manager: Optional[LockManager] = None,
    ) -> None:
        self.is_active: bool = False
        self.tx_id: int = 0
        self.isolation_level: str = "SNAPSHOT_ISOLATION"
        self._staged_mutations: List[Dict[str, Any]] = []
        self._snapshot_state: Optional[Dict[str, Any]] = None
        self.mvcc = mvcc_manager if mvcc_manager is not None else MVCCManager()
        self.lock_mgr = lock_manager if lock_manager is not None else LockManager()
        self._current_snapshot: Optional[TransactionSnapshot] = None
        self._tx_counter = 1000

    def begin(
        self,
        current_state_snapshot: Optional[Dict[str, Any]] = None,
        tx_id: Optional[int] = None,
        isolation_level: str = "SNAPSHOT_ISOLATION",
    ) -> int:
        """Starts a new transaction boundary with MVCC snapshot and lock context."""
        if self.is_active:
            raise TransactionError("Transaction is already active")

        self.is_active = True
        self.isolation_level = isolation_level
        self._staged_mutations.clear()
        self._snapshot_state = current_state_snapshot

        if tx_id is None:
            self._tx_counter += 1
            self.tx_id = self._tx_counter
        else:
            self.tx_id = tx_id

        self.mvcc.begin_transaction(self.tx_id)
        self._current_snapshot = self.mvcc.get_snapshot(self.tx_id)
        return self.tx_id

    def stage_mutation(self, mutation_type: str, payload: Dict[str, Any]) -> None:
        """Stages a DML/DDL mutation inside the active transaction."""
        if not self.is_active:
            return
        self._staged_mutations.append({"type": mutation_type, "payload": payload})

    def acquire_lock(
        self, resource_id: str, mode: LockMode = LockMode.SHARED, timeout: float = 2.0
    ) -> bool:
        """Acquires a resource lock for the current transaction."""
        if not self.is_active:
            return True
        return self.lock_mgr.acquire_lock(
            self.tx_id, resource_id, mode=mode, timeout=timeout
        )

    def commit(self) -> List[Dict[str, Any]]:
        """
        Commits active transaction, finalizing MVCC versions and releasing all SS2PL locks.
        """
        if not self.is_active:
            raise TransactionError("No active transaction to commit")

        mutations = list(self._staged_mutations)
        self.mvcc.commit_transaction(self.tx_id)
        self.lock_mgr.release_all_locks(self.tx_id)

        self.is_active = False
        self._staged_mutations.clear()
        self._snapshot_state = None
        self._current_snapshot = None
        return mutations

    def rollback(self) -> Optional[Dict[str, Any]]:
        """
        Aborts active transaction, reverting MVCC versions and releasing all SS2PL locks.
        """
        if not self.is_active:
            raise TransactionError("No active transaction to rollback")

        snapshot = self._snapshot_state
        self.mvcc.abort_transaction(self.tx_id)
        self.lock_mgr.release_all_locks(self.tx_id)

        self.is_active = False
        self._staged_mutations.clear()
        self._snapshot_state = None
        self._current_snapshot = None
        return snapshot
