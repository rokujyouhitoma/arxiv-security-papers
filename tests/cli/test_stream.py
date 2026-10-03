#!/usr/bin/env python3
"""tests/cli/test_stream.py

Unit tests for StreamReader, StreamWriter, and DiagnosticLogger in src/cli/stream.py.
Conforms to DSN-01 Section 5.2 and REQ-FR-09.
"""

import io
import json
import pytest

from src.cli.stream import (
    DiagnosticLogger,
    StreamErrorPolicy,
    StreamReader,
    StreamWriter,
)


def test_diagnostic_logger_outputs_to_custom_stream() -> None:
    err_stream = io.StringIO()
    logger = DiagnosticLogger(stream=err_stream)

    logger.info("Test Info")
    logger.warn("Test Warn")
    logger.error("Test Error")
    logger.banner("=== BANNER ===")
    logger.progress(current=5, total=10, prefix="Processing")

    output = err_stream.getvalue()
    assert "[INFO] Test Info\n" in output
    assert "[WARN] Test Warn\n" in output
    assert "[ERROR] Test Error\n" in output
    assert "=== BANNER ===\n" in output
    assert "Processing [5/10] (50.0%)" in output


def test_stream_writer_writes_jsonl() -> None:
    out_stream = io.StringIO()
    writer = StreamWriter(stream=out_stream)

    rec1 = {"arxiv_id": "2401.0001", "title": "Paper 1"}
    rec2 = {"arxiv_id": "2401.0002", "title": "論文2"}

    writer.write_record(rec1)
    writer.write_record(rec2)

    assert writer.written_count == 2

    lines = out_stream.getvalue().splitlines()
    assert len(lines) == 2
    assert json.loads(lines[0]) == rec1
    assert json.loads(lines[1]) == rec2


def test_stream_reader_parses_jsonl() -> None:
    input_data = (
        '{"id": 1, "name": "one"}\n\n'
        '{"id": 2, "name": "two"}\n'
    )
    in_stream = io.StringIO(input_data)
    reader = StreamReader(stream=in_stream)

    records = list(reader)
    assert len(records) == 2
    assert records[0] == {"id": 1, "name": "one"}
    assert records[1] == {"id": 2, "name": "two"}
    assert reader.read_count == 2
    assert reader.error_count == 0


def test_stream_reader_handles_malformed_json_skip() -> None:
    input_data = (
        '{"id": 1, "name": "one"}\n'
        'INVALID_JSON_LINE\n'
        '{"id": 2, "name": "two"}\n'
    )
    in_stream = io.StringIO(input_data)
    err_stream = io.StringIO()
    logger = DiagnosticLogger(stream=err_stream)
    reader = StreamReader(
        stream=in_stream,
        on_error=StreamErrorPolicy.SKIP,
        logger=logger,
    )

    records = list(reader)
    assert len(records) == 2
    assert reader.read_count == 2
    assert reader.error_count == 1
    assert "Skipping malformed stream line 2" in err_stream.getvalue()


def test_stream_reader_handles_malformed_json_abort() -> None:
    input_data = (
        '{"id": 1, "name": "one"}\n'
        'NOT_JSON\n'
    )
    in_stream = io.StringIO(input_data)
    reader = StreamReader(stream=in_stream, on_error=StreamErrorPolicy.ABORT)

    with pytest.raises(ValueError) as excinfo:
        list(reader)
    assert "Stream decode error at line 2" in str(excinfo.value)
    assert reader.error_count == 1
