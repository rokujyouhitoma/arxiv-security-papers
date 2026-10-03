#!/usr/bin/env python3
"""tests/cli/test_stream_pipeline.py

End-to-End integration test suite for Unix stream pipeline.
Verifies seamless chaining across CLI commands:
fetch | pdf-extract | okf-convert | summarize | db-index
Conforms to DSN-01 Section 5.2 and REQ-FR-09.
"""

import argparse
import io
import json
import os
from unittest.mock import patch

from cli.commands.db_index import DbIndexCommand
from cli.commands.okf_convert import OkfConvertCommand
from cli.commands.pdf_extract import PdfExtractCommand
from cli.commands.summarize import SummarizeCommand


def _run_stage(cmd: object, args_list: list[str], input_str: str) -> tuple[int, str, str]:
    """Helper to execute a command with captured stdin, stdout, and stderr."""
    parser = argparse.ArgumentParser()
    getattr(cmd, "add_arguments")(parser)
    parsed = parser.parse_args(args_list)

    with patch("sys.stdin", io.StringIO(input_str)):
        with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
            with patch("sys.stderr", new_callable=io.StringIO) as mock_stderr:
                code = getattr(cmd, "handle")(parsed)
                return code, mock_stdout.getvalue(), mock_stderr.getvalue()


def test_full_stream_pipeline_integration(tmp_path: str) -> None:
    ws = str(tmp_path)
    initial_records = [
        {
            "arxiv_id": "2401.1001",
            "title": "Quantum Resistance in Cryptographic Protocols",
            "abstract": "We evaluate post-quantum lattice schemes against fault injection.",
            "authors": ["Alice", "Bob"],
            "categories": ["cs.CR"],
            "published": "2026-10-01",
        },
        {
            "arxiv_id": "2401.1002",
            "title": "Autonomous Threat Hunting via Graph Neural Networks",
            "abstract": "Graph embeddings enable zero-shot anomaly detection in cloud audit logs.",
            "authors": ["Charlie"],
            "categories": ["cs.CR"],
            "published": "2026-10-02",
        },
    ]
    input_jsonl = "\n".join([json.dumps(r) for r in initial_records]) + "\n"

    # Stage 1: pdf-extract
    pdf_cmd = PdfExtractCommand()
    c1, out1, err1 = _run_stage(pdf_cmd, ["--pdf-cache-dir", ws], input_jsonl)
    assert c1 == 0
    lines1 = out1.strip().splitlines()
    assert len(lines1) == 2
    rec1 = json.loads(lines1[0])
    assert "full_text" in rec1
    assert "extracted_at" in rec1

    # Stage 2: okf-convert
    okf_cmd = OkfConvertCommand()
    c2, out2, err2 = _run_stage(okf_cmd, ["-f", "jsonl"], out1)
    assert c2 == 0
    lines2 = out2.strip().splitlines()
    assert len(lines2) == 2
    rec2 = json.loads(lines2[0])
    assert "okf_yaml" in rec2
    assert 'type: "security-paper"' in rec2["okf_yaml"]

    # Stage 3: summarize
    sum_cmd = SummarizeCommand()
    c3, out3, err3 = _run_stage(sum_cmd, ["--style", "structured"], out2)
    assert c3 == 0
    lines3 = out3.strip().splitlines()
    assert len(lines3) == 2
    rec3 = json.loads(lines3[0])
    assert "summary_ja" in rec3
    assert "points_ja" in rec3

    # Stage 4: db-index (with passthrough)
    db_cmd = DbIndexCommand(workspace_dir=ws)
    c4, out4, err4 = _run_stage(db_cmd, ["-t", "db", "-p"], out3)
    assert c4 == 0
    lines4 = out4.strip().splitlines()
    assert len(lines4) == 2

    # Check catalog file was updated
    cat_path = os.path.join(ws, "outputs", "database", "papers_catalog.json")
    assert os.path.isfile(cat_path)
    with open(cat_path, "r", encoding="utf-8") as f:
        catalog = json.load(f)
    assert "2401.1001" in catalog
    assert "2401.1002" in catalog
    assert catalog["2401.1001"]["title"] == "Quantum Resistance in Cryptographic Protocols"


def test_stream_pipeline_error_tolerance() -> None:
    malformed_input = (
        '{"arxiv_id": "2401.0001", "title": "Valid Record"}\n'
        'NOT_A_VALID_JSON_LINE\n'
        '{"arxiv_id": "2401.0002", "title": "Second Valid Record"}\n'
    )
    okf_cmd = OkfConvertCommand()
    code, out, err = _run_stage(okf_cmd, ["-f", "jsonl", "--on-error", "skip"], malformed_input)
    assert code == 0
    lines = out.strip().splitlines()
    assert len(lines) == 2
    assert "Skipping malformed stream line" in err
