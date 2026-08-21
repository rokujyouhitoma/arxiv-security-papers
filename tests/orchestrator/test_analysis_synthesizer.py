"""Tests for Phase 4 AnalysisSynthesizer."""

from orchestrator.analysis.synthesizer import AnalysisSynthesizer
from orchestrator.contracts import IntelligencePhase, PhaseContext, PhaseStatus


def test_analysis_synthesizer_multi_tier_production() -> None:
    synth = AnalysisSynthesizer()
    processed = [
        {"id": "doc1", "title": "Paper 1", "topic": "crypto"},
        {"id": "doc2", "title": "Paper 2", "topic": "crypto"},
        {"id": "doc3", "title": "Paper 3", "topic": "network"},
    ]

    products = synth.synthesize_products(processed, cycle_id="cycle_042")
    assert len(products) == 3  # 1 Run Product + 2 Domain (crypto, network) products

    run_prod = [p for p in products if p.tier == "01_per_run"][0]
    assert run_prod.source_count == 3
    assert "crypto" in run_prod.topic_tags
    assert "network" in run_prod.topic_tags
    assert run_prod.confidence_score > 0.8

    crypto_prod = [p for p in products if p.topic_tags == ["crypto"]][0]
    assert crypto_prod.tier == "02_daily"
    assert crypto_prod.source_count == 2


def test_analysis_synthesizer_phase_execution_and_compensation() -> None:
    synth = AnalysisSynthesizer()
    ctx = PhaseContext(
        cycle_id="c_synth",
        workspace_dir="/tmp",
        processed_records=[{"id": "d1", "topic": "t1"}],
    )
    ctx = synth.execute(ctx)
    assert ctx.phase_statuses[IntelligencePhase.ANALYSIS] == PhaseStatus.COMPLETED
    assert len(ctx.products) >= 1

    synth.compensate(ctx)
    assert ctx.phase_statuses[IntelligencePhase.ANALYSIS] == PhaseStatus.COMPENSATED
    assert len(ctx.products) == 0
