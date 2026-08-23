"""Unit and integration test suite for orchestrator CLI entry point."""

import json
from unittest.mock import patch

from orchestrator.cli import build_parser, main


def test_build_parser_structure() -> None:
    parser = build_parser()
    assert parser.prog == "orchestrator"

    # Verify subcommands exist
    subparsers_action = next(a for a in parser._actions if a.dest == "command")
    choices = subparsers_action.choices
    assert "cycle" in choices
    assert "daemon" in choices
    assert "pir" in choices
    assert "status" in choices
    assert "pipeline" in choices
    assert "spider" in choices
    assert "search" in choices
    assert "web" in choices
    assert "mcp" in choices


def test_cli_default_cycle_execution(tmp_path) -> None:
    code = main(["--workdir", str(tmp_path), "cycle", "--cycles", "1", "--quiet"])
    assert code == 0


def test_cli_cycle_json_output(tmp_path, capsys) -> None:
    code = main(
        [
            "--workdir",
            str(tmp_path),
            "cycle",
            "--cycles",
            "1",
            "--json",
            "--topics",
            "zero-trust,quantum",
        ]
    )
    assert code == 0
    captured = capsys.readouterr()
    data = json.loads(captured.out)
    assert isinstance(data, list)
    assert len(data) == 1
    assert "cycle_id" in data[0]
    assert "target_topics" in data[0]
    assert "zero-trust" in data[0]["target_topics"]


def test_cli_pir_list_and_add(tmp_path, capsys) -> None:
    # Test list empty
    code = main(["--workdir", str(tmp_path), "pir", "list"])
    assert code == 0

    # Test add PIR
    code_add = main(
        [
            "--workdir",
            str(tmp_path),
            "pir",
            "add",
            "--id",
            "pir_test_01",
            "--title",
            "Test PIR Title",
            "--description",
            "Test Description",
            "--topics",
            "topic_x,topic_y",
            "--priority",
            "0.95",
        ]
    )
    assert code_add == 0

    # Test list after add
    capsys.readouterr()  # clear buffer
    code_list2 = main(["--workdir", str(tmp_path), "pir", "list"])
    assert code_list2 == 0


def test_cli_pir_add_missing_args(tmp_path) -> None:
    code = main(["--workdir", str(tmp_path), "pir", "add", "--id", "incomplete"])
    assert code == 1


def test_cli_status_command(tmp_path, capsys) -> None:
    # Create mock directory structure
    (tmp_path / "outputs" / "okf_papers").mkdir(parents=True)
    (tmp_path / "outputs" / "executive_summaries" / "01_per_run").mkdir(parents=True)
    (tmp_path / "outputs" / "vector_db").mkdir(parents=True)
    (tmp_path / "outputs" / "vector_db" / "index.json").write_text("{}")

    code = main(["--workdir", str(tmp_path), "status"])
    assert code == 0
    captured = capsys.readouterr()
    assert "ARXIV SECURITY PAPERS" in captured.out
    assert "Vector Search Index" in captured.out


def test_cli_subcommand_dispatch_mocked(tmp_path) -> None:
    with patch("pipeline.arxiv_okf_fetcher.run_theme_pipeline") as mock_pipe:
        code = main(["--workdir", str(tmp_path), "pipeline", "--theme", "security"])
        assert code == 0
        mock_pipe.assert_called_once()

    with patch("spider.runner.SpiderRunner.run_spider") as mock_spider:
        mock_spider.return_value = {"crawled": 10}
        code = main(["--workdir", str(tmp_path), "spider", "--spider-name", "arxiv"])
        assert code == 0
        mock_spider.assert_called_once()

    with patch("search.vector_engine.VectorEngine.search_with_profile") as mock_search:
        mock_search.return_value = (
            [{"id": "doc1", "title": "Paper 1", "score": 1.0}],
            {"total_ms": 1.0},
        )
        code = main(["--workdir", str(tmp_path), "search", "--query", "pentest"])
        assert code == 0
        mock_search.assert_called_once()

    with patch("search.vector_engine.VectorEngine.build_index") as mock_build:
        mock_build.return_value = 42
        code = main(["--workdir", str(tmp_path), "search", "--build"])
        assert code == 0
        mock_build.assert_called_once()

    with patch("web.server.run_server") as mock_web:
        code = main(["--workdir", str(tmp_path), "web", "--port", "9000"])
        assert code == 0
        mock_web.assert_called_once_with(host="0.0.0.0", port=9000)

    with patch("mcp.papers_server.main") as mock_mcp:
        code = main(["--workdir", str(tmp_path), "mcp", "--server-type", "papers"])
        assert code == 0
        mock_mcp.assert_called_once()
