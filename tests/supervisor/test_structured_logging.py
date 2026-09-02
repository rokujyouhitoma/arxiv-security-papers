"""
Unit & Integration Tests for Supervisor Structured Log Inspection CLI.
"""

import json
from typing import Any

from supervisor.cli import main


def test_cli_logs_empty(tmp_path: Any, capsys: Any) -> None:
    non_existent = str(tmp_path / "non_existent.log")
    res = main(["logs", "--file", non_existent])
    assert res == 0
    captured = capsys.readouterr()
    assert "No log files found" in captured.out


def test_cli_logs_with_data(tmp_path: Any, capsys: Any) -> None:
    log_file = tmp_path / "test_access.jsonl"

    rec1 = {
        "timestamp": "2026-09-02T21:50:00.000000Z",
        "level": "INFO",
        "service": "web_gateway",
        "trace_id": "trace_aaa_111",
        "message": "GET /api/search 200",
    }
    rec2 = {
        "timestamp": "2026-09-02T21:50:01.000000Z",
        "level": "ERROR",
        "service": "search.engine",
        "trace_id": "trace_bbb_222",
        "message": "Vector dimension mismatch",
    }
    with open(str(log_file), "w", encoding="utf-8") as f:
        f.write(json.dumps(rec1) + "\n")
        f.write(json.dumps(rec2) + "\n")

    # 1. Test query all
    res = main(["logs", "--file", str(log_file), "--compact"])
    assert res == 0
    captured = capsys.readouterr()
    assert "GET /api/search 200" in captured.out
    assert "Vector dimension mismatch" in captured.out
    assert "trace_aaa_111" in captured.out

    # 2. Test filter by trace-id
    res = main(
        ["logs", "--file", str(log_file), "--trace-id", "trace_bbb_222", "--compact"]
    )
    assert res == 0
    captured = capsys.readouterr()
    assert "Vector dimension mismatch" in captured.out
    assert "GET /api/search 200" not in captured.out

    # 3. Test filter by level ERROR
    res = main(["logs", "--file", str(log_file), "--level", "ERROR", "--compact"])
    assert res == 0
    captured = capsys.readouterr()
    assert "Vector dimension mismatch" in captured.out
    assert "GET /api/search 200" not in captured.out
