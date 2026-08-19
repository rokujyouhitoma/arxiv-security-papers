#!/usr/bin/env python3
"""
Conflict-free Replicated Data Types (CRDTs).
State-based (CvRDT) implementations enabling convergent, commutative,
associative, and idempotent replication without centralized coordination.
"""

import uuid
from typing import Any, Dict, Generic, Optional, Set, Tuple, TypeVar

T = TypeVar("T")


class PNCounter:
    """
    Positive-Negative Counter (PN-Counter) CRDT.
    Supports increments and decrements across multiple replica nodes.
    """

    def __init__(
        self,
        p_counts: Optional[Dict[str, int]] = None,
        n_counts: Optional[Dict[str, int]] = None,
    ) -> None:
        self._p: Dict[str, int] = dict(p_counts or {})
        self._n: Dict[str, int] = dict(n_counts or {})

    def increment(self, node_id: str, delta: int = 1) -> None:
        """Increments the positive counter for a specific node."""
        if delta < 0:
            raise ValueError("Increment delta must be non-negative")
        self._p[node_id] = self._p.get(node_id, 0) + delta

    def decrement(self, node_id: str, delta: int = 1) -> None:
        """Increments the negative counter for a specific node."""
        if delta < 0:
            raise ValueError("Decrement delta must be non-negative")
        self._n[node_id] = self._n.get(node_id, 0) + delta

    @property
    def value(self) -> int:
        """Returns the converged net counter value."""
        pos = sum(self._p.values())
        neg = sum(self._n.values())
        return pos - neg

    def merge(self, other: "PNCounter") -> "PNCounter":
        """
        Merges two PN-Counters via component-wise maximum (Join-Semilattice).
        """
        all_p_nodes = set(self._p.keys()) | set(other._p.keys())
        merged_p = {n: max(self._p.get(n, 0), other._p.get(n, 0)) for n in all_p_nodes}

        all_n_nodes = set(self._n.keys()) | set(other._n.keys())
        merged_n = {n: max(self._n.get(n, 0), other._n.get(n, 0)) for n in all_n_nodes}

        return PNCounter(merged_p, merged_n)

    def to_dict(self) -> Dict[str, Any]:
        """Serializes counter state into dictionary."""
        return {"p": dict(self._p), "n": dict(self._n)}

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "PNCounter":
        """Deserializes counter state from dictionary."""
        return cls(data.get("p", {}), data.get("n", {}))

    def __repr__(self) -> str:
        return f"PNCounter(value={self.value}, p={self._p}, n={self._n})"


class ORSet(Generic[T]):
    """
    Observed-Remove Set (OR-Set / Add-Wins Set) CRDT.
    Supports concurrent additions and removals with automatic convergence.
    """

    def __init__(
        self,
        add_set: Optional[Set[Tuple[T, str]]] = None,
        remove_set: Optional[Set[Tuple[T, str]]] = None,
    ) -> None:
        self._add_set: Set[Tuple[T, str]] = set(add_set or set())
        self._remove_set: Set[Tuple[T, str]] = set(remove_set or set())

    def add(self, elem: T) -> str:
        """
        Adds an element with a unique tag and returns the tag.
        """
        tag = uuid.uuid4().hex
        self._add_set.add((elem, tag))
        return tag

    def remove(self, elem: T) -> None:
        """
        Removes all observed instances of an element by adding their tags to remove_set.
        """
        observed_tags = {tag for (e, tag) in self._add_set if e == elem}
        for tag in observed_tags:
            self._remove_set.add((elem, tag))

    def read(self) -> Set[T]:
        """Returns active elements present in add_set but not in remove_set."""
        return {
            elem for (elem, tag) in self._add_set if (elem, tag) not in self._remove_set
        }

    def merge(self, other: "ORSet[T]") -> "ORSet[T]":
        """
        Merges two OR-Sets via set union of add_set and remove_set.
        """
        merged_add = self._add_set | other._add_set
        merged_remove = self._remove_set | other._remove_set
        return ORSet(merged_add, merged_remove)

    def __contains__(self, elem: T) -> bool:
        return elem in self.read()

    def __len__(self) -> int:
        return len(self.read())

    def __repr__(self) -> str:
        return f"ORSet({list(self.read())})"
