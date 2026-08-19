#!/usr/bin/env python3
"""
Distributed Two-Phase Commit Participant Implementation.
Handles Phase 1 Resource Locking (Prepare) and Phase 2 Execution (Commit/Abort).
"""

from typing import Dict, List, Set

from .types import TwoPCState, VoteType


class TwoPCParticipant:
    """
    A participating node in a distributed 2PC transaction.
    """

    def __init__(self, participant_id: str) -> None:
        self.participant_id = participant_id
        self.tx_states: Dict[str, TwoPCState] = {}
        # resource_name -> owning tx_id
        self.resource_owners: Dict[str, str] = {}
        # tx_id -> set of acquired resource locks
        self.tx_locks: Dict[str, Set[str]] = {}
        self.is_online: bool = True

    def get_tx_state(self, tx_id: str) -> TwoPCState:
        """Returns the state of the transaction on this participant."""
        return self.tx_states.get(tx_id, TwoPCState.INITIAL)

    def prepare(
        self,
        tx_id: str,
        resources: List[str],
        can_commit: bool = True,
    ) -> VoteType:
        """
        Phase 1: Validates feasibility and acquires exclusive resource locks.
        """
        if not self.is_online or not can_commit:
            self.tx_states[tx_id] = TwoPCState.ABORTED
            return VoteType.VOTE_ABORT

        # Check for resource lock conflicts
        for res in resources:
            owner = self.resource_owners.get(res)
            if owner is not None and owner != tx_id:
                self.tx_states[tx_id] = TwoPCState.ABORTED
                return VoteType.VOTE_ABORT

        # Acquire locks
        acquired: Set[str] = set()
        for res in resources:
            self.resource_owners[res] = tx_id
            acquired.add(res)

        self.tx_locks[tx_id] = acquired
        self.tx_states[tx_id] = TwoPCState.PREPARED
        return VoteType.VOTE_COMMIT

    def commit(self, tx_id: str) -> bool:
        """
        Phase 2: Finalizes transaction and releases all resource locks.
        """
        if not self.is_online:
            return False

        self.tx_states[tx_id] = TwoPCState.COMMITTED
        self._release_locks(tx_id)
        return True

    def abort(self, tx_id: str) -> bool:
        """
        Phase 2: Rolls back transaction and releases all resource locks.
        """
        self.tx_states[tx_id] = TwoPCState.ABORTED
        self._release_locks(tx_id)
        return True

    def _release_locks(self, tx_id: str) -> None:
        """Releases all resource locks held by the transaction."""
        locks = self.tx_locks.pop(tx_id, set())
        for res in locks:
            if self.resource_owners.get(res) == tx_id:
                del self.resource_owners[res]
