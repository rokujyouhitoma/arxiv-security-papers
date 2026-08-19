#!/usr/bin/env python3
"""
Paper Ingestion Pipeline Saga Definition.
Orchestrates metadata registration, full-text extraction, and vector index generation
with automatic backward compensation.
"""

from typing import Any, Dict

from .orchestrator import SagaOrchestrator


def build_paper_pipeline_saga(
    saga_id: str,
    metadata_store: Dict[str, Any],
    pdf_store: Dict[str, Any],
    vector_store: Dict[str, Any],
) -> SagaOrchestrator:
    """
    Constructs an orchestration-based Saga for paper processing pipeline.
    """
    saga = SagaOrchestrator(saga_id)

    # --- Step 1: Register Paper Metadata ---
    def step1_action(ctx: Dict[str, Any]) -> Dict[str, Any]:
        paper_id = ctx["paper_id"]
        metadata_store[paper_id] = ctx.get("metadata", {})
        return {"metadata_registered": True}

    def step1_compensate(ctx: Dict[str, Any]) -> None:
        paper_id = ctx["paper_id"]
        metadata_store.pop(paper_id, None)

    saga.add_step("register_metadata", step1_action, step1_compensate)

    # --- Step 2: Extract Full-Text ---
    def step2_action(ctx: Dict[str, Any]) -> Dict[str, Any]:
        paper_id = ctx["paper_id"]
        if ctx.get("fail_at") == "extract_pdf":
            raise RuntimeError("PDF extraction corrupted / timeout")
        pdf_store[paper_id] = f"extracted_text_for_{paper_id}"
        return {"text_extracted": True}

    def step2_compensate(ctx: Dict[str, Any]) -> None:
        paper_id = ctx["paper_id"]
        pdf_store.pop(paper_id, None)

    saga.add_step("extract_pdf_text", step2_action, step2_compensate)

    # --- Step 3: Build Vector Embedding & Index ---
    def step3_action(ctx: Dict[str, Any]) -> Dict[str, Any]:
        paper_id = ctx["paper_id"]
        if ctx.get("fail_at") == "build_vector":
            raise RuntimeError("Vector embedding service unavailable")
        vector_store[paper_id] = [0.1, 0.2, 0.3, 0.4]
        return {"vector_indexed": True}

    def step3_compensate(ctx: Dict[str, Any]) -> None:
        paper_id = ctx["paper_id"]
        vector_store.pop(paper_id, None)

    saga.add_step("build_vector_index", step3_action, step3_compensate)

    return saga
