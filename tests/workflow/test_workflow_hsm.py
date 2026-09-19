"""Unit tests for Workflow, Saga, and Scheduler HSM lifecycle governance."""

from __future__ import annotations

import unittest
from typing import Any, Dict, List

from workflow.contracts import (
    EVENT_ABORT,
    EVENT_COMMIT,
    EVENT_COMMIT_ALL,
    EVENT_COMPLETE,
    EVENT_EXECUTE,
    EVENT_FAIL,
    EVENT_FAULT,
    EVENT_MAX_RETRIES,
    EVENT_RETRY,
    EVENT_SKIP,
    EVENT_START,
    build_saga_state_tree,
    build_scheduler_state_tree,
    build_task_state_tree,
)
from workflow.dag import DAGWorkflowEngine
from workflow.saga import PhaseProtocol, SagaCoordinator
from workflow.scheduler import WorkflowScheduler


class TestWorkflowHSM(unittest.TestCase):
    """Tests HSM tree transitions for DAG tasks, Saga transactions, and Scheduler."""

    def test_task_state_tree_transitions(self) -> None:
        """Verifies Task HSM transitions from PENDING through SUCCESS."""
        hsm = build_task_state_tree()
        self.assertEqual(hsm.current_state.name, "PENDING")
        self.assertEqual(hsm.current_state.get_path(), "OPERATIONAL.PENDING")

        self.assertTrue(hsm.send_event(EVENT_START))
        self.assertEqual(hsm.current_state.name, "PREPARING")

        self.assertTrue(hsm.send_event(EVENT_EXECUTE))
        self.assertEqual(hsm.current_state.name, "EXECUTING")

        self.assertTrue(hsm.send_event(EVENT_COMMIT))
        self.assertEqual(hsm.current_state.name, "COMMITTING")

        self.assertTrue(hsm.send_event(EVENT_COMPLETE))
        self.assertEqual(hsm.current_state.name, "SUCCESS")
        self.assertEqual(hsm.current_state.get_path(), "TERMINATED.SUCCESS")

    def test_task_state_tree_fault_and_retry(self) -> None:
        """Verifies Task HSM retry and failure escalation."""
        hsm = build_task_state_tree()
        hsm.send_event(EVENT_START)
        hsm.send_event(EVENT_EXECUTE)

        # Fault occurs -> RETRYING
        self.assertTrue(hsm.send_event(EVENT_FAULT))
        self.assertEqual(hsm.current_state.name, "RETRYING")

        # Retry back to PREPARING
        self.assertTrue(hsm.send_event(EVENT_RETRY))
        self.assertEqual(hsm.current_state.name, "PREPARING")

        # Exceed retries -> FAILED
        hsm.send_event(EVENT_FAULT)
        self.assertTrue(hsm.send_event(EVENT_MAX_RETRIES))
        self.assertEqual(hsm.current_state.name, "FAILED")

    def test_task_state_tree_skip_and_abort(self) -> None:
        """Verifies Task HSM skip and abort transitions."""
        hsm_skip = build_task_state_tree()
        self.assertTrue(hsm_skip.send_event(EVENT_SKIP))
        self.assertEqual(hsm_skip.current_state.name, "SKIPPED")

        hsm_abort = build_task_state_tree()
        self.assertTrue(hsm_abort.send_event(EVENT_ABORT))
        self.assertEqual(hsm_abort.current_state.name, "ABORTED")

    def test_dag_engine_hsm_task_execution(self) -> None:
        """Verifies DAG engine advances TaskNode HSM through full lifecycle."""
        dag = DAGWorkflowEngine()
        observed_states: List[str] = []

        def task_step(state: Dict[str, Any]) -> Dict[str, Any]:
            # Inspect HSM state inside the handler
            observed_states.append(dag.nodes["step_1"].hsm.current_state.name)
            return {"val": 42}

        dag.add_node("step_1", task_step)
        self.assertEqual(dag.nodes["step_1"].hsm.current_state.name, "PENDING")

        result = dag.execute({})
        self.assertEqual(result["val"], 42)
        self.assertEqual(observed_states, ["EXECUTING"])
        self.assertEqual(dag.nodes["step_1"].hsm.current_state.name, "SUCCESS")

    def test_dag_engine_hsm_task_failure(self) -> None:
        """Verifies DAG engine sets TaskNode HSM to FAILED on exception."""
        dag = DAGWorkflowEngine()

        def failing_task(state: Dict[str, Any]) -> Dict[str, Any]:
            raise RuntimeError("Task Crash")

        dag.add_node("fail_step", failing_task)
        with self.assertRaises(RuntimeError):
            dag.execute({})

        self.assertEqual(dag.nodes["fail_step"].hsm.current_state.name, "FAILED")

    def test_saga_coordinator_hsm_success_and_commit(self) -> None:
        """Verifies Saga HSM transitions across successful forward phases."""
        coordinator = SagaCoordinator()
        self.assertEqual(coordinator.hsm.current_state.name, "STEP_SUCCESS")

        class SimpleStep(PhaseProtocol):
            def execute(self, ctx: Any) -> Any:
                ctx["order"].append("exec")
                return ctx

            def compensate(self, ctx: Any) -> None:
                ctx["order"].append("comp")

        ctx: Dict[str, Any] = {"order": []}
        coordinator.execute_phase_safely(SimpleStep(), ctx)
        self.assertEqual(coordinator.hsm.current_state.name, "STEP_SUCCESS")

        coordinator.commit_all()
        self.assertEqual(coordinator.hsm.current_state.name, "COMMITTED")
        self.assertEqual(
            coordinator.hsm.current_state.get_path(), "TERMINATED.COMMITTED"
        )

    def test_saga_coordinator_hsm_compensation_flow(self) -> None:
        """Verifies Saga HSM transitions during reverse compensation."""
        coordinator = SagaCoordinator()

        class FailingStep(PhaseProtocol):
            def execute(self, ctx: Any) -> Any:
                ctx.setdefault("errors", []).append({"error": "Phase Error"})
                return ctx

            def compensate(self, ctx: Any) -> None:
                ctx["compensated"] = True

        ctx: Dict[str, Any] = {}
        coordinator.execute_phase_safely(FailingStep(), ctx)
        self.assertTrue(ctx.get("compensated"))
        self.assertEqual(coordinator.hsm.current_state.name, "ABORTED")

    def test_saga_coordinator_hsm_compensation_failure_trap(self) -> None:
        """Verifies Saga HSM transitions to ABORTED when compensation itself fails."""
        coordinator = SagaCoordinator()

        class BrokenCompensateStep(PhaseProtocol):
            def execute(self, ctx: Any) -> Any:
                return ctx

            def compensate(self, ctx: Any) -> None:
                raise RuntimeError("Compensate Error")

        ctx: Dict[str, Any] = {"errors": []}
        coordinator.execute_phase_safely(BrokenCompensateStep(), ctx)
        coordinator.compensate_all(ctx)
        self.assertEqual(coordinator.hsm.current_state.name, "ABORTED")
        self.assertTrue(any("compensation_error" in err for err in ctx["errors"]))

    def test_workflow_scheduler_hsm_lifecycle(self) -> None:
        """Verifies WorkflowScheduler HSM transitions between IDLE, DISPATCH, PAUSE, and STOP."""
        scheduler = WorkflowScheduler()
        self.assertEqual(scheduler.hsm.current_state.name, "IDLE")

        # Run due tasks -> DISPATCHING -> IDLE
        scheduler.run_due_tasks({})
        self.assertEqual(scheduler.hsm.current_state.name, "IDLE")

        # Pause -> BACKPRESSURE_PAUSED
        self.assertTrue(scheduler.pause("Queue saturated"))
        self.assertEqual(scheduler.hsm.current_state.name, "BACKPRESSURE_PAUSED")

        # Resume -> IDLE
        self.assertTrue(scheduler.resume())
        self.assertEqual(scheduler.hsm.current_state.name, "IDLE")

        # Stop -> DRAINING -> STOPPED
        self.assertTrue(scheduler.stop())
        self.assertEqual(scheduler.hsm.current_state.name, "STOPPED")
        self.assertEqual(scheduler.hsm.current_state.get_path(), "TERMINATED.STOPPED")

    def test_saga_state_tree_direct(self) -> None:
        """Verifies Saga HSM state tree direct instantiation and events."""
        hsm = build_saga_state_tree()
        self.assertEqual(hsm.current_state.name, "STEP_SUCCESS")
        self.assertTrue(hsm.send_event(EVENT_COMMIT_ALL))
        self.assertEqual(hsm.current_state.name, "COMMITTED")

    def test_scheduler_state_tree_direct(self) -> None:
        """Verifies Scheduler HSM state tree direct instantiation and failure event."""
        hsm = build_scheduler_state_tree()
        self.assertEqual(hsm.current_state.name, "IDLE")
        self.assertTrue(hsm.send_event(EVENT_FAIL))
        self.assertEqual(hsm.current_state.name, "FAILED")

    def test_scheduler_task_failure_tracking(self) -> None:
        """Verifies task status and error tracking on handler success and exception."""
        from workflow.scheduler import WorkflowScheduler

        scheduler = WorkflowScheduler()

        def succeeding_handler(ctx: dict) -> dict:
            return {"status": "ok"}

        def failing_handler(ctx: dict) -> dict:
            raise ValueError("Task computation fault")

        t1 = scheduler.register_task("t_success", 0.01, succeeding_handler)
        t2 = scheduler.register_task("t_failure", 0.01, failing_handler)

        self.assertEqual(t1.last_status, "IDLE")
        self.assertIsNone(t1.last_error)

        executed = scheduler.run_due_tasks()
        self.assertIn("t_success", executed)
        self.assertIn("t_failure", executed)

        self.assertEqual(t1.last_status, "SUCCESS")
        self.assertIsNone(t1.last_error)

        self.assertEqual(t2.last_status, "FAILED")
        self.assertIn("Task computation fault", t2.last_error or "")

        t2_dict = t2.to_dict()
        self.assertEqual(t2_dict["last_status"], "FAILED")
        self.assertEqual(t2_dict["last_error"], "Task computation fault")

    def test_scheduler_startup_execution_behavior(self) -> None:
        """Verifies run_on_startup and initial delay behavior (Issue 333)."""
        import os
        from unittest.mock import patch

        from workflow.scheduler import WorkflowScheduler
        from workflow.service import WorkflowService

        scheduler = WorkflowScheduler()

        def dummy_handler(ctx: dict) -> dict:
            return {"status": "ok"}

        # Default run_on_startup=True -> immediately due
        t_default = scheduler.register_task("t_default", 3600.0, dummy_handler)
        self.assertTrue(t_default.is_due())
        self.assertTrue(t_default.run_on_startup)

        # Explicit run_on_startup=False -> not due immediately
        t_deferred = scheduler.register_task(
            "t_deferred", 3600.0, dummy_handler, run_on_startup=False
        )
        self.assertFalse(t_deferred.is_due())
        self.assertFalse(t_deferred.run_on_startup)

        # WorkflowService respects run_on_startup=False constructor
        srv = WorkflowService(run_on_startup=False)
        srv.register_default_spider_tasks()
        self.assertFalse(srv.scheduler.tasks["spider_arxiv_6h"].is_due())

        # WorkflowService respects ARXIV_SPIDER_RUN_ON_STARTUP environment variable
        with patch.dict(os.environ, {"ARXIV_SPIDER_RUN_ON_STARTUP": "false"}):
            srv_env = WorkflowService()
            srv_env.register_default_spider_tasks()
            self.assertFalse(srv_env.scheduler.tasks["spider_arxiv_6h"].is_due())


if __name__ == "__main__":
    unittest.main()
