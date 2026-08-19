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
        participant_ids = list(participants.keys())
        record = TxRecord(tx_id=tx_id, participants=participant_ids)
        self.transactions[tx_id] = record

        # --- Phase 1: Prepare ---
        all_voted_commit = True

        for p_id, participant in participants.items():
            if not participant.is_online:
                all_voted_commit = False
                break

            target_resources = res_map.get(p_id, [])
            can_commit = p_id != force_abort_on

            vote = participant.prepare(
                tx_id=tx_id,
                resources=target_resources,
                can_commit=can_commit,
            )

            if vote != VoteType.VOTE_COMMIT:
                all_voted_commit = False
                break

        # --- Phase 2: Commit or Abort ---
        if all_voted_commit:
            record.state = TwoPCState.COMMITTED
            for participant in participants.values():
                participant.commit(tx_id)
            return GlobalDecision.GLOBAL_COMMIT

        record.state = TwoPCState.ABORTED
        for participant in participants.values():
            participant.abort(tx_id)
        return GlobalDecision.GLOBAL_ABORT
