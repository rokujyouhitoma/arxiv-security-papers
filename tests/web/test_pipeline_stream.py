#!/usr/bin/env python3
"""
Unit tests for Pipeline Real-time Progress EventBroadcaster and SSE Streaming.
"""

from __future__ import annotations

from typing import List

from pipeline.events import PipelineEventBroadcaster
from web.gateway.app import WSGIApplication
from web.gateway.streaming import stream_pipeline_progress


def test_pipeline_event_broadcaster_pub_sub() -> None:
    broadcaster = PipelineEventBroadcaster.get_instance()
    broadcaster.reset()

    q1 = broadcaster.subscribe()
    q2 = broadcaster.subscribe()

    broadcaster.emit("stage_start", {"stage": 1, "name": "Ingestion"})

    evt1 = q1.get_nowait()
    evt2 = q2.get_nowait()

    assert evt1["type"] == "stage_start"
    assert evt1["data"]["stage"] == 1
    assert evt2["type"] == "stage_start"
    assert evt2["data"]["name"] == "Ingestion"

    assert broadcaster.get_last_event() == evt1

    broadcaster.unsubscribe(q1)
    broadcaster.emit("progress", {"pct": 50.0})

    assert q1.empty()
    assert q2.get_nowait()["type"] == "progress"

    broadcaster.reset()


def test_stream_pipeline_progress_generator() -> None:
    broadcaster = PipelineEventBroadcaster.get_instance()
    broadcaster.reset()

    gen = stream_pipeline_progress(interval=0.1, max_duration=0.5)

    # First frame: connected
    first_chunk = next(gen).decode("utf-8")
    assert "event: connected" in first_chunk
    assert "pipeline_progress" in first_chunk

    # Emit event in background and consume from generator
    broadcaster.emit("stage_start", {"stage": 2, "name": "Transformation"})
    second_chunk = next(gen).decode("utf-8")
    assert "event: pipeline_event" in second_chunk
    assert "Transformation" in second_chunk

    broadcaster.reset()


def test_gateway_app_route_pipeline_stream() -> None:
    app = WSGIApplication()
    status_captured = []
    headers_captured = []

    def start_response(status: str, headers: List[tuple[str, str]]) -> None:
        status_captured.append(status)
        headers_captured.append(headers)

    environ = {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": "/api/stream/pipeline",
        "QUERY_STRING": "interval=0.2",
    }

    resp = app(environ, start_response)
    assert status_captured == ["200 OK"]
    header_dict = dict(headers_captured[0])
    assert header_dict.get("Content-Type") == "text/event-stream; charset=utf-8"

    # Consume first frame
    first_chunk = next(resp).decode("utf-8")
    assert "event: connected" in first_chunk
