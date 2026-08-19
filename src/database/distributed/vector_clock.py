#!/usr/bin/env python3
"""
Vector Clock Logical Timestamp Engine for Distributed Causal Consistency.
Tracks causality between events across distributed nodes and detects concurrent conflicts.
"""

import json
from typing import Any, Dict, Optional, Set


class VectorClock:
    """
    Vector Clock representation managing per-node counters {node_id: counter}.
    """

    def __init__(self, clock: Optional[Dict[str, int]] = None) -> None:
        self._clock: Dict[str, int] = {}
        if clock:
            for k, v in clock.items():
                if v > 0:
                    self._clock[k] = int(v)

    def get(self, node_id: str) -> int:
        """Returns the clock value for the given node."""
        return self._clock.get(node_id, 0)

    def increment(self, node_id: str) -> "VectorClock":
        """
        Increments the counter for node_id and returns a new VectorClock instance.
        """
        new_clock = dict(self._clock)
        new_clock[node_id] = new_clock.get(node_id, 0) + 1
        return VectorClock(new_clock)

    def update(self, node_id: str, other: "VectorClock") -> "VectorClock":
        """
        Merges with other clock and increments node_id counter.
        C_recv = max(C_local, C_msg) with C_recv[node_id] + 1
        """
        merged = self.merge(other)
        return merged.increment(node_id)

    def merge(self, other: "VectorClock") -> "VectorClock":
        """
        Returns a new VectorClock containing the maximum component-wise values.
        """
        all_nodes: Set[str] = set(self._clock.keys()) | set(other._clock.keys())
        merged_clock: Dict[str, int] = {}
        for n in all_nodes:
            max_val = max(self.get(n), other.get(n))
            if max_val > 0:
                merged_clock[n] = max_val
        return VectorClock(merged_clock)

    def happens_before(self, other: "VectorClock") -> bool:
        """
        Determines if self causally precedes other (self < other).
        True iff for all k: self[k] <= other[k] and exists k: self[k] < other[k].
        """
        all_nodes = set(self._clock.keys()) | set(other._clock.keys())
        has_strict_less = False

        for n in all_nodes:
            v_self = self.get(n)
            v_other = other.get(n)
            if v_self > v_other:
                return False
            if v_self < v_other:
                has_strict_less = True

        return has_strict_less

    def happens_after(self, other: "VectorClock") -> bool:
        """Determines if self causally succeeds other (self > other)."""
        return other.happens_before(self)

    def equals(self, other: "VectorClock") -> bool:
        """Checks if two vector clocks have identical counters."""
        all_nodes = set(self._clock.keys()) | set(other._clock.keys())
        return all(self.get(n) == other.get(n) for n in all_nodes)

    def is_concurrent_with(self, other: "VectorClock") -> bool:
        """
        Determines if self and other are concurrent (conflict / no causal relation).
        True iff neither happens before the other and they are not equal.
        """
        if self.equals(other):
            return False
        return not self.happens_before(other) and not other.happens_before(self)

    def to_dict(self) -> Dict[str, int]:
        """Serializes vector clock into dictionary."""
        return dict(self._clock)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "VectorClock":
        """Deserializes vector clock from dictionary."""
        return cls({str(k): int(v) for k, v in data.items()})

    def to_json(self) -> str:
        """Serializes vector clock into JSON string."""
        return json.dumps(self._clock, sort_keys=True)

    @classmethod
    def from_json(cls, json_str: str) -> "VectorClock":
        """Deserializes vector clock from JSON string."""
        data = json.loads(json_str)
        return cls.from_dict(data)

    def __repr__(self) -> str:
        return f"VectorClock({self._clock})"

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, VectorClock):
            return False
        return self.equals(other)
