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

from core.hsm import HierarchicalStateMachine, StateNode, TransitionRule

# Composite and leaf state definitions
STREAM_ROOT = "ROOT"
STREAM_INITIALIZING = "INITIALIZING"
STREAM_STREAMING = "STREAMING"
STREAM_FLOWING = "STREAMING.FLOWING"
STREAM_CONGESTED = "STREAMING.CONGESTED"
STREAM_DEGRADED = "STREAMING.DEGRADED"
STREAM_DRAINING = "DRAINING"
STREAM_DRAINING_FLUSH = "DRAINING.FLUSHING"
STREAM_DRAINING_RELEASE = "DRAINING.RELEASING"
STREAM_TERMINATED = "TERMINATED"
STREAM_COMPLETED = "TERMINATED.COMPLETED"
STREAM_ABORTED = "TERMINATED.ABORTED"

# Event constants
EVENT_CONNECTED = "CONNECTED"
EVENT_CONGESTION = "CONGESTION"
EVENT_DEGRADATION = "DEGRADATION"
EVENT_RECOVERY = "RECOVERY"
EVENT_DISCONNECT = "DISCONNECT"
EVENT_DRAINED = "DRAINED"
EVENT_ABORT = "ABORT"


def _configure_streaming_rules(
    init_node: StateNode,
    streaming: StateNode,
    flowing: StateNode,
    congested: StateNode,
    degraded: StateNode,
) -> None:
    init_node.add_transition(
        TransitionRule("INITIALIZING", EVENT_CONNECTED, "STREAMING.FLOWING")
    )
    flowing.add_transition(
        TransitionRule("FLOWING", EVENT_CONGESTION, "STREAMING.CONGESTED")
    )
    flowing.add_transition(
        TransitionRule("FLOWING", EVENT_DEGRADATION, "STREAMING.DEGRADED")
    )
    congested.add_transition(
        TransitionRule("CONGESTED", EVENT_RECOVERY, "STREAMING.FLOWING")
    )
    congested.add_transition(
        TransitionRule("CONGESTED", EVENT_DEGRADATION, "STREAMING.DEGRADED")
    )
    degraded.add_transition(
        TransitionRule("DEGRADED", EVENT_RECOVERY, "STREAMING.FLOWING")
    )
    streaming.add_transition(
        TransitionRule("STREAMING", EVENT_DISCONNECT, "DRAINING.FLUSHING")
    )
    streaming.add_transition(
        TransitionRule("STREAMING", EVENT_ABORT, "TERMINATED.ABORTED")
    )


def _configure_draining_rules(
    draining: StateNode,
    flushing: StateNode,
    releasing: StateNode,
) -> None:
    flushing.add_transition(
        TransitionRule("FLUSHING", EVENT_DRAINED, "DRAINING.RELEASING")
    )
    releasing.add_transition(
        TransitionRule("RELEASING", EVENT_DRAINED, "TERMINATED.COMPLETED")
    )
    draining.add_transition(
        TransitionRule("DRAINING", EVENT_ABORT, "TERMINATED.ABORTED")
    )


def build_stream_session_hsm() -> HierarchicalStateMachine:
    """Builds the hierarchical state machine tree for SSE stream session lifecycle."""
    root = StateNode("ROOT", initial_child="INITIALIZING")
    init_node = root.add_child(StateNode("INITIALIZING"))

    streaming = root.add_child(StateNode("STREAMING", initial_child="FLOWING"))
    flowing = streaming.add_child(StateNode("FLOWING"))
    congested = streaming.add_child(StateNode("CONGESTED"))
    degraded = streaming.add_child(StateNode("DEGRADED"))

    draining = root.add_child(StateNode("DRAINING", initial_child="FLUSHING"))
    flushing = draining.add_child(StateNode("FLUSHING"))
    releasing = draining.add_child(StateNode("RELEASING"))

    terminated = root.add_child(StateNode("TERMINATED", initial_child="COMPLETED"))
    terminated.add_child(StateNode("COMPLETED"))
    terminated.add_child(StateNode("ABORTED"))

    _configure_streaming_rules(init_node, streaming, flowing, congested, degraded)
    _configure_draining_rules(draining, flushing, releasing)
    return HierarchicalStateMachine(root)


