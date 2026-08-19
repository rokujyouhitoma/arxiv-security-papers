#!/usr/bin/env python3
"""
Raft Consensus Node Implementation.
Handles Leader Election, Log Replication, Heartbeats, Commit Quorum,
and State Machine Replication (SMR).
"""

from typing import Any, Dict, List, Optional

from .types import (
    AppendEntriesArgs,
    AppendEntriesReply,
    LogEntry,
    RaftRole,
    RequestVoteArgs,
    RequestVoteReply,
)


class RaftNode:
    """
    An active participant in a Raft consensus cluster.
    """

    def __init__(self, node_id: str) -> None:
        self.node_id = node_id
        self.current_term: int = 0
        self.voted_for: Optional[str] = None
        # 1-indexed log (dummy entry at index 0)
        self.log: List[LogEntry] = [LogEntry(index=0, term=0, command=None)]
        self.commit_index: int = 0
        self.last_applied: int = 0
        self.role: RaftRole = RaftRole.FOLLOWER
        self.state_machine: List[Any] = []
        self.is_online: bool = True

        self.peers: Dict[str, "RaftNode"] = {}
        self.next_index: Dict[str, int] = {}
        self.match_index: Dict[str, int] = {}

    @property
    def last_log_index(self) -> int:
        """Returns the index of the last log entry."""
        return self.log[-1].index

    @property
    def last_log_term(self) -> int:
        """Returns the term of the last log entry."""
        return self.log[-1].term

    @property
    def cluster_size(self) -> int:
        """Returns total cluster size including self."""
        return len(self.peers) + 1

    @property
    def majority(self) -> int:
        """Returns the quorum majority count."""
        return (self.cluster_size // 2) + 1

    def add_peer(self, peer: "RaftNode") -> None:
        """Registers a peer node in the cluster."""
        if peer.node_id != self.node_id:
            self.peers[peer.node_id] = peer

    def _step_down_if_newer_term(self, term: int) -> None:
        """Steps down to Follower if a strictly newer term is observed."""
        if term > self.current_term:
            self.current_term = term
            self.role = RaftRole.FOLLOWER
            self.voted_for = None

    def handle_request_vote(self, args: RequestVoteArgs) -> RequestVoteReply:
        """Handles incoming RequestVote RPC from a Candidate."""
        if not self.is_online:
            return RequestVoteReply(term=self.current_term, vote_granted=False)

        self._step_down_if_newer_term(args.term)

        if args.term < self.current_term:
            return RequestVoteReply(term=self.current_term, vote_granted=False)

        can_vote = self.voted_for is None or self.voted_for == args.candidate_id

        # Log completeness check (Raft 5.4.1)
        log_is_up_to_date = args.last_log_term > self.last_log_term or (
            args.last_log_term == self.last_log_term
            and args.last_log_index >= self.last_log_index
        )

        if can_vote and log_is_up_to_date:
            self.voted_for = args.candidate_id
            return RequestVoteReply(term=self.current_term, vote_granted=True)

        return RequestVoteReply(term=self.current_term, vote_granted=False)

    def handle_append_entries(self, args: AppendEntriesArgs) -> AppendEntriesReply:
        """Handles incoming AppendEntries (Heartbeat / Replication) RPC."""
        if not self.is_online:
            return AppendEntriesReply(
                term=self.current_term, success=False, match_index=0
            )

        self._step_down_if_newer_term(args.term)

        if args.term < self.current_term:
            return AppendEntriesReply(
                term=self.current_term, success=False, match_index=0
            )

        # Valid leader recognized
        self.role = RaftRole.FOLLOWER

        # Log consistency check (Raft 5.3)
        if args.prev_log_index >= len(self.log):
            return AppendEntriesReply(
                term=self.current_term, success=False, match_index=self.last_log_index
            )

        if self.log[args.prev_log_index].term != args.prev_log_term:
            # Delete conflicting entries
            self.log = self.log[: args.prev_log_index]
            return AppendEntriesReply(
                term=self.current_term, success=False, match_index=self.last_log_index
            )

        # Append new entries
        if args.entries:
            self.log = self.log[: args.prev_log_index + 1] + args.entries

        # Update commit index
        if args.leader_commit > self.commit_index:
            self.commit_index = min(args.leader_commit, self.last_log_index)
            self.apply_entries()

        return AppendEntriesReply(
            term=self.current_term,
            success=True,
            match_index=self.last_log_index,
        )

    def start_election(self) -> bool:
        """Starts an election to become cluster Leader."""
        if not self.is_online:
            return False

        self.role = RaftRole.CANDIDATE
        self.current_term += 1
        self.voted_for = self.node_id
        votes_granted = 1  # Vote for self

        args = RequestVoteArgs(
            term=self.current_term,
            candidate_id=self.node_id,
            last_log_index=self.last_log_index,
            last_log_term=self.last_log_term,
        )

        for peer in self.peers.values():
            if peer.is_online:
                reply = peer.handle_request_vote(args)
                if reply.vote_granted:
                    votes_granted += 1
                elif reply.term > self.current_term:
                    self._step_down_if_newer_term(reply.term)
                    return False

        if votes_granted >= self.majority:
            self.role = RaftRole.LEADER
            # Initialize leader state
            for peer_id in self.peers:
                self.next_index[peer_id] = self.last_log_index + 1
                self.match_index[peer_id] = 0
            return True

        return False

    def replicate_log(self) -> int:
        """Replicates pending log entries to all online followers."""
        if self.role != RaftRole.LEADER:
            return 0

        acked_count = 1  # Self

        for peer_id, peer in self.peers.items():
            if not peer.is_online:
                continue

            prev_idx = self.next_index.get(peer_id, self.last_log_index) - 1
            prev_idx = max(0, min(prev_idx, len(self.log) - 1))
            prev_term = self.log[prev_idx].term
            entries = self.log[prev_idx + 1 :]

            args = AppendEntriesArgs(
                term=self.current_term,
                leader_id=self.node_id,
                prev_log_index=prev_idx,
                prev_log_term=prev_term,
                entries=entries,
                leader_commit=self.commit_index,
            )

            reply = peer.handle_append_entries(args)
            if reply.success:
                self.match_index[peer_id] = reply.match_index
                self.next_index[peer_id] = reply.match_index + 1
                acked_count += 1
            elif reply.term > self.current_term:
                self._step_down_if_newer_term(reply.term)
                return 0
            else:
                # Decrement next_index on retry
                self.next_index[peer_id] = max(1, self.next_index.get(peer_id, 1) - 1)

        return acked_count

    def propose(self, command: Any) -> bool:
        """
        Proposes a new command to the replicated state machine.
        Appends to local log and replicates to followers for majority commit.
        """
        if self.role != RaftRole.LEADER or not self.is_online:
            return False

        entry = LogEntry(
            index=len(self.log),
            term=self.current_term,
            command=command,
        )
        self.log.append(entry)

        acks = self.replicate_log()
        if acks >= self.majority:
            self.commit_index = entry.index
            self.apply_entries()
            # Send updated commit index in heartbeat
            self.replicate_log()
            return True

        return False

    def apply_entries(self) -> List[Any]:
        """Applies committed log entries to the local state machine."""
        applied: List[Any] = []
        while self.last_applied < self.commit_index:
            self.last_applied += 1
            cmd = self.log[self.last_applied].command
            if cmd is not None:
                self.state_machine.append(cmd)
                applied.append(cmd)
        return applied
