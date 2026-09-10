#!/usr/bin/env python3
"""
Unit tests for Hierarchical State Machine (HSM) StreamController and SSE Streaming.
Verifies backpressure transitions, priority frame shedding, and graceful draining.
"""

from typing import Any, Dict, List, Optional

from web.gateway.streaming import (
    EVENT_CONGESTION,
    EVENT_CONNECTED,
    EVENT_DEGRADATION,
    EVENT_RECOVERY,
    STREAM_INITIALIZING,
    STREAM_STREAMING,
    STREAM_TERMINATED,
    StreamController,
    build_stream_session_hsm,
    stream_log_tail,
    stream_system_events,
    stream_top_metrics,
)


def test_stream_hsm_initial_state() -> None:
    """Verifies that the stream session HSM initializes in INITIALIZING state."""
    hsm = build_stream_session_hsm()
    assert hsm.current_state.name == "INITIALIZING"
    assert hsm.is_in_state(STREAM_INITIALIZING)


def test_stream_hsm_connect_transition() -> None:
    """Verifies transition from INITIALIZING to STREAMING.FLOWING."""
    hsm = build_stream_session_hsm()
    assert hsm.send_event(EVENT_CONNECTED) is True
    assert hsm.current_state.name == "FLOWING"
    assert hsm.is_in_state(STREAM_STREAMING)


def test_stream_hsm_congestion_entry() -> None:
    """Verifies transition from FLOWING to CONGESTED."""
    hsm = build_stream_session_hsm()
    hsm.send_event(EVENT_CONNECTED)
    assert hsm.send_event(EVENT_CONGESTION) is True
    assert hsm.current_state.name == "CONGESTED"


def test_stream_hsm_degradation_entry() -> None:
    """Verifies transition from CONGESTED to DEGRADED."""
    hsm = build_stream_session_hsm()
    hsm.send_event(EVENT_CONNECTED)
    hsm.send_event(EVENT_CONGESTION)
    assert hsm.send_event(EVENT_DEGRADATION) is True
    assert hsm.current_state.name == "DEGRADED"


def test_stream_hsm_congestion_recovery() -> None:
    """Verifies recovery from DEGRADED back to CONGESTED then FLOWING."""
    hsm = build_stream_session_hsm()
    hsm.send_event(EVENT_CONNECTED)
    hsm.send_event(EVENT_CONGESTION)
    hsm.send_event(EVENT_DEGRADATION)
    assert hsm.send_event(EVENT_RECOVERY) is True
    assert hsm.current_state.name == "FLOWING"


def test_stream_controller_cycle_congested() -> None:
    """Verifies mild delay causes transition to CONGESTED."""
    ctrl = StreamController("test_stream", interval=1.0)
    ctrl.mark_connected()
    ctrl.evaluate_cycle(0.9)
    assert ctrl.current_state_path == "STREAMING.CONGESTED"


def test_stream_controller_cycle_degraded() -> None:
    """Verifies severe delay causes transition to DEGRADED."""
    ctrl = StreamController("test_stream", interval=1.0)
    ctrl.mark_connected()
    ctrl.evaluate_cycle(1.6)
    assert ctrl.current_state_path == "STREAMING.DEGRADED"


def test_stream_controller_cycle_recovery() -> None:
    """Verifies returning to normal duration restores FLOWING."""
    ctrl = StreamController("test_stream", interval=1.0)
    ctrl.mark_connected()
    ctrl.evaluate_cycle(1.6)
    ctrl.evaluate_cycle(0.5)
    assert ctrl.current_state_path == "STREAMING.FLOWING"


def test_priority_emission_in_flowing() -> None:
    """Verifies all priorities are emitted in normal FLOWING state."""
    ctrl = StreamController("test_stream", interval=1.0)
    ctrl.mark_connected()
    results = [ctrl.should_emit(p) for p in (0, 1, 2)]
    assert results == [True, True, True]


