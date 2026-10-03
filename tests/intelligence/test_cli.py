#!/usr/bin/env python3
"""tests/intelligence/test_cli.py

Tests for stdout and stderr stream separation in src/intelligence/cli.py conforming to DSN-01 Section 5.2.
"""

import io
import json
from unittest.mock import MagicMock, patch

from src.intelligence.cli import _print_banner, _output_cycle_summary, run_cycle_command, build_parser


def test_print_banner_outputs_strictly_to_stderr() -> None:
    with patch("sys.stderr", new_callable=io.StringIO) as mock_stderr:
        with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
            _print_banner()
            assert "UNIVERSAL AUTONOMOUS INTELLIGENCE ORCHESTRATOR" in mock_stderr.getvalue()
            assert mock_stdout.getvalue() == ""


def test_output_cycle_summary_json_to_stdout_cleanly() -> None:
    sample_summary = [{"cycle_id": "test_01", "errors": []}]
    with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
        code = _output_cycle_summary(sample_summary, as_json=True)
        assert code == 0
        raw_stdout = mock_stdout.getvalue()
        parsed = json.loads(raw_stdout)
        assert len(parsed) == 1
        assert parsed[0]["cycle_id"] == "test_01"


def test_cycle_command_json_separation(tmp_path: str) -> None:
    parser = build_parser()
    args = parser.parse_args(["--workdir", str(tmp_path), "cycle", "--json"])

    mock_engine = MagicMock()
    mock_ctx = MagicMock()
    mock_ctx.cycle_id = "test_cycle"
    mock_ctx.phase_statuses = {}
    mock_ctx.raw_records = []
    mock_ctx.processed_records = []
    mock_ctx.products = []
    mock_ctx.errors = []
    mock_ctx.directive = None
    mock_ctx.state = {}
    mock_engine.run_cycle.return_value = mock_ctx
    mock_engine.pir_manager.list_active_requirements.return_value = []
    mock_engine.get_current_topic_weights.return_value = {}

    with patch("src.intelligence.cli.ClosedLoopIntelligenceEngine", return_value=mock_engine):
        with patch("sys.stdout", new_callable=io.StringIO) as mock_stdout:
            with patch("sys.stderr", new_callable=io.StringIO) as mock_stderr:
                code = run_cycle_command(args)
                assert code == 0

                raw_stdout = mock_stdout.getvalue().strip()
                data = json.loads(raw_stdout)
                assert isinstance(data, list)
                assert data[0]["cycle_id"] == "test_cycle"

                assert "UNIVERSAL AUTONOMOUS" not in raw_stdout
                assert mock_stderr is not None
