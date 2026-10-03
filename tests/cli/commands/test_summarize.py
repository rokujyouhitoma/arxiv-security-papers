#!/usr/bin/env python3
"""tests/cli/commands/test_summarize.py

Unit tests for SummarizeCommand conforming to DSN-01 Section 5.2.
"""

import argparse
import io
import json
from unittest.mock import patch

from src.cli.commands.summarize import (
    SummarizeCommand,
    _enrich_summary,
    _resolve_paper_text,
    _resolve_title_ja,
)


def test_resolve_paper_text() -> None:
    assert _resolve_paper_text({"abstract": "Abs"}) == "Abs"
    assert _resolve_paper_text({"full_text": "Full"}) == "Full"
    assert _resolve_paper_text({"summary": "Sum"}) == "Sum"
    assert _resolve_paper_text({}) == ""


def test_resolve_title_ja() -> None:
    assert _resolve_title_ja({"title_ja": "既存タイトル"}, "Original") == "既存タイトル"
    translated = _resolve_title_ja({}, "Blockchain Security Protocols")
    assert isinstance(translated, str)
    assert len(translated) > 0


def test_enrich_summary_styles() -> None:
    rec = {
        "arxiv_id": "2401.0001",
        "title": "Quantum Resistance in Distributed Ledgers",
        "abstract": "We evaluate post-quantum signature schemes against classical side-channel attacks.",
    }
    exec_res = _enrich_summary(rec, style="executive")
    assert exec_res["arxiv_id"] == "2401.0001"
    assert "summary_ja" in exec_res
    assert "points_ja" in exec_res
    assert "threat" in exec_res["points_ja"]
    assert "proposal" in exec_res["points_ja"]
    assert "impact" in exec_res["points_ja"]
    assert "structured_summary" not in exec_res

    struct_res = _enrich_summary(rec, style="structured")
    assert "structured_summary" in struct_res
    assert "【課題】" in struct_res["structured_summary"]


def test_summarize_command_stream_pipeline() -> None:
    cmd = SummarizeCommand()
    parser = argparse.ArgumentParser()
    cmd.add_arguments(parser)
    args = parser.parse_args(["--style", "structured"])

    input_jsonl = (
        '{"arxiv_id": "2401.0001", "title": "Hardware Trojans", "abstract": "Chip security"}\n'
    )

    with patch("sys.stdin", io.StringIO(input_jsonl)):
        with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
            with patch("sys.stderr", new_callable=io.StringIO) as mock_stderr:
                code = cmd.handle(args)
                assert code == 0

                lines = mock_stdout.getvalue().strip().splitlines()
                assert len(lines) == 1
                rec = json.loads(lines[0])
                assert rec["arxiv_id"] == "2401.0001"
                assert "summary_ja" in rec
                assert "points_ja" in rec

                stderr_val = mock_stderr.getvalue()
                assert "[INFO]" in stderr_val
                assert "Successfully summarized 1 paper records." in stderr_val
