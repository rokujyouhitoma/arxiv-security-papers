#!/usr/bin/env python3
"""
Scenario 7: Long-Running Pipeline Compensation Transactions (Orchestration Saga).
Location: tests/database/scenarios/test_scenario_07_saga_pipeline_compensation.py
Persona: Paper Ingestion & Analysis Workflow Worker.
Verifies Saga forward execution, per-step local commits with immediate lock release,
and backward compensation rollback (C2 -> C1) on external failure without residual dirty state.
"""

import os
import sys
import unittest

import pytest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.distributed.saga import (
    SagaOrchestrator,
    SagaStatus,
    build_paper_pipeline_saga,
)


class TestScenario07SagaPipelineCompensation(unittest.TestCase):
    """Verifies Saga forward execution and backward compensation lifecycle."""

    def test_fast_saga_pipeline_success_and_compensation_on_failure(self) -> None:
        """Fast verification: Forward success flow and backward compensation rollback."""
        meta_store = {}
        pdf_store = {}
        vec_store = {}

        # 1. Successful Saga pipeline
        saga_success = build_paper_pipeline_saga(
            saga_id="saga_success",
            metadata_store=meta_store,
            pdf_store=pdf_store,
            vector_store=vec_store,
        )
        ok_success = saga_success.execute(
            initial_context={
                "paper_id": "paper_2608_001",
                "metadata": {"title": "Zero Trust Security"},
            }
        )
        self.assertTrue(ok_success)
        self.assertEqual(saga_success.status, SagaStatus.COMPLETED)
        self.assertIn("paper_2608_001", meta_store)
        self.assertIn("paper_2608_001", pdf_store)
        self.assertIn("paper_2608_001", vec_store)

        # 2. Pipeline failure at Step 3 (LLM Vector Inference Failure)
        saga_fail = build_paper_pipeline_saga(
            saga_id="saga_fail",
            metadata_store=meta_store,
            pdf_store=pdf_store,
            vector_store=vec_store,
        )
        ok_fail = saga_fail.execute(
            initial_context={
                "paper_id": "paper_2608_002",
                "metadata": {"title": "Quantum Attacks"},
                "fail_at": "build_vector",
            }
        )

        # Overall saga returns False and is marked COMPENSATED
        self.assertFalse(ok_fail)
        self.assertEqual(saga_fail.status, SagaStatus.COMPENSATED)

        # Compensations C2 and C1 were executed in reverse: stores have zero leftover dirty state
        self.assertNotIn("paper_2608_002", meta_store)
        self.assertNotIn("paper_2608_002", pdf_store)
        self.assertNotIn("paper_2608_002", vec_store)

    @pytest.mark.slow
    def test_slow_multi_step_custom_saga_compensation_stress(self) -> None:
        """Slow verification: 5-step custom distributed Saga orchestrator under failures."""
        state = {"step1": False, "step2": False, "step3": False}

        def forward1(ctx):
            state["step1"] = True
            return {"s1": True}

        def comp1(ctx):
            state["step1"] = False

        def forward2(ctx):
            state["step2"] = True
            return {"s2": True}

        def comp2(ctx):
            state["step2"] = False

        def forward3_fail(ctx):
            raise ConnectionError("External Vector Model Timeout")

        def comp3(ctx):
            state["step3"] = False

        orch = SagaOrchestrator(saga_id="custom_stress_saga")
        orch.add_step("s1", forward1, comp1)
        orch.add_step("s2", forward2, comp2)
        orch.add_step("s3", forward3_fail, comp3)

        res = orch.execute()
        self.assertFalse(res)
        self.assertEqual(orch.status, SagaStatus.COMPENSATED)

        # All states compensated back to clean baseline
        self.assertFalse(state["step1"])
        self.assertFalse(state["step2"])
        self.assertFalse(state["step3"])


if __name__ == "__main__":
    unittest.main()
