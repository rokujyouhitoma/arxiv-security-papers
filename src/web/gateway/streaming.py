#!/usr/bin/env python3
"""
Server-Sent Events (SSE) Streaming Generator and Formatter for Web Gateway.
Provides PEP 3333 compliant chunked streaming generators for real-time telemetry, logs, and top metrics.
"""

from __future__ import annotations

import json
import os
import sys
import threading
import time
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Iterator, List, Optional


def _log_stream_open(stream_name: str) -> None:
    th = threading.current_thread().name
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
    print(
        f"[{ts}] [SSE-OPEN] thread={th} stream={stream_name}",
        file=sys.stderr,
        flush=True,
    )


def _log_stream_close(stream_name: str, reason: str) -> None:
    th = threading.current_thread().name
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
    print(
        f"[{ts}] [SSE-CLOSE] thread={th} stream={stream_name} reason={reason}",
        file=sys.stderr,
        flush=True,
    )


def _serialize_sse_payload(data: Any) -> str:
    if isinstance(data, (dict, list)):
        return json.dumps(data, ensure_ascii=False)
    return str(data)


def _build_sse_header_lines(
    event: Optional[str], event_id: Optional[str], retry_ms: Optional[int]
) -> List[str]:
    lines: List[str] = []
    if event_id is not None:
        lines.append(f"id: {event_id}")
    if event is not None:
        lines.append(f"event: {event}")
    if retry_ms is not None:
        lines.append(f"retry: {retry_ms}")
    return lines


def format_sse_event(
    data: Any,
    event: Optional[str] = None,
    event_id: Optional[str] = None,
    retry_ms: Optional[int] = None,
) -> bytes:
    """
    Encodes data and metadata into a valid SSE (Server-Sent Events) byte chunk according to W3C spec.
    """
    lines = _build_sse_header_lines(event, event_id, retry_ms)
    payload = _serialize_sse_payload(data)
    for line in payload.splitlines():
        lines.append(f"data: {line}")
    lines.append("")
    lines.append("")
    return "\n".join(lines).encode("utf-8")


def _format_ping() -> bytes:
    return b": ping\n\n"


def stream_top_metrics(
    status_fn: Callable[[], Dict[str, Any]],
    interval: float = 1.0,
    max_duration: float = 3600.0,
) -> Iterator[bytes]:
    """
    Streams live supervisor top metrics, process table, and memory usage via SSE.
    """
    start_time = time.monotonic()
    last_ping = start_time
    seq = 0

    _log_stream_open("top_metrics")
    # Emit initial connection event
    yield format_sse_event(
        {"status": "connected", "stream": "top_metrics"},
        event="connected",
        event_id=str(seq),
    )

    try:
        while (time.monotonic() - start_time) < max_duration:
            seq += 1
            now = time.monotonic()
            metrics = status_fn()
            yield format_sse_event(
                metrics,
                event="top_update",
                event_id=str(seq),
            )

            # Send keep-alive comment ping every 15 seconds
            if now - last_ping >= 15.0:
                yield _format_ping()
                last_ping = now

            time.sleep(interval)
    except (GeneratorExit, ConnectionResetError, BrokenPipeError) as exc:
        _log_stream_close("top_metrics", type(exc).__name__)
    finally:
        _log_stream_close("top_metrics", "stream_ended")


def _parse_single_log_line(line_str: str) -> Dict[str, Any]:
    try:
        return cast_dict(json.loads(line_str))
    except Exception:
        return {"raw": line_str}


def cast_dict(val: Any) -> Dict[str, Any]:
    return val if isinstance(val, dict) else {"raw": str(val)}


def _extract_log_records(f: Any) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    for line in f:
        s = line.strip()
        if s:
            records.append(_parse_single_log_line(s))
    return records


def _read_new_log_lines(
    file_path: str, last_pos: int
) -> tuple[List[Dict[str, Any]], int]:
    if not os.path.exists(file_path):
        return [], last_pos
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            f.seek(last_pos)
            records = _extract_log_records(f)
            return records, f.tell()
    except Exception:
        return [], last_pos


def _init_log_tail_pos(log_file_path: str) -> int:
    if not os.path.exists(log_file_path):
        return 0
    try:
        size = os.path.getsize(log_file_path)
        return max(0, size - 4096)
    except Exception:
        return 0


def stream_log_tail(
    log_file_path: str,
    interval: float = 1.0,
    max_duration: float = 3600.0,
) -> Iterator[bytes]:
    """
    Streams real-time structured JSON log entries by tailing the target log file.
    """
    start_time = time.monotonic()
    last_ping = start_time
    last_pos = _init_log_tail_pos(log_file_path)
    seq = 0

    _log_stream_open("log_tail")
    yield format_sse_event(
        {"status": "connected", "file": os.path.basename(log_file_path)},
        event="connected",
        event_id=str(seq),
    )

    try:
        while (time.monotonic() - start_time) < max_duration:
            now = time.monotonic()
            records, last_pos = _read_new_log_lines(log_file_path, last_pos)
            for rec in records:
                seq += 1
                yield format_sse_event(rec, event="log_entry", event_id=str(seq))

            if now - last_ping >= 15.0:
                yield _format_ping()
                last_ping = now

            time.sleep(interval)
    except (GeneratorExit, ConnectionResetError, BrokenPipeError) as exc:
        _log_stream_close("log_tail", type(exc).__name__)
    finally:
        _log_stream_close("log_tail", "stream_ended")


def stream_system_events(
    event_fetcher: Callable[[], Optional[Dict[str, Any]]],
    interval: float = 2.0,
    max_duration: float = 3600.0,
) -> Iterator[bytes]:
    """
    Streams system event bus notifications, pipeline tasks, and ingest status updates.
    """
    start_time = time.monotonic()
    last_ping = start_time
    seq = 0

    _log_stream_open("system_events")
    yield format_sse_event(
        {"status": "connected", "stream": "system_events"},
        event="connected",
        event_id=str(seq),
    )

    try:
        while (time.monotonic() - start_time) < max_duration:
            seq += 1
            now = time.monotonic()
            evt = event_fetcher()
            if evt is not None:
                yield format_sse_event(evt, event="system_event", event_id=str(seq))

            if now - last_ping >= 15.0:
                yield _format_ping()
                last_ping = now

            time.sleep(interval)
    except (GeneratorExit, ConnectionResetError, BrokenPipeError) as exc:
        _log_stream_close("system_events", type(exc).__name__)
    finally:
        _log_stream_close("system_events", "stream_ended")
