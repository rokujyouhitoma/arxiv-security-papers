#!/usr/bin/env python3
"""
Distributed Coordination and Consensus Subsystem.
Exports VectorClock, VersionedValue, and conflict resolution strategies.
"""

from .vector_clock import VectorClock
from .version_vector import (
    ConflictResolutionStrategy,
    VersionedValue,
    prune_dominated_versions,
    resolve_conflict,
)

__all__ = [
    "VectorClock",
    "VersionedValue",
    "ConflictResolutionStrategy",
    "resolve_conflict",
    "prune_dominated_versions",
]
