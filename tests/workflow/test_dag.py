"""Unit tests for Topological DAG Workflow Engine."""

import pytest

from workflow.dag import DAGWorkflowEngine


def test_dag_workflow_topological_execution() -> None:
    dag = DAGWorkflowEngine()

    def task_a(state: dict) -> dict:
        return {"a": 1}

    def task_b(state: dict) -> dict:
        return {"b": state.get("a", 0) + 2}

    def task_c(state: dict) -> dict:
        return {"c": state.get("b", 0) * 3}

    dag.add_node("task_c", task_c, dependencies=["task_b"])
    dag.add_node("task_a", task_a)
    dag.add_node("task_b", task_b, dependencies=["task_a"])

    final_state = dag.execute()
    assert final_state["a"] == 1
    assert final_state["b"] == 3
    assert final_state["c"] == 9


def test_dag_workflow_cycle_detection() -> None:
    dag = DAGWorkflowEngine()
    dag.add_node("a", lambda s: {}, dependencies=["b"])
    dag.add_node("b", lambda s: {}, dependencies=["a"])

    with pytest.raises(ValueError, match="Cycle detected"):
        dag.execute()
