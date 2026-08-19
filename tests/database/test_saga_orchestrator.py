#!/usr/bin/env python3
"""
Unit and Integration Tests for Saga Orchestration Engine
and Backward Compensating Transactions.
"""

import os
import sys
import unittest
from typing import Any, Dict, List

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from database.distributed.saga import (
    SagaOrchestrator,
    SagaStatus,
    build_paper_pipeline_saga,
)


class TestSagaOrchestrator(unittest.TestCase):
    """Tests for the generic Saga state machine orchestrator."""

    def test_successful_saga_execution(self) -> None:
        saga = SagaOrchestrator("saga-1")
        execution_order: List[str] = []

        def step1(ctx: Dict[str, Any]) -> Dict[str, Any]:
            execution_order.append("T1")
            return {"step1_done": True, "count": ctx.get("count", 0) + 1}

        def step2(ctx: Dict[str, Any]) -> Dict[str, Any]:
            execution_order.append("T2")
            return {"step2_done": True, "count": ctx["count"] + 10}

        saga.add_step("step1", step1)
        saga.add_step("step2", step2)

        success = saga.execute({"count": 5})

        self.assertTrue(success)
        self.assertEqual(saga.status, SagaStatus.COMPLETED)
        self.assertEqual(execution_order, ["T1", "T2"])
        self.assertEqual(saga.context["count"], 16)
        self.assertTrue(saga.context["step1_done"])
        self.assertTrue(saga.context["step2_done"])

    def test_backward_compensation_on_failure(self) -> None:
        saga = SagaOrchestrator("saga-fail-test")
        events: List[str] = []

        def step1_action(ctx: Dict[str, Any]) -> Dict[str, Any]:
            events.append("T1")
            return {"t1": "ok"}

        def step1_comp(ctx: Dict[str, Any]) -> None:
            events.append("C1")

        def step2_action(ctx: Dict[str, Any]) -> Dict[str, Any]:
            events.append("T2")
            return {"t2": "ok"}

        def step2_comp(ctx: Dict[str, Any]) -> None:
            events.append("C2")

        def step3_action(ctx: Dict[str, Any]) -> Dict[str, Any]:
            events.append("T3")
            raise RuntimeError("Database constraint violation at T3")

        def step3_comp(ctx: Dict[str, Any]) -> None:
            events.append("C3")

        saga.add_step("step1", step1_action, step1_comp)
        saga.add_step("step2", step2_action, step2_comp)
        saga.add_step("step3", step3_action, step3_comp)

        success = saga.execute({})

        self.assertFalse(success)
        self.assertEqual(saga.status, SagaStatus.COMPENSATED)
        self.assertEqual(saga.compensated_steps, ["step2", "step1"])
        # Forward T1, T2, T3 -> Backward C2, C1 (T3 failed so C3 is not called)
        self.assertEqual(events, ["T1", "T2", "T3", "C2", "C1"])


class TestPaperPipelineSaga(unittest.TestCase):
    """Tests for the concrete Paper Processing Pipeline Saga."""

    def setUp(self) -> None:
        self.metadata_db: Dict[str, Any] = {}
        self.pdf_db: Dict[str, Any] = {}
        self.vector_db: Dict[str, Any] = {}

    def test_paper_pipeline_success(self) -> None:
        saga = build_paper_pipeline_saga(
            "saga-paper-101",
            self.metadata_db,
            self.pdf_db,
            self.vector_db,
        )

        success = saga.execute(
            {
                "paper_id": "2408.0001",
                "metadata": {"title": "Quantum Cryptography Security Analysis"},
            }
        )

        self.assertTrue(success)
        self.assertEqual(saga.status, SagaStatus.COMPLETED)
        self.assertIn("2408.0001", self.metadata_db)
        self.assertIn("2408.0001", self.pdf_db)
        self.assertIn("2408.0001", self.vector_db)

    def test_paper_pipeline_failure_compensates_all(self) -> None:
        saga = build_paper_pipeline_saga(
            "saga-paper-fail",
            self.metadata_db,
            self.pdf_db,
            self.vector_db,
        )

        success = saga.execute(
            {
                "paper_id": "2408.9999",
                "metadata": {"title": "Failing Vector Paper"},
                "fail_at": "build_vector",
            }
        )

        self.assertFalse(success)
        self.assertEqual(saga.status, SagaStatus.COMPENSATED)
        # All stores should be completely cleaned up by compensations C2, C1
        self.assertNotIn("2408.9999", self.metadata_db)
        self.assertNotIn("2408.9999", self.pdf_db)
        self.assertNotIn("2408.9999", self.vector_db)


if __name__ == "__main__":
    unittest.main()
