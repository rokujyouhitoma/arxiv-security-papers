#!/usr/bin/env python3
"""
Version Vector and Conflict Resolution Engine.
Handles concurrent updates across distributed replicas using LWW (Last-Write-Wins),
Sibling preservation (Dynamo/Riak style), and custom merge strategies.
"""

import enum
import time
from typing import Any, Callable, Dict, List, Optional

from .vector_clock import VectorClock


class ConflictResolutionStrategy(enum.Enum):
    """Strategies for resolving concurrent conflicts in distributed replicas."""

    LWW = "LastWriteWins"
    SIBLINGS = "Siblings"
    CUSTOM = "Custom"


class VersionedValue:
    """
    A container associating a data payload with its causal VectorClock
    and physical timestamp.
    """

    def __init__(
        self,
        value: Any,
        clock: Optional[VectorClock] = None,
        timestamp: Optional[float] = None,
    ) -> None:
        self.value = value
        self.clock = clock or VectorClock()
        self.timestamp = timestamp if timestamp is not None else time.time()

    def to_dict(self) -> Dict[str, Any]:
        """Serializes versioned value into dictionary."""
        return {
            "value": self.value,
            "clock": self.clock.to_dict(),
            "timestamp": self.timestamp,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "VersionedValue":
        """Deserializes versioned value from dictionary."""
        return cls(
            value=data.get("value"),
            clock=VectorClock.from_dict(data.get("clock", {})),
            timestamp=data.get("timestamp", 0.0),
        )

    def __repr__(self) -> str:
        return f"VersionedValue(value={self.value!r}, clock={self.clock!r}, ts={self.timestamp})"


def _is_dominated(v1: VersionedValue, versions: List[VersionedValue], idx: int) -> bool:
    return any(
        i != idx and v1.clock.happens_before(v.clock) for i, v in enumerate(versions)
    )


def _in_frontier(v1: VersionedValue, frontier: List[VersionedValue]) -> bool:
    return any(v1.clock.equals(e.clock) and v1.value == e.value for e in frontier)


def prune_dominated_versions(versions: List[VersionedValue]) -> List[VersionedValue]:
    """
    Removes versions that are causally preceded (happens_before) by any other version.
    Leaves only the concurrent frontier (un-dominated versions).
    """
    if len(versions) <= 1:
        return list(versions)
    frontier: List[VersionedValue] = []
    for i, v1 in enumerate(versions):
        if not _is_dominated(v1, versions, i) and not _in_frontier(v1, frontier):
            frontier.append(v1)
    return frontier


def _resolve_lww(frontier: List[VersionedValue]) -> List[VersionedValue]:
    lww_winner = max(frontier, key=lambda v: v.timestamp)
    merged_clock = frontier[0].clock
    for v in frontier[1:]:
        merged_clock = merged_clock.merge(v.clock)
    return [
        VersionedValue(
            value=lww_winner.value, clock=merged_clock, timestamp=lww_winner.timestamp
        )
    ]


def _apply_resolution_strategy(
    frontier: List[VersionedValue],
    strategy: ConflictResolutionStrategy,
    custom_merger: Optional[Callable[[List[VersionedValue]], VersionedValue]],
) -> List[VersionedValue]:
    if strategy == ConflictResolutionStrategy.LWW:
        return _resolve_lww(frontier)
    if strategy == ConflictResolutionStrategy.CUSTOM and custom_merger:
        return [custom_merger(frontier)]
    return frontier


def resolve_conflict(
    versions: List[VersionedValue],
    strategy: ConflictResolutionStrategy = ConflictResolutionStrategy.LWW,
    custom_merger: Optional[Callable[[List[VersionedValue]], VersionedValue]] = None,
) -> List[VersionedValue]:
    """
    Resolves concurrent versions into a unified version list.
    """
    if not versions:
        return []
    frontier = prune_dominated_versions(versions)
    if len(frontier) <= 1:
        return frontier
    return _apply_resolution_strategy(frontier, strategy, custom_merger)
