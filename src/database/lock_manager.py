#!/usr/bin/env python3
"""
Strict Two-Phase Locking (SS2PL) & Lock Manager Subsystem.
Implements multi-granularity resource locking (Shared, Exclusive, Intent),
lock compatibility matrix, and Wait-For Graph (WFG) deadlock detection.
"""

import enum
import threading
import time
from typing import Dict, List, Optional, Set, Tuple


class LockMode(enum.IntEnum):
    """Lock modes supported by the lock manager."""

    SHARED = 1  # S: Read Lock
    EXCLUSIVE = 2  # X: Write Lock
    INTENT_SHARED = 3  # IS: Intent Read
    INTENT_EXCLUSIVE = 4  # IX: Intent Write


# Lock compatibility matrix: (granted, requested) -> bool
_COMPATIBILITY_MATRIX: Dict[Tuple[LockMode, LockMode], bool] = {
    (LockMode.SHARED, LockMode.SHARED): True,
    (LockMode.SHARED, LockMode.EXCLUSIVE): False,
    (LockMode.SHARED, LockMode.INTENT_SHARED): True,
    (LockMode.SHARED, LockMode.INTENT_EXCLUSIVE): False,
    (LockMode.EXCLUSIVE, LockMode.SHARED): False,
    (LockMode.EXCLUSIVE, LockMode.EXCLUSIVE): False,
    (LockMode.EXCLUSIVE, LockMode.INTENT_SHARED): False,
    (LockMode.EXCLUSIVE, LockMode.INTENT_EXCLUSIVE): False,
    (LockMode.INTENT_SHARED, LockMode.SHARED): True,
    (LockMode.INTENT_SHARED, LockMode.EXCLUSIVE): False,
    (LockMode.INTENT_SHARED, LockMode.INTENT_SHARED): True,
    (LockMode.INTENT_SHARED, LockMode.INTENT_EXCLUSIVE): True,
    (LockMode.INTENT_EXCLUSIVE, LockMode.SHARED): False,
    (LockMode.INTENT_EXCLUSIVE, LockMode.EXCLUSIVE): False,
    (LockMode.INTENT_EXCLUSIVE, LockMode.INTENT_SHARED): True,
    (LockMode.INTENT_EXCLUSIVE, LockMode.INTENT_EXCLUSIVE): True,
}


def is_compatible(granted: LockMode, requested: LockMode) -> bool:
    """Returns True if the requested lock mode is compatible with granted mode."""
    return _COMPATIBILITY_MATRIX.get((granted, requested), False)


class DeadlockError(Exception):
    """Raised when a deadlock cycle is detected in the Wait-For Graph."""

    def __init__(self, cycle: List[int], victim_tx: int) -> None:
        self.cycle = cycle
        self.victim_tx = victim_tx
        super().__init__(
            f"Deadlock detected on cycle {cycle}; aborting victim Tx {victim_tx}"
        )


class WaitForGraph:
    """
    Directed Wait-For Graph (WFG) for transaction deadlock detection.
    Edge (T1 -> T2) indicates T1 is waiting for a lock held by T2.
    """

    def __init__(self) -> None:
        self._edges: Dict[int, Set[int]] = {}
        self._lock = threading.RLock()

    def add_edge(self, waiter_tx: int, holder_tx: int) -> None:
        """Adds a directed wait dependency from waiter to holder."""
        with self._lock:
            if waiter_tx == holder_tx:
                return
            if waiter_tx not in self._edges:
                self._edges[waiter_tx] = set()
            self._edges[waiter_tx].add(holder_tx)

    def remove_edge(self, waiter_tx: int, holder_tx: int) -> None:
        """Removes a wait dependency."""
        with self._lock:
            if waiter_tx in self._edges:
                self._edges[waiter_tx].discard(holder_tx)
                if not self._edges[waiter_tx]:
                    del self._edges[waiter_tx]

    def remove_tx(self, tx_id: int) -> None:
        """Removes all incoming and outgoing edges for a transaction."""
        with self._lock:
            self._edges.pop(tx_id, None)
            for waiter, holders in list(self._edges.items()):
                holders.discard(tx_id)
                if not holders:
                    del self._edges[waiter]

    def detect_cycle(self) -> Optional[List[int]]:
        """
        Detects directed cycles using Depth-First Search (DFS).
        Returns the cycle path [T1, T2, ..., T1] or None if acyclic.
        """
        with self._lock:
            visited: Set[int] = set()
            rec_stack: Set[int] = set()
            parent_map: Dict[int, int] = {}

            for node in list(self._edges.keys()):
                if node not in visited:
                    cycle = self._dfs_cycle(node, visited, rec_stack, parent_map)
                    if cycle:
                        return cycle
            return None

    def _dfs_cycle(
        self,
        node: int,
        visited: Set[int],
        rec_stack: Set[int],
        parent_map: Dict[int, int],
    ) -> Optional[List[int]]:
        visited.add(node)
        rec_stack.add(node)

        for neighbor in self._edges.get(node, set()):
            if neighbor not in visited:
                parent_map[neighbor] = node
                cycle = self._dfs_cycle(neighbor, visited, rec_stack, parent_map)
                if cycle:
                    return cycle
            elif neighbor in rec_stack:
                # Cycle found! Reconstruct path from neighbor back to node
                path = [neighbor]
                curr = node
                while curr != neighbor:
                    path.append(curr)
                    curr = parent_map.get(curr, neighbor)
                path.append(neighbor)
                path.reverse()
                return path

        rec_stack.remove(node)
        return None


