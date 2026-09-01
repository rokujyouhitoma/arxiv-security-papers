#!/usr/bin/env python3
"""
Distributed Two-Phase Commit Coordinator Implementation.
Coordinates Phase 1 Voting and Phase 2 Atomic Decision Broadcast across participants.
"""

from typing import Dict, List, Optional

from .participant import TwoPCParticipant
from .types import GlobalDecision, TwoPCState, TxRecord, VoteType


class TwoPCCoordinator:
    """
    Coordinates distributed atomic transaction commit across participants.
    """

    def __init__(self, coordinator_id: str) -> None:
        self.coordinator_id = coordinator_id
        self.transactions: Dict[str, TxRecord] = {}
        self.is_online: bool = True

    def get_tx_state(self, tx_id: str) -> TwoPCState:
        """Returns the current global state of the transaction."""
        rec = self.transactions.get(tx_id)
        return rec.state if rec is not None else TwoPCState.INITIAL

    def _phase1_prepare(
        self,
        tx_id: str,
        participants: Dict[str, "TwoPCParticipant"],
        res_map: Dict[str, List[str]],
        force_abort_on: Optional[str],
    ) -> bool:
        for p_id, participant in participants.items():
            if not participant.is_online:
                return False
            vote = participant.prepare(
                tx_id=tx_id,
                resources=res_map.get(p_id, []),
                can_commit=(p_id != force_abort_on),
            )
            if vote != VoteType.VOTE_COMMIT:
                return False
        return True

    def _broadcast_decision(
        self,
        tx_id: str,
        participants: Dict[str, TwoPCParticipant],
        record: TxRecord,
        commit: bool,
    ) -> GlobalDecision:
        if commit:
            record.state = TwoPCState.COMMITTED
            for p in participants.values():
                p.commit(tx_id)
            return GlobalDecision.GLOBAL_COMMIT
        record.state = TwoPCState.ABORTED
        for p in participants.values():
            p.abort(tx_id)
        return GlobalDecision.GLOBAL_ABORT

    def execute_transaction(
        self,
        tx_id: str,
        participants: Dict[str, TwoPCParticipant],
        resources_map: Optional[Dict[str, List[str]]] = None,
        force_abort_on: Optional[str] = None,
    ) -> GlobalDecision:
        """
        Executes a 2PC atomic transaction across participants.
        Phase 1: Prepare (Gather Votes)
        Phase 2: Commit or Abort Broadcast
        """
        if not self.is_online:
            return GlobalDecision.GLOBAL_ABORT
        res_map = resources_map or {}
        record = TxRecord(tx_id=tx_id, participants=list(participants.keys()))
        self.transactions[tx_id] = record
        can_commit = self._phase1_prepare(tx_id, participants, res_map, force_abort_on)
        return self._broadcast_decision(tx_id, participants, record, can_commit)
