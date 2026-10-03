#!/usr/bin/env python3
"""tests/cli/commands/test_db_index.py

Unit tests for DbIndexCommand conforming to DSN-01 Section 5.2.
"""

import argparse
import io
import json
import os
from unittest.mock import patch

from src.cli.commands.db_index import (
    DbIndexCommand,
    _index_single_record,
    _load_catalog,
    _save_catalog,
)


def test_catalog_load_save(tmp_path: str) -> None:
    cat_path = os.path.join(str(tmp_path), "catalog.json")
    assert _load_catalog(cat_path) == {}

    data = {"2401_0001": {"title": "Test Paper"}}
    _save_catalog(cat_path, data)
    loaded = _load_catalog(cat_path)
    assert "2401_0001" in loaded
    assert loaded["2401_0001"]["title"] == "Test Paper"


def test_index_single_record() -> None:
    cat: dict[str, dict[str, object]] = {}
    rec = {
        "arxiv_id": "2401.9999",
        "title": "Hardware Security",
        "title_ja": "ハードウェアセキュリティ",
        "summary_ja": "要約文",
        "tags": ["cs.CR"],
    }
    _index_single_record(rec, cat, "all")
    assert "2401.9999" in cat
    assert cat["2401.9999"]["title_ja"] == "ハードウェアセキュリティ"


def test_db_index_command_summary_output(tmp_path: str) -> None:
    cmd = DbIndexCommand(workspace_dir=str(tmp_path))
    parser = argparse.ArgumentParser()
    cmd.add_arguments(parser)
    args = parser.parse_args(["-t", "db"])

    input_jsonl = '{"arxiv_id": "2401.0001", "title": "Paper 1", "title_ja": "論文1"}\n'

    with patch("sys.stdin", io.StringIO(input_jsonl)):
        with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
            with patch("sys.stderr", new_callable=io.StringIO) as mock_stderr:
                code = cmd.handle(args)
                assert code == 0

                lines = mock_stdout.getvalue().strip().splitlines()
                assert len(lines) == 1
                stats = json.loads(lines[0])
                assert stats["status"] == "success"
                assert stats["indexed_count"] == 1
                assert stats["target"] == "db"

                assert "[INFO]" in mock_stderr.getvalue()


def test_db_index_command_passthrough_output(tmp_path: str) -> None:
    cmd = DbIndexCommand(workspace_dir=str(tmp_path))
    parser = argparse.ArgumentParser()
    cmd.add_arguments(parser)
    args = parser.parse_args(["-p"])

    input_jsonl = '{"arxiv_id": "2401.0002", "title": "Paper 2"}\n'

    with patch("sys.stdin", io.StringIO(input_jsonl)):
        with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
            with patch("sys.stderr", new_callable=io.StringIO) as mock_stderr:
                code = cmd.handle(args)
                assert code == 0

                lines = mock_stdout.getvalue().strip().splitlines()
                assert len(lines) == 1
                rec = json.loads(lines[0])
                assert rec["arxiv_id"] == "2401.0002"
                assert "[INFO]" in mock_stderr.getvalue()
