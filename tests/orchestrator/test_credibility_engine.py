"""Test suite for NATO STANAG 2022 Admiralty Credibility Scoring Engine."""

import pytest

from orchestrator.analysis.hypothesis_engine import HypothesisEngine
from orchestrator.cli import main
from orchestrator.contracts import IntelligencePhase, PhaseContext
from orchestrator.processing.credibility import (
    AdmiraltyCredibility,
    AdmiraltyEngine,
    AdmiraltyReliability,
)
from orchestrator.processing.processor import ProcessingCoordinator


def test_admiralty_source_reliability_evaluation() -> None:
    engine = AdmiraltyEngine()

    # Grade A: Top conference / official advisory
    rel_a1, _ = engine.evaluate_source(
        "nist_advisory", {"venue": "USENIX Security 2026"}
    )
    assert rel_a1 == AdmiraltyReliability.A

    rel_a2, _ = engine.evaluate_source("cert_advisory", {})
    assert rel_a2 == AdmiraltyReliability.A

    # Grade B: arXiv / IACR
    rel_b, _ = engine.evaluate_source("arxiv_spider", {})
    assert rel_b == AdmiraltyReliability.B

    # Grade C: GitHub PoC
    rel_c, _ = engine.evaluate_source("github_repo", {})
    assert rel_c == AdmiraltyReliability.C

    # Grade D: Blog
    rel_d, _ = engine.evaluate_source("tech_blog", {})
    assert rel_d == AdmiraltyReliability.D

    # Grade F: Unknown
    rel_f, _ = engine.evaluate_source("custom_feed_99", {})
    assert rel_f == AdmiraltyReliability.F


def test_admiralty_information_credibility_evaluation() -> None:
    engine = AdmiraltyEngine()

    # Level 1: CVE + CWE
    cred_1, _ = engine.evaluate_content(
        "Analysis of CVE-2026-12345 exploiting CWE-79 in web applications."
    )
    assert cred_1 == AdmiraltyCredibility.ONE

    # Level 2: Formal proof / theorem
    cred_2, _ = engine.evaluate_content(
        "We present a formal proof theorem showing reduction to lattice hardness."
    )
    assert cred_2 == AdmiraltyCredibility.TWO

    # Level 3: Empirical benchmark
    cred_3, _ = engine.evaluate_content(
        "Experimental evaluation on dataset showing 95% detection accuracy."
    )
    assert cred_3 == AdmiraltyCredibility.THREE

    # Level 6: Insufficient data
    cred_6, _ = engine.evaluate_content("Hello world security overview.")
    assert cred_6 == AdmiraltyCredibility.SIX


def test_admiralty_compound_scoring_and_rating() -> None:
    engine = AdmiraltyEngine()
    record = {
        "id": "sec_001",
        "title": "USENIX Study on CVE-2026-9999",
        "summary": "We analyze CVE-2026-9999 and CWE-1357 in agentic sandboxes.",
        "source": "cve_advisory",
        "metadata": {"venue": "USENIX Security"},
    }

    rating = engine.rate_record(record)
    assert rating.code == "A1"
    assert pytest.approx(rating.score, 0.01) == 1.0
    assert "情報源信頼性: [A]" in rating.justification
    assert "情報確実性: [1]" in rating.justification


def test_admiralty_matrix_markdown_generation() -> None:
    engine = AdmiraltyEngine()
    md = engine.generate_matrix_markdown()
    assert "NATO STANAG 2022 Admiralty 信憑性評価マトリクス" in md
    assert "完全な信頼性 (Completely Reliable)" in md
    assert "独立ソースにより確認済 (Confirmed)" in md


def test_processing_coordinator_admiralty_integration(tmp_path) -> None:
    proc = ProcessingCoordinator()
    raw = {
        "id": "2408.01234",
        "title": "Formal Verification of Post-Quantum Signatures",
        "summary": "We provide a formal proof theorem for ML-DSA constant-time implementation.",
        "source": "arxiv",
        "raw_text": "Full text with formal verification proofs.",
    }

    ctx = PhaseContext(
        cycle_id="cycle_01",
        workspace_dir=str(tmp_path),
        raw_records=[raw],
    )

    ctx = proc.execute(ctx)
    assert ctx.phase_statuses[IntelligencePhase.PROCESSING].value == "completed"
    assert len(ctx.processed_records) == 1
    rec = ctx.processed_records[0]

    assert rec["admiralty_code"] == "B2"
    assert rec["admiralty_score"] > 0.70
    assert 'admiralty_code: "B2"' in rec["okf_content"]
    assert "admiralty_justification:" in rec["okf_content"]


def test_hypothesis_engine_admiralty_weighting_integration(tmp_path) -> None:
    hypo_engine = HypothesisEngine(storage_path=str(tmp_path / "hypo.json"))

    # Records with different admiralty scores
    records = [
        {
            "id": "high_cred_doc",
            "title": "MCP Tool Abuse Privilege Escalation Proof",
            "summary": "We present unauthorized execution and privilege escalation attacks on MCP.",
            "source": "cert_advisory",
            "admiralty_score": 1.0,  # High credibility weight
        },
        {
            "id": "low_cred_doc",
            "title": "Untested ideas on MCP privilege escalation",
            "summary": "Speculative privilege escalation.",
            "source": "tech_blog",
            "admiralty_score": 0.16,  # Low credibility weight
        },
    ]

    evaluated = hypo_engine.evaluate_all(records)
    assert len(evaluated) >= 1
    mcp_hypo = hypo_engine.get_hypothesis("hypo_llm_mcp")
    assert mcp_hypo is not None

    supp_weights = [ev.relevance_score for ev in mcp_hypo.supporting_evidence]
    assert 1.0 in supp_weights
    assert 0.16 in supp_weights


def test_cli_credibility_commands(capsys) -> None:
    # 1. Matrix
    code_matrix = main(["credibility", "matrix"])
    assert code_matrix == 0
    captured = capsys.readouterr()
    assert "NATO STANAG 2022 Admiralty 信憑性評価マトリクス" in captured.out

    # 2. Rate text
    code_rate = main(
        [
            "credibility",
            "rate",
            "--text",
            "Detailed analysis of CVE-2026-8888 vulnerability exploiting CWE-79.",
            "--source",
            "cve_advisory",
        ]
    )
    assert code_rate == 0
    captured_rate = capsys.readouterr()
    assert "Admiralty Code    : [A1]" in captured_rate.out
