"""
Unit tests for the Transformer layer (translation, security domain & threat tagging, OKF serialization).
"""

import json
import os
import tempfile
from typing import Any, Dict

from pipeline.transformer import (
    build_okf_from_raw,
    classify_domain,
    determine_security_tags,
    extract_mitre_and_stride,
    translate_title_ja,
)


def test_translate_title_ja():
    title1 = (
        "TeleGapper: On the (un)reliability of Privacy Policies in Telegram Mini apps"
    )
    assert "Telegram" in translate_title_ja(title1)

    title2 = "Vulnerability Detection in Autonomous Vehicles"
    ja2 = translate_title_ja(title2)
    assert "脆弱性検出" in ja2 or "自動運転車両" in ja2


def test_classify_domain():
    paper_ai = {
        "title": "Adversarial Prompt Injection in LLM Agents",
        "summary": "Attacking agent memory and RAG frameworks.",
        "categories": ["cs.CR", "cs.AI"],
    }
    assert classify_domain(paper_ai) == "AI/ML Security"

    paper_crypto = {
        "title": "Lattice-Based Zero-Knowledge Signatures",
        "summary": "Post-quantum encryption schemes.",
        "categories": ["cs.CR"],
    }
    assert classify_domain(paper_crypto) == "Cryptography"


def test_determine_security_tags():
    paper = {
        "title": "Fuzzing Python Bytecode to Discover Malware Vulnerability",
        "summary": "Crash reproduction in VM bytecode.",
        "categories": ["cs.CR"],
    }
    tags = determine_security_tags(paper)
    assert "Software Security" in tags
    assert "fuzzing" in tags or "malware-analysis" in tags


def test_extract_mitre_and_stride():
    paper = {
        "title": "Phishing and Credential Stuffing in Cloud Portals",
        "summary": "Denial of service and data tampering in API gateways.",
    }
    threats = extract_mitre_and_stride(paper)
    assert "T1566" in threats["mitre_attack"] or "T1078" in threats["mitre_attack"]
    assert "Denial of Service" in threats["stride"] or "Tampering" in threats["stride"]


def test_extract_mitre_and_stride_custom_extractor():
    paper = {"title": "Generic Test Paper", "summary": "Sample abstract."}

    def dummy_extractor(text: str):
        return (["T9999_CUSTOM"], ["CustomThreat"])

    custom_res = extract_mitre_and_stride(paper, custom_extractor=dummy_extractor)
    assert custom_res["mitre_attack"] == ["T9999_CUSTOM"]
    assert custom_res["stride"] == ["CustomThreat"]


def test_build_okf_from_raw():
    with tempfile.TemporaryDirectory() as tmpdir:
        config = {
            "paths": {
                "raw_data_dir": "outputs/raw_data",
                "okf_papers_dir": "outputs/okf_papers",
                "templates_dir": "templates",
            },
            "okf": {
                "default_tags": ["cs.CR", "security"],
            },
        }

        # Prepare dummy raw meta
        raw_day_dir = os.path.join(tmpdir, "outputs/raw_data/2026-08-17")
        os.makedirs(raw_day_dir, exist_ok=True)
        raw_meta_path = os.path.join(raw_day_dir, "2608.11111_meta.json")

        paper_data = {
            "arxiv_id": "2608.11111v1",
            "clean_id": "2608.11111",
            "title": "Securing QUIC Against Delay Attacks in IoT Networks",
            "summary": "We analyze latency constraints and proposing cryptographic defenses.",
            "published": "2026-08-17T12:00:00Z",
            "authors": ["David Lee"],
            "abs_url": "https://arxiv.org/abs/2608.11111",
            "pdf_url": "https://arxiv.org/pdf/2608.11111.pdf",
            "primary_category": "cs.CR",
            "categories": ["cs.CR", "cs.NI"],
        }
        with open(raw_meta_path, "w", encoding="utf-8") as f:
            json.dump(paper_data, f)

        # Execute transformation
        result = build_okf_from_raw(raw_meta_path, tmpdir, config)
        assert os.path.exists(result["okf_path"])
        assert result["date_str"] == "2026-08-17"

        with open(result["okf_path"], "r", encoding="utf-8") as f:
            okf_content = f.read()

        assert 'type: "security-paper"' in okf_content
        assert "Securing QUIC Against Delay Attacks in IoT Networks" in okf_content
        assert "エグゼクティブサマリー" in okf_content


def test_transform_and_save_okf_progress_and_error_handling(capsys: Any) -> None:
    from unittest.mock import patch

    from pipeline.arxiv_okf_fetcher import _transform_and_save_okf

    with tempfile.TemporaryDirectory() as tmpdir:
        config = {
            "paths": {
                "okf_papers_dir": "outputs/okf/papers",
                "state_file": "outputs/database/papers_catalog.json",
            }
        }
        os.makedirs(os.path.join(tmpdir, "outputs", "database"), exist_ok=True)
        state_path = os.path.join(tmpdir, "outputs", "database", "papers_catalog.json")
        processed_state: Dict[str, Any] = {}

        tasks = [
            (
                {
                    "arxiv_id": "2608.11111v1",
                    "clean_id": "2608.11111",
                    "title": "Paper 1",
                },
                tmpdir,
                "meta1.json",
            ),
            (
                {
                    "arxiv_id": "2608.22222v1",
                    "clean_id": "2608.22222",
                    "title": "Paper 2",
                },
                tmpdir,
                "meta2.json",
            ),
        ]

        # First paper succeeds, second paper raises exception
        def mock_build(meta_path: str, ws: str, cfg: Dict[str, Any]) -> Dict[str, Any]:
            if "meta2.json" in meta_path:
                raise ValueError("Corrupt metadata payload")
            return {
                "rel_okf_path": "outputs/okf/papers/2026-08-17/2608.11111.md",
                "title_ja": "論文1",
            }

        with patch(
            "pipeline.arxiv_okf_fetcher.build_okf_from_raw", side_effect=mock_build
        ):
            with patch("pipeline.arxiv_okf_fetcher._ingest_items_into_knowledge_graph"):
                results = _transform_and_save_okf(
                    tasks, tmpdir, config, processed_state, state_path
                )

        assert len(results) == 1
        assert "2608.11111v1" in processed_state
        assert "2608.22222v1" not in processed_state

        captured = capsys.readouterr().out
        assert (
            "[ETL:Transformation] Starting OKF v0.2 Markdown generation for 2 papers"
            in captured
        )
        assert "[OKF:Transformer]" in captured
        assert "( 50.0%)" in captured
        assert "Paper: 2608.11111" in captured
        assert "[OK]" in captured
        assert "(100.0%)" in captured
        assert "Paper: 2608.22222" in captured
        assert "[ERROR: Corrupt metadata payload]" in captured
        assert "Finished OKF transformation for 2 papers" in captured
        assert "(OK: 1/2, Error: 1/2)" in captured