def test_priority_emission_in_congested() -> None:
    """Verifies priority 0 and 1 are emitted in CONGESTED state."""
    ctrl = StreamController("test_stream", interval=1.0)
    ctrl.mark_connected()
    ctrl.evaluate_cycle(0.9)
    assert ctrl.should_emit(priority=0) is True
    assert ctrl.should_emit(priority=1) is True


def test_priority_emission_in_degraded() -> None:
    """Verifies low priorities are suppressed in DEGRADED state."""
    ctrl = StreamController("test_stream", interval=1.0)
    ctrl.mark_connected()
    ctrl.evaluate_cycle(1.6)
    assert ctrl.should_emit(priority=0) is True
    ctrl.skip_counter = 0
    assert ctrl.should_emit(priority=2) is False


def test_stream_controller_graceful_disconnect() -> None:
    """Verifies graceful disconnect triggers DRAINING and returns stream_close frame."""
    ctrl = StreamController("test_metrics", interval=1.0)
    ctrl.mark_connected()
    close_bytes = ctrl.handle_disconnect("client_closed")
    assert close_bytes is not None
    decoded = close_bytes.decode("utf-8")
    assert "event: stream_close" in decoded
    assert ctrl.current_state_path == "TERMINATED.COMPLETED"


def test_stream_controller_abnormal_disconnect() -> None:
    """Verifies abnormal disconnect aborts immediately without frame."""
    ctrl = StreamController("test_metrics", interval=1.0)
    ctrl.mark_connected()
    close_bytes = ctrl.handle_disconnect("BrokenPipeError")
    assert close_bytes is None
    assert ctrl.current_state_path == "TERMINATED.ABORTED"


def _assert_frame_match(frames: List[bytes], prefix: str) -> None:
    matched = any(prefix in f.decode("utf-8") for f in frames)
    assert matched is True


def test_stream_top_metrics_generator_lifecycle() -> None:
    """Verifies stream_top_metrics generator produces connected frame and handles exit."""
    ctrl = StreamController("top_metrics", interval=0.01)
    gen = stream_top_metrics(
        status_fn=lambda: {"cpu": 10.5, "mem": 42.0},
        interval=0.01,
        max_duration=0.03,
        controller=ctrl,
    )
    frames = list(gen)
    assert len(frames) >= 2
    assert "event: connected" in frames[0].decode("utf-8")
    _assert_frame_match(frames, "event: top_update")
    _assert_frame_match(frames, "event: stream_close")
    assert ctrl.hsm.is_in_state(STREAM_TERMINATED)


def test_stream_log_tail_generator_lifecycle(tmp_path: Any) -> None:
    """Verifies stream_log_tail generator tails file and closes gracefully."""
    log_file = tmp_path / "test.log"
    log_file.write_text('{"msg": "log line 1"}\n{"msg": "log line 2"}\n')

    ctrl = StreamController("log_tail", interval=0.01)
    gen = stream_log_tail(
        str(log_file),
        interval=0.01,
        max_duration=0.03,
        controller=ctrl,
    )
    frames = list(gen)
    assert len(frames) >= 2
    assert "event: connected" in frames[0].decode("utf-8")
    _assert_frame_match(frames, "event: stream_close")
    assert ctrl.hsm.is_in_state(STREAM_TERMINATED)


def test_stream_system_events_generator_lifecycle() -> None:
    """Verifies stream_system_events emits events and drains cleanly."""
    event_data = {"type": "pipeline_started", "id": 1}
    calls = [0]

    def fetch_event() -> Optional[Dict[str, Any]]:
        calls[0] += 1
        return event_data if calls[0] == 1 else None

    ctrl = StreamController("system_events", interval=0.01)
    gen = stream_system_events(
        fetch_event,
        interval=0.01,
        max_duration=0.03,
        controller=ctrl,
    )
    frames = list(gen)
    assert len(frames) >= 2
    assert "event: connected" in frames[0].decode("utf-8")
    _assert_frame_match(frames, "event: system_event")
    _assert_frame_match(frames, "event: stream_close")
    assert ctrl.hsm.is_in_state(STREAM_TERMINATED)