class StreamController:
    """Manages cycle latencies, backpressure state transitions, and graceful drain."""

    def __init__(
        self,
        stream_name: str,
        interval: float,
        hsm: Optional[HierarchicalStateMachine] = None,
    ) -> None:
        self.stream_name: str = stream_name
        self.interval: float = max(0.01, interval)
        self.hsm: HierarchicalStateMachine = hsm or build_stream_session_hsm()
        self.skip_counter: int = 0

    @property
    def current_state_path(self) -> str:
        return str(self.hsm.get_state_path())

    def mark_connected(self) -> None:
        if self.hsm.is_in_state(STREAM_INITIALIZING):
            self.hsm.send_event(EVENT_CONNECTED)

    def evaluate_cycle(self, duration: float) -> None:
        """Evaluates iteration duration and transitions HSM state for backpressure."""
        if duration > self.interval * 1.5:
            self._handle_degraded_duration()
        elif duration > self.interval * 0.8:
            self._handle_congested_duration()
        else:
            self._handle_recovery_duration()

    def _handle_degraded_duration(self) -> None:
        if not self.hsm.is_in_state("DEGRADED"):
            self.hsm.send_event(EVENT_DEGRADATION)

    def _handle_congested_duration(self) -> None:
        if self.hsm.is_in_state("FLOWING"):
            self.hsm.send_event(EVENT_CONGESTION)

    def _handle_recovery_duration(self) -> None:
        if not self.hsm.is_in_state("FLOWING"):
            self.hsm.send_event(EVENT_RECOVERY)

    def should_emit(self, priority: int = 0) -> bool:
        """Determines whether to emit frame based on priority and congestion level."""
        self.skip_counter += 1
        if self.hsm.is_in_state("DEGRADED"):
            return self._emit_in_degraded(priority)
        if self.hsm.is_in_state("CONGESTED"):
            return self._emit_in_congested(priority)
        return True

    def _emit_in_degraded(self, priority: int) -> bool:
        if priority == 0:
            return True
        if priority == 1:
            return self.skip_counter % 2 == 0
        return False

    def _emit_in_congested(self, priority: int) -> bool:
        if priority >= 2:
            return self.skip_counter % 2 == 0
        return True

    def handle_disconnect(self, reason: str) -> Optional[bytes]:
        """Drains stream resources through HSM and returns final close frame if graceful."""
        is_abnormal = reason in (
            "BrokenPipeError",
            "ConnectionResetError",
            "abnormal",
        )
        if is_abnormal:
            self.hsm.send_event(EVENT_ABORT)
            return None
        self.hsm.send_event(EVENT_DISCONNECT)
        close_frame = format_sse_event(
            {"status": "closed", "stream": self.stream_name, "reason": reason},
            event="stream_close",
        )
        self.hsm.send_event(EVENT_DRAINED)
        self.hsm.send_event(EVENT_DRAINED)
        return close_frame


def _log_stream_open(stream_name: str) -> None:
    th = threading.current_thread().name
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
    print(
        f"[{ts}] [SSE-OPEN] thread={th} stream={stream_name}",
        file=sys.stderr,
        flush=True,
    )


