"""
src/core/profiler/sampling.py
==============================
PyNYTProf 統計的サンプリングエンジン (SIGPROF / threading.Timer 駆動)。
DSN-28 Section 4.5 準拠。

- Python 標準ライブラリのみ使用（ゼロ外部依存）。
- SIGPROF / SIGALRM 利用可能環境ではシグナル駆動サンプリングを優先。
- Windows / スレッド非対応環境では threading.Timer フォールバック。
- 設計目標オーバーヘッド: +2% 未満（100 Hz サンプリング時）。
- ProfileData 互換の stack_traces 辞書へ直接集計。
"""

from __future__ import annotations

import signal
import sys
import threading
import time
from typing import Optional

from core.profiler.storage import ProfileData, ProfileMetadata


class SamplingEngine:
    """
    統計的サンプリング・プロファイラ。

    SIGPROF または threading.Timer を使用して定期的にコールスタックを採取し、
    ProfileData.stack_traces に集計する。

    使用例::

        engine = SamplingEngine(interval_sec=0.01)  # 100 Hz
        engine.start()
        heavy_work()
        data = engine.stop()

    本番パイプライン用途（低オーバーヘッド優先）では mode="sub" 相当の
    スタック集計のみ行い、行単位計測は行わない。
    """

    # SIGPROF は POSIX のみ。Windows では AttributeError になるためガード。
    _SIGPROF: Optional[int] = getattr(signal, "SIGPROF", None)
    # SIGALRM は Unix のみ（macOS/Linux）
    _SIGALRM: Optional[int] = getattr(signal, "SIGALRM", None)

    def __init__(
        self,
        interval_sec: float = 0.01,
        use_signal: bool = True,
    ) -> None:
        """
        Args:
            interval_sec: サンプリング間隔（秒）。デフォルト 0.01s = 100 Hz。
            use_signal: シグナル駆動サンプリングを試みるか。False の場合は
                        threading.Timer フォールバック固定。
        """
        self.interval_sec = interval_sec
        self._use_signal = use_signal and self._SIGPROF is not None

        self._profile_data: Optional[ProfileData] = None
        self._is_active = False
        self._timer: Optional[threading.Timer] = None
        self._lock = threading.Lock()
        self._sample_count = 0
        self._start_time_ns: int = 0

    # ------------------------------------------------------------------
    # 公開 API
    # ------------------------------------------------------------------

    def start(self) -> None:
        """サンプリングを開始する。"""
        if self._is_active:
            return

        self._start_time_ns = time.perf_counter_ns()
        meta = ProfileMetadata(
            cmdline=list(sys.argv),
            start_time_iso=_iso_now(),
            clock_type="perf_counter_ns (sampling)",
            mode="sampling",
            calls_mode=1,
        )
        self._profile_data = ProfileData(metadata=meta)
        self._sample_count = 0
        self._is_active = True

        if self._use_signal:
            self._start_signal_mode()
        else:
            self._start_timer_mode()

    def stop(self) -> ProfileData:
        """サンプリングを停止し、集計済み ProfileData を返す。"""
        if not self._is_active:
            return self._profile_data or ProfileData()
        self._is_active = False
        self._stop_engine()
        self._finalize_metadata()
        return self._profile_data or ProfileData()

    def _stop_engine(self) -> None:
        """エンジンを停止する。"""
        if self._use_signal and self._SIGPROF is not None:
            self._stop_signal_mode()
        else:
            self._stop_timer_mode()

    def _finalize_metadata(self) -> None:
        """プロファイルメタデータを確定する。"""
        if self._profile_data:
            now_ns = time.perf_counter_ns()
            self._profile_data.metadata.total_time_ns = now_ns - self._start_time_ns
            self._profile_data.metadata.end_time_iso = _iso_now()

    @property
    def sample_count(self) -> int:
        """採取済みサンプル数。"""
        return self._sample_count

    # ------------------------------------------------------------------
    # シグナル駆動モード（POSIX 限定）
    # ------------------------------------------------------------------

    def _start_signal_mode(self) -> None:
        """SIGPROF シグナルハンドラを登録し、インターバルタイマを起動する。"""
        assert self._SIGPROF is not None
        signal.signal(self._SIGPROF, self._sigprof_handler)
        # setitimer: (interval_sec, initial_delay) — 両方同値で繰り返し発火
        signal.setitimer(
            signal.ITIMER_PROF,
            self.interval_sec,
            self.interval_sec,
        )

    def _stop_signal_mode(self) -> None:
        """インターバルタイマを停止し、シグナルハンドラをデフォルトに戻す。"""
        assert self._SIGPROF is not None
        signal.setitimer(signal.ITIMER_PROF, 0)
        signal.signal(self._SIGPROF, signal.SIG_DFL)

    def _sigprof_handler(self, signum: int, frame: object) -> None:  # noqa: ARG002
        """SIGPROF ハンドラ: 現在のコールスタックを記録する。"""
        self._capture_stack(frame)

    # ------------------------------------------------------------------
    # threading.Timer フォールバックモード
    # ------------------------------------------------------------------

    def _start_timer_mode(self) -> None:
        """threading.Timer による定期サンプリングを開始する。"""
        self._schedule_timer()

    def _stop_timer_mode(self) -> None:
        """タイマを停止する。"""
        if self._timer is not None:
            self._timer.cancel()
            self._timer = None

    def _schedule_timer(self) -> None:
        """次のタイマをスケジュールする。"""
        if not self._is_active:
            return
        self._timer = threading.Timer(self.interval_sec, self._timer_callback)
        self._timer.daemon = True
        self._timer.start()

    def _timer_callback(self) -> None:
        """タイマコールバック: サンプル採取後に次のタイマを予約する。"""
        if not self._is_active:
            return
        # threading.Timer 経由の場合、フレームはタイマスレッド内のものになるが、
        # sys._current_frames() で全スレッドのフレームを取得して集計する。
        self._capture_all_thread_stacks()
        self._schedule_timer()

    # ------------------------------------------------------------------
    # スタックキャプチャ
    # ------------------------------------------------------------------

    def _capture_stack(self, frame: object) -> None:
        """単一フレームチェーンからスタック文字列を構築して集計する。"""
        if self._profile_data is None:
            return
        parts = self._frame_to_parts(frame)
        if not parts:
            return
        parts.reverse()
        stack_str = ";".join(parts)
        time_ns = int(self.interval_sec * 1_000_000_000)
        with self._lock:
            self._profile_data.record_stack_trace(stack_str, time_ns)
            self._sample_count += 1

    @staticmethod
    def _frame_to_parts(frame: object) -> "list[str]":
        """フレームチェーンから関数ラベルリストを構築する。"""
        parts: list[str] = []
        f = frame
        while f is not None:
            code = getattr(f, "f_code", None)
            if code is None:
                break
            module = getattr(f, "f_globals", {}).get("__name__", "")
            qualname = getattr(code, "co_qualname", code.co_name)
            label = f"{module}.{qualname}" if module else qualname
            parts.append(label)
            f = getattr(f, "f_back", None)
        return parts

    def _capture_all_thread_stacks(self) -> None:
        """全スレッドのコールスタックを採取する（threading.Timer モード用）。"""
        if self._profile_data is None:
            return
        time_ns = int(self.interval_sec * 1_000_000_000)
        frames = sys._current_frames()  # {thread_id: frame}
        with self._lock:
            for _tid, frame in frames.items():
                stack_str = self._build_thread_stack(frame)
                if stack_str:
                    self._profile_data.record_stack_trace(stack_str, time_ns)
            self._sample_count += 1

    @staticmethod
    def _build_thread_stack(frame: object) -> str:
        """フレームチェーンからスタック文字列を構築する（スレッド単位）。"""
        parts: list[str] = []
        f: object = frame
        while f is not None:
            code = getattr(f, "f_code", None)
            if code is None:
                break
            module = getattr(f, "f_globals", {}).get("__name__", "")
            qualname = getattr(code, "co_qualname", code.co_name)
            label = f"{module}.{qualname}" if module else qualname
            parts.append(label)
            f = getattr(f, "f_back", None)
        if not parts:
            return ""
        parts.reverse()
        return ";".join(parts)


