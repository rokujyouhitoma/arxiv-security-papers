"""Test suite for Hypothesis-Driven Autonomous Investigation & Verification Engine."""

from typing import Any, Dict, List

import pytest

from orchestrator.analysis.hypothesis_engine import HypothesisEngine
from orchestrator.analysis.synthesizer import AnalysisSynthesizer
from orchestrator.cli import main
from orchestrator.contracts import (
    Hypothesis,
    HypothesisStatus,
    IntelligencePhase,
    PhaseContext,
)


@pytest.fixture
def mock_records() -> List[Dict[str, Any]]:
    return [
        {
            "id": "2408.0001",
            "title": "Exploiting MCP Tools via Agent Privilege Escalation",
            "summary": (
                "We demonstrate unauthorized execution and privilege escalation attacks "
                "on Model Context Protocol servers."
            ),
            "topic": "LLM・AIセキュリティ",
            "tags": ["mcp", "agent", "tool use", "privilege escalation"],
        },
        {
            "id": "2408.0002",
            "title": "Practical Fault Injection on Kyber Hardware Implementations",
            "summary": (
                "We present a novel power analysis and side-channel leakage attack "
                "against post-quantum lattice cryptography."
            ),
            "topic": "耐量子暗号",
            "tags": ["pqc", "kyber", "side-channel", "fault injection"],
        },
        {
            "id": "2408.0003",
            "title": "Slopsquatting in AI Coding: Hallucinated Package Infiltration",
            "summary": (
                "A study on package hallucination and hallucinated package attacks "
                "that bypasses scanner checks."
            ),
            "topic": "サプライチェーンセキュリティ",
            "tags": ["slopsquatting", "package hallucination", "dependency"],
        },
    ]


def test_hypothesis_engine_registration_and_list(tmp_path) -> None:
    db_path = str(tmp_path / "hypo.json")
    engine = HypothesisEngine(storage_path=db_path)

    hypo = Hypothesis(
        hypo_id="hypo_test_1",
        statement="Test security proposition",
        target_topics=["zero-trust", "rbac"],
    )
    engine.register_hypothesis(hypo)

    retrieved = engine.get_hypothesis("hypo_test_1")
    assert retrieved is not None
    assert retrieved.statement == "Test security proposition"
    assert len(engine.list_hypotheses()) == 1


def test_hypothesis_engine_autonomous_formulation(tmp_path, mock_records) -> None:
    db_path = str(tmp_path / "hypo.json")
    engine = HypothesisEngine(storage_path=db_path)

    new_hypos = engine.formulate_hypotheses(mock_records)
    assert len(new_hypos) >= 2
    ids = [h.hypo_id for h in new_hypos]
    assert "hypo_llm_mcp" in ids
    assert "hypo_pqc_sidechannel" in ids


def test_hypothesis_engine_evidence_evaluation(tmp_path, mock_records) -> None:
    db_path = str(tmp_path / "hypo.json")
    engine = HypothesisEngine(storage_path=db_path)

    # 1. Formulate & Evaluate
    evaluated = engine.evaluate_all(mock_records)
    assert len(evaluated) >= 2

    # Check MCP hypothesis evidence
    mcp_hypo = engine.get_hypothesis("hypo_llm_mcp")
    assert mcp_hypo is not None
    assert len(mcp_hypo.supporting_evidence) >= 1
    assert mcp_hypo.confidence_score > 0.5
    assert mcp_hypo.status in [
        HypothesisStatus.INVESTIGATING,
        HypothesisStatus.SUPPORTED,
    ]


def test_hypothesis_engine_report_and_queries(tmp_path) -> None:
    engine = HypothesisEngine()
    hypo = Hypothesis(
        hypo_id="hypo_sample",
        statement="MCP servers lack sandboxing by default",
        target_topics=["mcp", "agent"],
        confidence_score=0.85,
        status=HypothesisStatus.SUPPORTED,
    )
    engine.register_hypothesis(hypo, save=False)

    report = engine.synthesize_hypothesis_report(hypo)
    assert "学術仮説検証レポート" in report
    assert "MCP servers lack sandboxing by default" in report
    assert "即時対策推奨" in report

    queries = engine.generate_investigation_queries(hypo)
    assert len(queries) == 4
    assert any("exploit proof of concept" in q for q in queries)


def test_hypothesis_engine_persistence(tmp_path, mock_records) -> None:
    db_path = str(tmp_path / "hypo.json")
    engine1 = HypothesisEngine(storage_path=db_path)
    engine1.evaluate_all(mock_records)

    # Reopen in new instance
    engine2 = HypothesisEngine(storage_path=db_path)
    assert len(engine2.list_hypotheses()) >= 2
    hypo = engine2.get_hypothesis("hypo_llm_mcp")
    assert hypo is not None
    assert len(hypo.supporting_evidence) >= 1


def test_analysis_synthesizer_integration(tmp_path, mock_records) -> None:
    db_path = str(tmp_path / "hypo.json")
    engine = HypothesisEngine(storage_path=db_path)
    synthesizer = AnalysisSynthesizer(hypothesis_engine=engine)

    ctx = PhaseContext(
        cycle_id="cycle_test_01",
        workspace_dir=str(tmp_path),
        processed_records=mock_records,
    )

    ctx = synthesizer.execute(ctx)
    assert ctx.phase_statuses[IntelligencePhase.ANALYSIS].value == "completed"
    assert len(ctx.hypotheses) >= 2
    assert len(ctx.products) >= 2

    # Check product summary includes hypothesis breakdown
    run_prod = next(p for p in ctx.products if p.tier == "01_per_run")
    assert "自律検証セキュリティ仮説動向" in run_prod.summary


def test_cli_hypothesis_commands(tmp_path, capsys) -> None:
    # 1. List empty
    code_list = main(["--workdir", str(tmp_path), "hypothesis", "list"])
    assert code_list == 0

    # 2. Add manual hypothesis
    code_add = main(
        [
            "--workdir",
            str(tmp_path),
            "hypothesis",
            "add",
            "--id",
            "hypo_custom_1",
            "--statement",
            "Quantum attacks bypass classical signatures",
            "--topics",
            "quantum,signatures",
        ]
    )
    assert code_add == 0

    # 3. Report
    capsys.readouterr()
    code_rep = main(
        [
            "--workdir",
            str(tmp_path),
            "hypothesis",
            "report",
            "--id",
            "hypo_custom_1",
        ]
    )
    assert code_rep == 0
    captured = capsys.readouterr()
    assert "学術仮説検証レポート" in captured.out