class LockGrant:
    """Represents a granted lock on a resource."""

    def __init__(self, tx_id: int, mode: LockMode) -> None:
        self.tx_id = tx_id
        self.mode = mode

    def __repr__(self) -> str:
        return f"<LockGrant Tx={self.tx_id} Mode={self.mode.name}>"


class LockManager:
    """
    Coordinates multi-granularity resource locking with Strict Two-Phase Locking (SS2PL).
    Locks are retained until transaction completion (commit/rollback).
    """

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._cond = threading.Condition(self._lock)
        # resource_id -> List[LockGrant]
        self._grants: Dict[str, List[LockGrant]] = {}
        # tx_id -> Set[Tuple[resource_id, LockMode]]
        self._tx_locks: Dict[int, Set[Tuple[str, LockMode]]] = {}
        self.wait_for_graph = WaitForGraph()

    def acquire_lock(
        self,
        tx_id: int,
        resource_id: str,
        mode: LockMode,
        timeout: float = 2.0,
    ) -> bool:
        """
        Acquires a lock on a resource in accordance with SS2PL.
        Blocks if conflicting locks are held, detecting deadlocks via WFG.
        """
        start_time = time.time()
        with self._lock:
            # Check if this transaction already holds an equal or stronger lock
            if self._has_sufficient_lock(tx_id, resource_id, mode):
                return True

            while True:
                grants = self._grants.get(resource_id, [])
                conflicts = [
                    g
                    for g in grants
                    if not is_compatible(g.mode, mode) and g.tx_id != tx_id
                ]

                if not conflicts:
                    # Grant lock immediately
                    self._grant_lock(tx_id, resource_id, mode)
                    self.wait_for_graph.remove_tx(tx_id)
                    return True

                # Record wait dependencies in WFG
                for holder in conflicts:
                    self.wait_for_graph.add_edge(tx_id, holder.tx_id)

                # Check for deadlocks
                cycle = self.wait_for_graph.detect_cycle()
                if cycle:
                    # Deadlock detected! Abort current transaction as victim
                    self.wait_for_graph.remove_tx(tx_id)
                    raise DeadlockError(cycle=cycle, victim_tx=tx_id)

                # Wait for lock release or timeout
                elapsed = time.time() - start_time
                remaining = timeout - elapsed
                if remaining <= 0:
                    self.wait_for_graph.remove_tx(tx_id)
                    return False

                self._cond.wait(timeout=min(remaining, 0.1))

    def _has_sufficient_lock(
        self, tx_id: int, resource_id: str, mode: LockMode
    ) -> bool:
        """Checks if transaction already holds an identical or stronger lock."""
        for grant in self._grants.get(resource_id, []):
            if grant.tx_id == tx_id:
                if grant.mode == mode:
                    return True
                if grant.mode == LockMode.EXCLUSIVE:
                    return True  # Exclusive subsumes Shared
        return False

    def _grant_lock(self, tx_id: int, resource_id: str, mode: LockMode) -> None:
        """Records a granted lock."""
        if resource_id not in self._grants:
            self._grants[resource_id] = []
        self._grants[resource_id].append(LockGrant(tx_id, mode))

        if tx_id not in self._tx_locks:
            self._tx_locks[tx_id] = set()
        self._tx_locks[tx_id].add((resource_id, mode))

    def release_all_locks(self, tx_id: int) -> int:
        """
        Releases all locks held by a transaction (SS2PL commit/rollback phase).
        Wakes up waiting transactions.
        """
        with self._lock:
            locks = self._tx_locks.pop(tx_id, set())
            released_count = len(locks)

            for resource_id, _ in locks:
                if resource_id in self._grants:
                    self._grants[resource_id] = [
                        g for g in self._grants[resource_id] if g.tx_id != tx_id
                    ]
                    if not self._grants[resource_id]:
                        del self._grants[resource_id]

            self.wait_for_graph.remove_tx(tx_id)
            self._cond.notify_all()
            return released_count

    def is_locked(self, resource_id: str) -> bool:
        """Returns True if any transaction currently holds a lock on resource."""
        with self._lock:
            return bool(self._grants.get(resource_id))