# ------------------------------------------------------------------
# コンテキストマネージャ便利 API
# ------------------------------------------------------------------


class SamplingProfiler:
    """
    コンテキストマネージャ形式のサンプリングプロファイラ。

    使用例::

        with SamplingProfiler(interval_sec=0.005) as sp:
            run_pipeline()
        data = sp.profile_data
    """

    def __init__(
        self,
        interval_sec: float = 0.01,
        output_file: Optional[str] = None,
        use_signal: bool = True,
    ) -> None:
        self.interval_sec = interval_sec
        self.output_file = output_file
        self._engine = SamplingEngine(
            interval_sec=interval_sec, use_signal=use_signal
        )
        self.profile_data: Optional[ProfileData] = None

    def __enter__(self) -> "SamplingProfiler":
        self._engine.start()
        return self

    def __exit__(self, *_: object) -> None:
        self.profile_data = self._engine.stop()
        if self.output_file and self.profile_data:
            from core.profiler.storage import ProfileStorage

            ProfileStorage.save(self.profile_data, self.output_file)

    @property
    def sample_count(self) -> int:
        return self._engine.sample_count


# ------------------------------------------------------------------
# ユーティリティ
# ------------------------------------------------------------------


def _iso_now() -> str:
    """現在時刻を ISO 8601 UTC 文字列で返す。"""
    import datetime

    return datetime.datetime.now(datetime.timezone.utc).isoformat()
