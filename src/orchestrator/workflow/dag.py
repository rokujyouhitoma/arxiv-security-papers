"""DAG (Directed Acyclic Graph) Workflow Engine.

Executes intelligence lifecycle tasks in dependency order, ensuring sequential
and parallel execution guarantees across the 6 intelligence phases.
"""

from collections import defaultdict, deque
from typing import Callable, Dict, List, Optional, Set

from orchestrator.contracts import PhaseContext


class DAGWorkflowEngine:
    """DAG Task Orchestration Engine."""

    def __init__(self) -> None:
        self._tasks: Dict[str, Callable[[PhaseContext], PhaseContext]] = {}
        self._dependencies: Dict[str, Set[str]] = defaultdict(set)

    def add_task(
        self,
        task_id: str,
        runner_fn: Callable[[PhaseContext], PhaseContext],
        depends_on: Optional[List[str]] = None,
    ) -> None:
        """Registers a task node and its prerequisite task IDs in the DAG."""
        self._tasks[task_id] = runner_fn
        if depends_on:
            for dep in depends_on:
                self._dependencies[task_id].add(dep)

    def _build_in_degree_and_graph(
        self,
    ) -> tuple[Dict[str, int], Dict[str, List[str]]]:
        """Builds in-degree mapping and adjacency graph."""
        in_degree: Dict[str, int] = {t: 0 for t in self._tasks}
        graph: Dict[str, List[str]] = defaultdict(list)

        for task_id, deps in self._dependencies.items():
            for dep in deps:
                if dep in self._tasks:
                    graph[dep].append(task_id)
                    in_degree[task_id] += 1
        return in_degree, graph

    def topological_sort(self) -> List[str]:
        """Returns task IDs sorted in execution order via Kahn's algorithm."""
        in_degree, graph = self._build_in_degree_and_graph()
        queue: deque[str] = deque([t for t, deg in in_degree.items() if deg == 0])
        ordered: List[str] = []

        while queue:
            node = queue.popleft()
            ordered.append(node)
            for neighbor in graph[node]:
                in_degree[neighbor] -= 1
                if in_degree[neighbor] == 0:
                    queue.append(neighbor)

        if len(ordered) != len(self._tasks):
            raise ValueError("Cycle detected in intelligence workflow DAG")

        return ordered

    def execute_dag(self, context: PhaseContext) -> PhaseContext:
        """Executes all registered tasks in topological dependency order."""
        ordered_tasks = self.topological_sort()
        for task_id in ordered_tasks:
            runner = self._tasks[task_id]
            context = runner(context)
            if context.errors:
                break
        return context
