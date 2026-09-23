"""
src/core/profiler/__init__.py
=============================
PyNYTProf: Python 版 NYTProf 高精度プロファイラ ＆ 可視化統合スイート。
DSN-28 準拠。

公開 API:
- Profiler: コンテキストマネージャ
- profile: 関数デコレータ
- pynytprof_start, pynytprof_stop, pynytprof_enable, pynytprof_disable
- ProfileData, ProfileStorage
"""

from __future__ import annotations

import functools
from typing import Any, Callable, Optional

from core.profiler.chart import FlameChartGenerator, TraceEventExporter
from core.profiler.diff import ProfileDiffer
from core.profiler.engine import ProfilerEngine
from core.profiler.exporter import CallgrindExporter
from core.profiler.flamegraph import FlameGraphGenerator
from core.profiler.merge import ProfileMerger
from core.profiler.reporter import HTMLReporter
from core.profiler.sampling import SamplingEngine, SamplingProfiler
from core.profiler.storage import (
    ProfileData,
    ProfileMetadata,
    ProfileStorage,
    TimelineEvent,
)

_GLOBAL_ENGINE: Optional[ProfilerEngine] = None


class Profiler:
    """
    コンテキストマネージャ形式のプロファイラ。
    使用例:
        with Profiler(output_file="prof.out", mode="line") as p:
            heavy_work()
    """

    def __init__(
        self,
        output_file: Optional[str] = None,
        mode: str = "line",
        calls_mode: int = 1,
        track_c_calls: bool = True,
    ) -> None:
        self.output_file = output_file
        self.engine = ProfilerEngine(
            mode=mode, calls_mode=calls_mode, track_c_calls=track_c_calls
        )
        self.profile_data: Optional[ProfileData] = None

    def __enter__(self) -> Profiler:
        self.engine.start()
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.profile_data = self.engine.stop()
        if self.output_file and self.profile_data:
            ProfileStorage.save(self.profile_data, self.output_file)


def profile(
    output_file: Optional[str] = None,
    mode: str = "line",
    calls_mode: int = 1,
) -> Callable[..., Any]:
    """
    関数デコレータ。
    使用例:
        @profile(output_file="fib.out")
        def fib(n):
            ...
    """

    def decorator(func: Callable[..., Any]) -> Callable[..., Any]:
        @functools.wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            with Profiler(output_file=output_file, mode=mode, calls_mode=calls_mode):
                return func(*args, **kwargs)

        return wrapper

    return decorator


def pynytprof_start(mode: str = "line", calls_mode: int = 1) -> None:
    """グローバルプロファイラを開始"""
    global _GLOBAL_ENGINE
    if _GLOBAL_ENGINE is None:
        _GLOBAL_ENGINE = ProfilerEngine(mode=mode, calls_mode=calls_mode)
    _GLOBAL_ENGINE.start()


def pynytprof_stop(output_file: Optional[str] = None) -> ProfileData:
    """グローバルプロファイラを停止し、データを保存/返却"""
    global _GLOBAL_ENGINE
    if _GLOBAL_ENGINE is None:
        return ProfileData()
    data = _GLOBAL_ENGINE.stop()
    if output_file:
        ProfileStorage.save(data, output_file)
    _GLOBAL_ENGINE = None
    return data


def pynytprof_enable() -> None:
    """グローバルプロファイラの計測再開"""
    if _GLOBAL_ENGINE:
        _GLOBAL_ENGINE.enable()


def pynytprof_disable() -> None:
    """グローバルプロファイラの計測一時停止"""
    if _GLOBAL_ENGINE:
        _GLOBAL_ENGINE.disable()


def pynytprof_cli_main() -> None:
    """CLI エントリポイント（遅延インポート）"""
    from core.profiler.cli import main  # noqa: PLC0415

    main()


def parse_pynytprof_env(env_val: str) -> "dict[str, object]":
    """環境変数パーサ（遅延インポート）"""
    from core.profiler.cli import parse_pynytprof_env as _parse  # noqa: PLC0415

    return _parse(env_val)


__all__ = [
    "Profiler",
    "profile",
    "pynytprof_start",
    "pynytprof_stop",
    "pynytprof_enable",
    "pynytprof_disable",
    "ProfilerEngine",
    "FlameGraphGenerator",
    "HTMLReporter",
    "CallgrindExporter",
    "ProfileMerger",
    "ProfileData",
    "ProfileMetadata",
    "ProfileStorage",
    "SamplingEngine",
    "SamplingProfiler",
    "ProfileDiffer",
    "FlameChartGenerator",
    "TraceEventExporter",
    "TimelineEvent",
    "pynytprof_cli_main",
    "parse_pynytprof_env",
]
