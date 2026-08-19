#!/usr/bin/env python3
"""
Raft Consensus RPC Types and State Definitions.
Defines roles, log entries, and RequestVote / AppendEntries message payloads.
"""

import enum
from typing import Any, List


class RaftRole(enum.Enum):
    """Raft consensus node role."""

    FOLLOWER = "Follower"
    CANDIDATE = "Candidate"
    LEADER = "Leader"


class LogEntry:
    """A replicated state machine log entry."""

    def __init__(self, index: int, term: int, command: Any) -> None:
        self.index = index
        self.term = term
        self.command = command

    def __repr__(self) -> str:
        return f"LogEntry(idx={self.index}, term={self.term}, cmd={self.command!r})"

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, LogEntry):
            return False
        return (
            self.index == other.index
            and self.term == other.term
            and self.command == other.command
        )


class RequestVoteArgs:
    """Arguments for RequestVote RPC."""

    def __init__(
        self,
        term: int,
        candidate_id: str,
        last_log_index: int,
        last_log_term: int,
    ) -> None:
        self.term = term
        self.candidate_id = candidate_id
        self.last_log_index = last_log_index
        self.last_log_term = last_log_term


class RequestVoteReply:
    """Results of RequestVote RPC."""

    def __init__(self, term: int, vote_granted: bool) -> None:
        self.term = term
        self.vote_granted = vote_granted


class AppendEntriesArgs:
    """Arguments for AppendEntries (Heartbeat / Replication) RPC."""

    def __init__(
        self,
        term: int,
        leader_id: str,
        prev_log_index: int,
        prev_log_term: int,
        entries: List[LogEntry],
        leader_commit: int,
    ) -> None:
        self.term = term
        self.leader_id = leader_id
        self.prev_log_index = prev_log_index
        self.prev_log_term = prev_log_term
        self.entries = entries
        self.leader_commit = leader_commit


class AppendEntriesReply:
    """Results of AppendEntries RPC."""

    def __init__(self, term: int, success: bool, match_index: int) -> None:
        self.term = term
        self.success = success
        self.match_index = match_index
