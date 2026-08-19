#!/usr/bin/env python3
"""
Distributed Deadlock Detector.
Maintains a distributed Wait-For Graph (WFG), detects dependency cycles via DFS,
and selects victim transactions for resolution.
"""

from typing import Dict, List, Optional, Set


class DistributedDeadlockDetector:
    """
    Tracks transaction wait-for dependencies and detects cycles.
    """

    def __init__(self) -> None:
        # waiter_tx -> set of holder_txs it is waiting on
        self.wait_graph: Dict[str, Set[str]] = {}

    def add_wait_edge(self, waiter_tx: str, holder_tx: str) -> None:
        """Adds a dependency indicating waiter_tx is waiting for holder_tx."""
        if waiter_tx == holder_tx:
            return
        if waiter_tx not in self.wait_graph:
            self.wait_graph[waiter_tx] = set()
        self.wait_graph[waiter_tx].add(holder_tx)

    def remove_wait_edge(self, waiter_tx: str, holder_tx: str) -> None:
        """Removes a dependency between waiter_tx and holder_tx."""
        if waiter_tx in self.wait_graph:
            self.wait_graph[waiter_tx].discard(holder_tx)
            if not self.wait_graph[waiter_tx]:
                del self.wait_graph[waiter_tx]

    def clear_tx(self, tx_id: str) -> None:
        """Removes all incoming and outgoing edges for the given transaction."""
        self.wait_graph.pop(tx_id, None)
        for waiter in list(self.wait_graph.keys()):
            self.wait_graph[waiter].discard(tx_id)
            if not self.wait_graph[waiter]:
                del self.wait_graph[waiter]

    def detect_cycle(self) -> Optional[List[str]]:
        """
        Detects cycles in the Wait-For Graph using Depth-First Search.
        Returns a list of transaction IDs forming a cycle if detected, else None.
        """
        visited: Set[str] = set()
        recursion_stack: List[str] = []
        stack_set: Set[str] = set()

        def _dfs(node: str) -> Optional[List[str]]:
            visited.add(node)
            recursion_stack.append(node)
            stack_set.add(node)

            for neighbor in self.wait_graph.get(node, set()):
                if neighbor not in visited:
                    res = _dfs(neighbor)
                    if res is not None:
                        return res
                elif neighbor in stack_set:
                    # Cycle detected: extract subpath from neighbor to current
                    idx = recursion_stack.index(neighbor)
                    return recursion_stack[idx:] + [neighbor]

            recursion_stack.pop()
            stack_set.remove(node)
            return None

        for node in list(self.wait_graph.keys()):
            if node not in visited:
                cycle = _dfs(node)
                if cycle is not None:
                    return cycle

        return None

    def select_victim(self, cycle: Optional[List[str]] = None) -> Optional[str]:
        """
        Selects a victim transaction from the cycle to abort and break the deadlock.
        Defaults to the lexicographically last transaction ID in the cycle.
        """
        detected_cycle = cycle if cycle is not None else self.detect_cycle()
        if not detected_cycle:
            return None
        # Exclude the duplicate closing element in cycle representation
        unique_txs = list(set(detected_cycle))
        unique_txs.sort()
        return unique_txs[-1]
