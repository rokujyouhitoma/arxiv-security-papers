#!/usr/bin/env python3
"""tests/cli/commands/test_okf_convert.py

Unit tests for OkfConvertCommand conforming to DSN-01 Section 5.2 and Google OKF v0.2.
"""

import argparse
import io
import json
import os
from unittest.mock import patch

from src.cli.commands.okf_convert import (
    OkfConvertCommand,
    _build_okf_frontmatter,
    _convert_record,
    _normalize_paper_dict,
)


def test_normalize_paper_dict() -> None:
    rec = {
        "arxiv_id": "2401.1234",
        "title": "Quantum Safe Cryptography",
        "abstract": "Summary text",
    }
    norm = _normalize_paper_dict(rec)
    assert norm["arxiv_id"] == "2401.1234"
    assert norm["clean_id"] == "2401.1234"
    assert norm["abs_url"] == "https://arxiv.org/abs/2401.1234"
    assert "title_ja" in norm


def test_build_okf_frontmatter() -> None:
    fm = _build_okf_frontmatter(
        title="Zero Trust Architecture",
        title_ja="ゼロトラストアーキテクチャ",
        desc="ゼロトラストの検証",
        resource="https://arxiv.org/abs/2401.5555",
        tags=["cs.CR", "zero-trust"],
        pub_date="2026-10-01",
    )
    assert 'type: "security-paper"' in fm
    assert 'title: "Zero Trust Architecture"' in fm
    assert 'title_ja: "ゼロトラストアーキテクチャ"' in fm
    assert 'resource: "https://arxiv.org/abs/2401.5555"' in fm
    assert '- "zero-trust"' in fm


def test_convert_record_and_save(tmp_path: str) -> None:
    save_dir = str(tmp_path)
    rec = {
        "arxiv_id": "2401.7777",
        "title": "Adversarial Machine Learning in Cloud",
        "abstract": "We evaluate evasion attacks against neural network classifiers.",
    }
    enriched, md_content = _convert_record(rec, save_dir=save_dir)
    assert enriched["arxiv_id"] == "2401.7777"
    assert "okf_yaml" in enriched
    assert "markdown_content" in enriched
    assert "title_ja" in enriched

    saved_file = os.path.join(save_dir, "2401.7777.md")
    assert os.path.isfile(saved_file)
    with open(saved_file, "r", encoding="utf-8") as f:
        content = f.read()
    assert 'type: "security-paper"' in content


def test_okf_convert_command_jsonl_pipeline() -> None:
    cmd = OkfConvertCommand()
    parser = argparse.ArgumentParser()
    cmd.add_arguments(parser)
    args = parser.parse_args(["-f", "jsonl"])

    input_jsonl = '{"arxiv_id": "2401.0001", "title": "Protocol Security", "abstract": "Protocol analysis"}\n'

    with patch("sys.stdin", io.StringIO(input_jsonl)):
        with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
            with patch("sys.stderr", new_callable=io.StringIO) as mock_stderr:
                code = cmd.handle(args)
                assert code == 0

                lines = mock_stdout.getvalue().strip().splitlines()
                assert len(lines) == 1
                rec = json.loads(lines[0])
                assert rec["arxiv_id"] == "2401.0001"
                assert "okf_yaml" in rec

                stderr_val = mock_stderr.getvalue()
                assert "[INFO]" in stderr_val
                assert "OKF conversion completed successfully." in stderr_val


def test_okf_convert_command_markdown_pipeline() -> None:
    cmd = OkfConvertCommand()
    parser = argparse.ArgumentParser()
    cmd.add_arguments(parser)
    args = parser.parse_args(["-f", "markdown"])

    input_jsonl = '{"arxiv_id": "2401.0002", "title": "Side Channel Attacks", "abstract": "Cache timing"}\n'

    with patch("sys.stdin", io.StringIO(input_jsonl)):
        with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
            with patch("sys.stderr", new_callable=io.StringIO) as mock_stderr:
                code = cmd.handle(args)
                assert code == 0

                output = mock_stdout.getvalue()
                assert 'type: "security-paper"' in output
                assert "Side Channel Attacks" in output
                assert "OKF conversion completed" in mock_stderr.getvalue()
