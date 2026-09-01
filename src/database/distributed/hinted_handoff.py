#!/usr/bin/env python3
"""
Hinted Handoff Manager for Sloppy Quorums and High Availability.
Buffers writes destined for unreachable replicas and flushes them upon recovery.
"""

import time
from typing import Dict, List, Optional

from .quorum import QuorumReplica
from .version_vector import VersionedValue


class Hint:
    """A buffered write hint destined for a temporarily offline replica."""

    def __init__(
        self,
        target_node_id: str,
        key: str,
        version: VersionedValue,
        timestamp: Optional[float] = None,
    ) -> None:
        self.target_node_id = target_node_id
        self.key = key
        self.version = version
        self.timestamp = timestamp if timestamp is not None else time.time()

    def __repr__(self) -> str:
        return (
            f"Hint(target={self.target_node_id}, key={self.key}, ts={self.timestamp})"
        )


class HintedHandoffManager:
    """
    Manages local storage of hints and delivers them when target replicas resume operation.
    """

    def __init__(self) -> None:
        self._hints: Dict[str, List[Hint]] = {}

    def store_hint(
        self,
        target_node_id: str,
        key: str,
        version: VersionedValue,
    ) -> None:
        """Stores a write hint for an offline node."""
        if target_node_id not in self._hints:
            self._hints[target_node_id] = []
        hint = Hint(target_node_id, key, version)
        self._hints[target_node_id].append(hint)

    def get_hints(self, target_node_id: str) -> List[Hint]:
        """Returns the current list of pending hints for a node."""
        return list(self._hints.get(target_node_id, []))

    def hint_count(self, target_node_id: Optional[str] = None) -> int:
        """Returns total or per-node pending hint count."""
        if target_node_id:
            return len(self._hints.get(target_node_id, []))
        return sum(len(hints) for hints in self._hints.values())

    def _apply_hints(
        self, target_replica: "QuorumReplica", hints: "List[Hint]"
    ) -> "tuple[int, List[Hint]]":
        applied = 0
        remaining: List[Hint] = []
        for hint in hints:
            if target_replica.put(hint.key, hint.version):
                applied += 1
            else:
                remaining.append(hint)
        return applied, remaining

    def flush_hints_for_node(self, target_replica: QuorumReplica) -> int:
        """
        Delivers all stored hints to the target replica if online and clears them.
        Returns the number of successfully applied hints.
        """
        if not target_replica.is_online:
            return 0
        target_id = target_replica.node_id
        hints = self._hints.get(target_id, [])
        if not hints:
            return 0
        applied_count, remaining = self._apply_hints(target_replica, hints)
        if remaining:
            self._hints[target_id] = remaining
        else:
            self._hints.pop(target_id, None)
        return applied_count
