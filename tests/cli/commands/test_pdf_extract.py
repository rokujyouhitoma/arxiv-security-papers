#!/usr/bin/env python3
"""tests/cli/commands/test_pdf_extract.py

Unit tests for PdfExtractCommand conforming to DSN-01 Section 5.2.
"""

import argparse
import io
import json
from unittest.mock import patch

from src.cli.commands.pdf_extract import (
    PdfExtractCommand,
    _process_single_record,
    _resolve_cached_pdf,
)
from src.cli.stream import DiagnosticLogger


def test_resolve_cached_pdf(tmp_path: str) -> None:
    path_str = str(tmp_path)
    res = _resolve_cached_pdf(path_str, "2401.12345")
    assert res is None


def test_process_single_record_fallback() -> None:
    logger = DiagnosticLogger(stream=io.StringIO())
    rec = {
        "arxiv_id": "2401.9999",
        "title": "Quantum Resistance",
        "abstract": "Abstract text",
    }
    enriched = _process_single_record(rec, "/nonexistent", logger)
    assert enriched["arxiv_id"] == "2401.9999"
    assert enriched["full_text"] == "Abstract text"
    assert enriched["page_count"] == 1
    assert "extracted_at" in enriched


def test_process_single_record_with_existing_text() -> None:
    logger = DiagnosticLogger(stream=io.StringIO())
    rec = {
        "arxiv_id": "2401.9999",
        "title": "Quantum Resistance",
        "full_text": "Already extracted text",
        "page_count": 5,
    }
    enriched = _process_single_record(rec, "/nonexistent", logger)
    assert enriched["full_text"] == "Already extracted text"
    assert enriched["page_count"] == 5


def test_pdf_extract_command_stream_pipeline() -> None:
    cmd = PdfExtractCommand()
    parser = argparse.ArgumentParser()
    cmd.add_arguments(parser)
    args = parser.parse_args(["--pdf-cache-dir", "/tmp", "--on-error", "skip"])

    input_jsonl = (
        '{"arxiv_id": "2401.0001", "title": "Paper 1", "abstract": "Abs 1"}\n'
        '{"arxiv_id": "2401.0002", "title": "Paper 2", "abstract": "Abs 2"}\n'
    )

    with patch("sys.stdin", io.StringIO(input_jsonl)):
        with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
            with patch("sys.stderr", new_callable=io.StringIO) as mock_stderr:
                code = cmd.handle(args)
                assert code == 0

                lines = mock_stdout.getvalue().strip().splitlines()
                assert len(lines) == 2

                rec1 = json.loads(lines[0])
                assert rec1["arxiv_id"] == "2401.0001"
                assert rec1["full_text"] == "Abs 1"

                rec2 = json.loads(lines[1])
                assert rec2["arxiv_id"] == "2401.0002"
                assert rec2["full_text"] == "Abs 2"

                stderr_val = mock_stderr.getvalue()
                assert "[INFO]" in stderr_val
                assert "Successfully processed 2 paper records." in stderr_val
