#!/usr/bin/env python3
"""
Transaction Control Language (TCL) Transaction & Snapshot Manager.
Provides atomic transaction boundaries, staged buffer mutations, and rollback capabilities.
"""

from typing import Any, Dict, List, Optional


class TransactionError(Exception):
    """Raised when an illegal transaction state transition is attempted."""

    pass


class TransactionManager:
    """
    Manages in-memory transaction states, staging buffers, and rollback snapshots.
    """

    def __init__(self) -> None:
        self.is_active: bool = False
        self._staged_mutations: List[Dict[str, Any]] = []
        self._snapshot_state: Optional[Dict[str, Any]] = None

    def begin(self, current_state_snapshot: Optional[Dict[str, Any]] = None) -> None:
        """Starts a new transaction boundary."""
        if self.is_active:
            raise TransactionError("Transaction is already active")
        self.is_active = True
        self._staged_mutations.clear()
        self._snapshot_state = current_state_snapshot

    def stage_mutation(self, mutation_type: str, payload: Dict[str, Any]) -> None:
        """Stages a DML/DDL mutation inside the active transaction."""
        if not self.is_active:
            return
        self._staged_mutations.append({"type": mutation_type, "payload": payload})

    def commit(self) -> List[Dict[str, Any]]:
        """
        Commits active transaction, returning all staged mutations for final disk persistence.
        """
        if not self.is_active:
            raise TransactionError("No active transaction to commit")
        mutations = list(self._staged_mutations)
        self.is_active = False
        self._staged_mutations.clear()
        self._snapshot_state = None
        return mutations

    def rollback(self) -> Optional[Dict[str, Any]]:
        """
        Aborts active transaction, discarding staged mutations and returning snapshot state to restore.
        """
        if not self.is_active:
            raise TransactionError("No active transaction to rollback")
        snapshot = self._snapshot_state
        self.is_active = False
        self._staged_mutations.clear()
        self._snapshot_state = None
        return snapshot
