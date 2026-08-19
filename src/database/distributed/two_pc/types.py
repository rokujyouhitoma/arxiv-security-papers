#!/usr/bin/env python3
"""
Distributed Two-Phase Commit (2PC) Types and State Definitions.
Defines states, voting results, global decisions, and transaction records.
"""

import enum
from typing import Any, Dict, List, Optional


class TwoPCState(enum.Enum):
    """Lifecycle state of a 2PC transaction participant or coordinator."""

    INITIAL = "INITIAL"
    PREPARED = "PREPARED"
    COMMITTED = "COMMITTED"
    ABORTED = "ABORTED"


class VoteType(enum.Enum):
    """Participant vote response in Phase 1 (Prepare)."""

    VOTE_COMMIT = "VOTE_COMMIT"
    VOTE_ABORT = "VOTE_ABORT"


class GlobalDecision(enum.Enum):
    """Coordinator decision broadcast in Phase 2."""

    GLOBAL_COMMIT = "GLOBAL_COMMIT"
    GLOBAL_ABORT = "GLOBAL_ABORT"


class TxRecord:
    """Metadata tracking a distributed 2PC transaction."""

    def __init__(
        self,
        tx_id: str,
        participants: List[str],
        state: TwoPCState = TwoPCState.INITIAL,
        payload: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.tx_id = tx_id
        self.participants = list(participants)
        self.state = state
        self.payload = payload or {}

    def __repr__(self) -> str:
        return f"TxRecord(id={self.tx_id!r}, state={self.state.value}, parts={self.participants})"
