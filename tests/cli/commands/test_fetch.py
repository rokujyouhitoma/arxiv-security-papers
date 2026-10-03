#!/usr/bin/env python3
"""tests/cli/commands/test_fetch.py

Unit tests for FetchCommand conforming to DSN-01 Section 5.2 and REQ-FR-09.
"""

import argparse
import io
import json
from unittest.mock import MagicMock, patch

from src.cli.commands.fetch import FetchCommand, _extract_paper_record


def test_extract_paper_record() -> None:
    mock_item = MagicMock()
    mock_item.source_id = "2401.9999"
    mock_item.raw_content = "Test Abstract"
    mock_item.metadata = {
        "arxiv_id": "2401.9999",
        "title": "Quantum Resistance in Distributed Systems",
        "authors": ["Alice", "Bob"],
        "abstract": "Test Abstract",
        "published": "2026-10-01",
        "categories": ["cs.CR"],
        "pdf_url": "https://arxiv.org/pdf/2401.9999.pdf",
    }

    record = _extract_paper_record(mock_item)
    assert record["arxiv_id"] == "2401.9999"
    assert record["title"] == "Quantum Resistance in Distributed Systems"
    assert record["authors"] == ["Alice", "Bob"]
    assert record["categories"] == ["cs.CR"]


def test_fetch_command_execution() -> None:
    cmd = FetchCommand()
    parser = argparse.ArgumentParser()
    cmd.add_arguments(parser)
    args = parser.parse_args(["-n", "2", "-c", "cs.CR"])

    mock_items = [
        MagicMock(
            source_id="2401.0001",
            raw_content="Abstract 1",
            metadata={"arxiv_id": "2401.0001", "title": "Paper 1"},
        ),
        MagicMock(
            source_id="2401.0002",
            raw_content="Abstract 2",
            metadata={"arxiv_id": "2401.0002", "title": "Paper 2"},
        ),
    ]

    with patch(
        "src.cli.commands.fetch.ArxivSourceAdapter.fetch_items",
        return_value=mock_items,
    ):
        with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
            with patch("sys.stderr", new_callable=io.StringIO) as mock_stderr:
                code = cmd.handle(args)
                assert code == 0

                lines = mock_stdout.getvalue().strip().splitlines()
                assert len(lines) == 2
                rec1 = json.loads(lines[0])
                assert rec1["arxiv_id"] == "2401.0001"
                assert rec1["title"] == "Paper 1"

                stderr_val = mock_stderr.getvalue()
                assert "[INFO]" in stderr_val
                assert "Successfully streamed 2 paper records." in stderr_val
