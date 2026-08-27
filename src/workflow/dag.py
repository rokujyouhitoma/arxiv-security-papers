"""Directed Acyclic Graph (DAG) Task Orchestration Engine."""

from collections import deque
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Set


@dataclass
class TaskNode:
    """A single node within the DAG workflow graph."""

    task_id: str
    handler: Callable[[Dict[str, Any]], Dict[str, Any]]
    dependencies: Set[str] = field(default_factory=set)


class DAGWorkflowEngine:
    """Orchestrates task execution according to a topological dependency graph."""

    def __init__(self) -> None:
        self.nodes: Dict[str, TaskNode] = {}

    def add_node(
        self,
        task_id: str,
        handler: Callable[[Dict[str, Any]], Dict[str, Any]],
        dependencies: Optional[List[str]] = None,
    ) -> None:
        """Adds a task node with its declared dependencies."""
        deps = set(dependencies) if dependencies else set()
        self.nodes[task_id] = TaskNode(
            task_id=task_id, handler=handler, dependencies=deps
        )

    def _build_adj_and_in_degree(self) -> tuple[Dict[str, List[str]], Dict[str, int]]:
        """Builds adjacency list and in-degree mapping for DAG."""
        in_degree = {n_id: 0 for n_id in self.nodes}
        adj_list: Dict[str, List[str]] = {n_id: [] for n_id in self.nodes}

        for node_id, node in self.nodes.items():
            for dep in node.dependencies:
                if dep not in self.nodes:
                    raise ValueError(
                        f"Task '{node_id}' depends on undefined task '{dep}'"
                    )
                adj_list[dep].append(node_id)
                in_degree[node_id] += 1
        return adj_list, in_degree

    def _topological_sort(self) -> List[str]:
        """Calculates topological execution order using Kahn's algorithm."""
        adj_list, in_degree = self._build_adj_and_in_degree()
        queue: deque[str] = deque(
            [node_id for node_id, deg in in_degree.items() if deg == 0]
        )
        ordered: List[str] = []

        while queue:
            curr = queue.popleft()
            ordered.append(curr)
            for neighbor in adj_list[curr]:
                in_degree[neighbor] -= 1
                if in_degree[neighbor] == 0:
                    queue.append(neighbor)

        if len(ordered) != len(self.nodes):
            raise ValueError("Cycle detected in DAG workflow definition")

        return ordered

    def execute(self, initial_state: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Executes all DAG tasks in topological order, mutating shared context state."""
        state = dict(initial_state) if initial_state is not None else {}
        execution_order = self._topological_sort()

        for task_id in execution_order:
            node = self.nodes[task_id]
            result = node.handler(state)
            if isinstance(result, dict):
                state.update(result)

        return state
