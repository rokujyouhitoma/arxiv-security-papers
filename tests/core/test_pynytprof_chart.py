"""
tests/core/test_pynytprof_chart.py
==================================
PyNYTProf 時系列 Flame Chart および Chrome Trace Event エクスポーターのテストスイート。
DSN-28 Section 9.2 (Phase 10: Issue 378) 準拠。
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile

from core.profiler.chart import FlameChartGenerator, TraceEventExporter
from core.profiler.cli import main
from core.profiler.engine import ProfilerEngine
from core.profiler.storage import (
    ProfileData,
    ProfileMetadata,
    ProfileStorage,
    SubroutineMetric,
    TimelineEvent,
)


class TestPyNYTProfChart:
    """Flame Chart & Trace Event エクスポーターの検証"""

    def test_trace_event_exporter_with_timeline(self) -> None:
        """TimelineEvent を保持する ProfileData から Chrome Trace JSON を生成"""
        profile = ProfileData(
            metadata=ProfileMetadata(cmdline=["test_app.py"], pid=1234)
        )
        profile.record_timeline_event(
            TimelineEvent(
                name="app.main",
                cat="function",
                entry_ns=1_000_000,
                exit_ns=5_000_000,
                inclusive_ns=4_000_000,
                exclusive_ns=1_000_000,
                suspend_ns=0,
                depth=1,
                caller="",
                filename="app.py",
                first_line=10,
                tid=100,
            )
        )
        profile.record_timeline_event(
            TimelineEvent(
                name="app.fetch_data",
                cat="coroutine",
                entry_ns=2_000_000,
                exit_ns=4_500_000,
                inclusive_ns=2_500_000,
                exclusive_ns=500_000,
                suspend_ns=2_000_000,
                depth=2,
                caller="app.main",
                filename="app.py",
                first_line=20,
                task_id=999,
                tid=100,
            )
        )

        trace_dict = TraceEventExporter.export_dict(profile)
        assert "traceEvents" in trace_dict
        assert trace_dict["displayTimeUnit"] == "ms"

        events = trace_dict["traceEvents"]
        # メタデータイベント (process_name, thread_name)
        meta_events = [e for e in events if e.get("ph") == "M"]
        assert len(meta_events) >= 2

        # 実行完了イベント (ph == "X")
        exec_events = [e for e in events if e.get("ph") == "X"]
        assert len(exec_events) == 2

        main_ev = next(e for e in exec_events if e["name"] == "app.main")
        assert main_ev["pid"] == 1234
        assert main_ev["tid"] == 100
        assert main_ev["dur"] == 4000.0  # 4ms in us
        assert main_ev["args"]["exclusive_ms"] == 1.0

        coro_ev = next(e for e in exec_events if e["name"] == "app.fetch_data")
        assert coro_ev["cat"] == "coroutine"
        assert coro_ev["args"]["suspend_ms"] == 2.0
        assert coro_ev["args"]["task_id"] == 999

        # ファイル出力検証
        with tempfile.TemporaryDirectory() as tmpdir:
            out_json = os.path.join(tmpdir, "trace.json")
            TraceEventExporter.export_file(profile, out_json)
            assert os.path.isfile(out_json)
            with open(out_json, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            assert len(loaded["traceEvents"]) == len(events)

    def test_trace_event_exporter_fallback(self) -> None:
        """timeline_events が空の場合のサブルーチンフォールバック生成"""
        profile = ProfileData(metadata=ProfileMetadata(pid=4321))
        profile.subroutines["foo"] = SubroutineMetric(
            name="foo",
            filename="foo.py",
            first_line=5,
            calls=1,
            inclusive_time_ns=3_000_000,
            exclusive_time_ns=3_000_000,
        )

        trace_dict = TraceEventExporter.export_dict(profile)
        exec_events = [e for e in trace_dict["traceEvents"] if e.get("ph") == "X"]
        assert len(exec_events) == 1
        assert exec_events[0]["name"] == "foo"
        assert exec_events[0]["dur"] == 3000.0

    def test_flame_chart_generator_svg_and_html(self) -> None:
        """FlameChartGenerator による SVG および HTML レポート生成"""
        profile = ProfileData(
            metadata=ProfileMetadata(pid=5555, total_time_ns=10_000_000)
        )
        profile.record_timeline_event(
            TimelineEvent(
                name="server.handle_request",
                cat="function",
                entry_ns=100_000,
                exit_ns=8_000_000,
                inclusive_ns=7_900_000,
                exclusive_ns=2_000_000,
                suspend_ns=0,
                depth=1,
                caller="",
                filename="server.py",
                first_line=50,
            )
        )

        # 1. SVG 生成
        svg = FlameChartGenerator.generate_svg(profile, width=1000)
        assert "<svg" in svg
        assert "</svg>" in svg
        assert 'class="pynytprof-flamechart"' in svg
        assert "server.handle_request" in svg
        assert 'class="chart-block"' in svg

        # 2. HTML 生成
        with tempfile.TemporaryDirectory() as tmpdir:
            out_html = os.path.join(tmpdir, "chart.html")
            html_text = FlameChartGenerator.generate_html(
                profile, out_path=out_html, title="Custom Test Chart"
            )
            assert os.path.isfile(out_html)
            assert "<!DOCTYPE html>" in html_text
            assert "Custom Test Chart" in html_text
            assert "Total Duration" in html_text
            assert "Details Inspector" in html_text
            # 外部スクリプト / CDN 依存がゼロであること
            assert "cdn." not in html_text
            assert '<script src="http' not in html_text
            assert '<link href="http' not in html_text
            assert '<script src="https' not in html_text
            assert '<link href="https' not in html_text

    def test_flame_chart_xss_sanitization(self) -> None:
        """悪意のある関数名やパスに対する厳格な XSS エスケープ"""
        profile = ProfileData()
        bad_name = "<script>alert('xss')</script>"
        bad_file = '"><img src=x onerror=alert(1)>'
        profile.record_timeline_event(
            TimelineEvent(
                name=bad_name,
                cat="function",
                entry_ns=0,
                exit_ns=1_000_000,
                inclusive_ns=1_000_000,
                exclusive_ns=1_000_000,
                depth=1,
                filename=bad_file,
                first_line=1,
            )
        )

        svg = FlameChartGenerator.generate_svg(profile)
        assert "<script>" not in svg
        assert "&lt;script&gt;" in svg
        assert "<img src=x" not in svg

        html_text = FlameChartGenerator.generate_html(
            profile, title="<script>alert(2)</script>"
        )
        assert "<script>alert(2)</script>" not in html_text
        assert "&lt;script&gt;alert(2)&lt;/script&gt;" in html_text

    def test_engine_calls_mode_2_captures_timeline(self) -> None:
        """ProfilerEngine(calls_mode=2) がタイムラインイベントを正常採取すること"""
        engine = ProfilerEngine(mode="sub", calls_mode=2)
        engine.start()

        def sub_a() -> int:
            return 42

        def sub_b() -> int:
            return sub_a() * 2

        val = sub_b()
        assert val == 84

        data = engine.stop()
        assert len(data.timeline_events) >= 2
        sub_names = [ev.name for ev in data.timeline_events]
        assert any("sub_a" in n for n in sub_names)
        assert any("sub_b" in n for n in sub_names)

    def test_cli_chart_subcommand_e2e(self) -> None:
        """CLI `pynytprof chart` および `tools/pynytprofchart` の E2E 検証"""
        with tempfile.TemporaryDirectory() as tmpdir:
            prof_file = os.path.join(tmpdir, "test.pynytprof.out")
            html_file = os.path.join(tmpdir, "chart.html")
            trace_file = os.path.join(tmpdir, "trace.json")

            # プロファイル作成 (calls_mode=2)
            profile = ProfileData(
                metadata=ProfileMetadata(pid=9999, total_time_ns=5_000_000)
            )
            profile.record_timeline_event(
                TimelineEvent(
                    name="cli_demo",
                    cat="function",
                    entry_ns=1000,
                    exit_ns=5000,
                    inclusive_ns=4000,
                    exclusive_ns=4000,
                    depth=1,
                    filename="demo.py",
                    first_line=1,
                )
            )
            ProfileStorage.save(profile, prof_file)

            # CLI main() 経由で chart サブコマンド実行
            ret = main(
                [
                    "chart",
                    "-i",
                    prof_file,
                    "-o",
                    html_file,
                    "--output-trace",
                    trace_file,
                ]
            )
            assert ret == 0
            assert os.path.isfile(html_file)
            assert os.path.isfile(trace_file)

            # tools/pynytprofchart スクリプトの実行確認
            chart_tool = os.path.join(
                os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
                "tools",
                "pynytprofchart",
            )
            out_tool_html = os.path.join(tmpdir, "tool_chart.html")
            res = subprocess.run(
                [sys.executable, chart_tool, "-i", prof_file, "-o", out_tool_html],
                capture_output=True,
                text=True,
                check=False,
            )
            assert res.returncode == 0
            assert os.path.isfile(out_tool_html)