def _log_stream_close(stream_name: str, reason: str, state_path: str = "") -> None:
    th = threading.current_thread().name
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3]
    print(
        f"[{ts}] [SSE-CLOSE] thread={th} stream={stream_name} reason={reason} state={state_path}",
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


def _check_ping(now: float, last_ping: float) -> tuple[Optional[bytes], float]:
    if now - last_ping >= 15.0:
        return _format_ping(), now
    return None, last_ping


def _emit_top_metric_frame(
    ctrl: StreamController,
    status_fn: Callable[[], Dict[str, Any]],
    seq: int,
) -> Optional[bytes]:
    if not ctrl.should_emit(priority=0):
        return None
    return format_sse_event(status_fn(), event="top_update", event_id=str(seq))


def _resolve_ctrl(
    controller: Optional[StreamController], name: str, interval: float
) -> StreamController:
    if controller is not None:
        return controller
    return StreamController(name, interval)


def _drain_stream_frames(
    ctrl: StreamController, stream_name: str, reason: str
) -> Iterator[bytes]:
    frame = _drain_and_close(ctrl, stream_name, reason)
    if frame is not None:
        yield frame


def _wrap_stream(
    ctrl: StreamController,
    stream_name: str,
    gen_fn: Callable[[], Iterator[bytes]],
) -> Iterator[bytes]:
    _log_stream_open(stream_name)
    ctrl.mark_connected()
    try:
        yield from gen_fn()
    except (GeneratorExit, ConnectionResetError, BrokenPipeError) as exc:
        yield from _drain_stream_frames(ctrl, stream_name, type(exc).__name__)
    finally:
        yield from _drain_stream_frames(ctrl, stream_name, "stream_ended")


def _yield_metric_frame(
    ctrl: StreamController,
    status_fn: Callable[[], Dict[str, Any]],
    seq: int,
) -> Iterator[bytes]:
    frame = _emit_top_metric_frame(ctrl, status_fn, seq)
    if frame is not None:
        yield frame


def _loop_top_metrics(
    ctrl: StreamController,
    status_fn: Callable[[], Dict[str, Any]],
    interval: float,
    max_duration: float,
) -> Iterator[bytes]:
    start_time = time.monotonic()
    last_ping = start_time
    seq = 0
    while (time.monotonic() - start_time) < max_duration:
        cycle_start = time.monotonic()
        seq += 1
        yield from _yield_metric_frame(ctrl, status_fn, seq)
        ping, last_ping = _check_ping(time.monotonic(), last_ping)
        if ping is not None:
            yield ping
        ctrl.evaluate_cycle(time.monotonic() - cycle_start)
        time.sleep(interval)


def stream_top_metrics(
    status_fn: Callable[[], Dict[str, Any]],
    interval: float = 1.0,
    max_duration: float = 3600.0,
    controller: Optional[StreamController] = None,
) -> Iterator[bytes]:
    """
    Streams live supervisor top metrics, process table, and memory usage via SSE.
    Governed by HierarchicalStateMachine (HSM) backpressure and lifecycle controls.
    """
    ctrl = _resolve_ctrl(controller, "top_metrics", interval)
    yield format_sse_event(
        {"status": "connected", "stream": "top_metrics"},
        event="connected",
        event_id="0",
    )
    yield from _wrap_stream(
        ctrl,
        "top_metrics",
        lambda: _loop_top_metrics(ctrl, status_fn, interval, max_duration),
    )


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


def _drain_and_close(
    ctrl: StreamController, stream_name: str, reason: str
) -> Optional[bytes]:
    _log_stream_close(stream_name, reason, ctrl.current_state_path)
    if not ctrl.hsm.is_in_state(STREAM_TERMINATED):
        return ctrl.handle_disconnect(reason)
    return None


def _emit_log_records(
    ctrl: StreamController,
    log_file_path: str,
    last_pos: int,
    seq: int,
) -> tuple[List[bytes], int, int]:
    chunks: List[bytes] = []
    records, next_pos = _read_new_log_lines(log_file_path, last_pos)
    for rec in records:
        seq += 1
        if ctrl.should_emit(priority=1):
            chunks.append(format_sse_event(rec, event="log_entry", event_id=str(seq)))
    return chunks, next_pos, seq


def _loop_log_tail(
    ctrl: StreamController,
    log_file_path: str,
    interval: float,
    max_duration: float,
) -> Iterator[bytes]:
    start_time = time.monotonic()
    last_ping = start_time
    last_pos = _init_log_tail_pos(log_file_path)
    seq = 0
    while (time.monotonic() - start_time) < max_duration:
        cycle_start = time.monotonic()
        chunks, last_pos, seq = _emit_log_records(ctrl, log_file_path, last_pos, seq)
        for chunk in chunks:
            yield chunk
        ping, last_ping = _check_ping(time.monotonic(), last_ping)
        if ping is not None:
            yield ping
        ctrl.evaluate_cycle(time.monotonic() - cycle_start)
        time.sleep(interval)


def stream_log_tail(
    log_file_path: str,
    interval: float = 1.0,
    max_duration: float = 3600.0,
    controller: Optional[StreamController] = None,
) -> Iterator[bytes]:
    """
    Streams real-time structured JSON log entries by tailing the target log file.
    Governed by HierarchicalStateMachine (HSM) backpressure and lifecycle controls.
    """
    ctrl = _resolve_ctrl(controller, "log_tail", interval)
    yield format_sse_event(
        {"status": "connected", "file": os.path.basename(log_file_path)},
        event="connected",
        event_id="0",
    )
    yield from _wrap_stream(
        ctrl,
        "log_tail",
        lambda: _loop_log_tail(ctrl, log_file_path, interval, max_duration),
    )


def _emit_system_event_frame(
    ctrl: StreamController,
    event_fetcher: Callable[[], Optional[Dict[str, Any]]],
    seq: int,
) -> Optional[bytes]:
    if not ctrl.should_emit(priority=0):
        return None
    evt = event_fetcher()
    if evt is None:
        return None
    return format_sse_event(evt, event="system_event", event_id=str(seq))


def _yield_system_event_frame(
    ctrl: StreamController,
    event_fetcher: Callable[[], Optional[Dict[str, Any]]],
    seq: int,
) -> Iterator[bytes]:
    frame = _emit_system_event_frame(ctrl, event_fetcher, seq)
    if frame is not None:
        yield frame


def _loop_system_events(
    ctrl: StreamController,
    event_fetcher: Callable[[], Optional[Dict[str, Any]]],
    interval: float,
    max_duration: float,
) -> Iterator[bytes]:
    start_time = time.monotonic()
    last_ping = start_time
    seq = 0
    while (time.monotonic() - start_time) < max_duration:
        cycle_start = time.monotonic()
        seq += 1
        yield from _yield_system_event_frame(ctrl, event_fetcher, seq)
        ping, last_ping = _check_ping(time.monotonic(), last_ping)
        if ping is not None:
            yield ping
        ctrl.evaluate_cycle(time.monotonic() - cycle_start)
        time.sleep(interval)


def stream_system_events(
    event_fetcher: Callable[[], Optional[Dict[str, Any]]],
    interval: float = 2.0,
    max_duration: float = 3600.0,
    controller: Optional[StreamController] = None,
) -> Iterator[bytes]:
    """
    Streams system event bus notifications, pipeline tasks, and ingest status updates.
    Governed by HierarchicalStateMachine (HSM) backpressure and lifecycle controls.
    """
    ctrl = _resolve_ctrl(controller, "system_events", interval)
    yield format_sse_event(
        {"status": "connected", "stream": "system_events"},
        event="connected",
        event_id="0",
    )
    yield from _wrap_stream(
        ctrl,
        "system_events",
        lambda: _loop_system_events(ctrl, event_fetcher, interval, max_duration),
    )
