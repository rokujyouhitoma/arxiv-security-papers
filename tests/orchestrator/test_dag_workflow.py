"""Tests for DAGWorkflowEngine."""

import pytest

from orchestrator.contracts import PhaseContext
from orchestrator.workflow.dag import DAGWorkflowEngine


def test_dag_workflow_topological_execution() -> None:
    engine = DAGWorkflowEngine()
    execution_order: list = []

    def task_a(ctx: PhaseContext) -> PhaseContext:
        execution_order.append("A")
        return ctx

    def task_b(ctx: PhaseContext) -> PhaseContext:
        execution_order.append("B")
        return ctx

    def task_c(ctx: PhaseContext) -> PhaseContext:
        execution_order.append("C")
        return ctx

    # C depends on B, B depends on A
    engine.add_task("task_a", task_a)
    engine.add_task("task_b", task_b, depends_on=["task_a"])
    engine.add_task("task_c", task_c, depends_on=["task_b"])

    ctx = PhaseContext(cycle_id="c_dag", workspace_dir="/tmp")
    ctx = engine.execute_dag(ctx)

    assert execution_order == ["A", "B", "C"]


def test_dag_workflow_cycle_detection() -> None:
    engine = DAGWorkflowEngine()
    engine.add_task("t1", lambda c: c, depends_on=["t2"])
    engine.add_task("t2", lambda c: c, depends_on=["t1"])

    with pytest.raises(ValueError, match="Cycle detected"):
        engine.topological_sort()
