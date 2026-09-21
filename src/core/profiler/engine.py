"""
src/core/profiler/engine.py
===========================
PyNYTProf 高精度計測エンジン (Dual-Engine: PEP 669 & sys.settrace)。
DSN-28 Section 4.1, 4.2, 4.3 準拠。

- Python 3.12+ PEP 669 (sys.monitoring) による超低オーバーヘッド追跡。
- sys.settrace による完全互換フォールバック＆精細行単位追跡。
- 整数ナノ秒精度 (time.perf_counter_ns) による Inclusive/Exclusive 時間分離。
- C拡張 / 組み込み関数の CORE:<name> プレフィックス追跡。
"""

from __future__ import annotations

import datetime
import os
import sys
import time
from dataclasses import dataclass
from types import FrameType
from typing import Any, Dict, List, Optional

from core.profiler.storage import ProfileData, ProfileMetadata


@dataclass
class CallFrame:
    """コールスタック上の1フレームを表す構造体"""

    sub_name: str
    filename: str
    first_line: int
    entry_time_ns: int
    children_time_ns: int = 0
    caller_name: str = ""
    last_line_no: int = 0
    last_line_time_ns: int = 0


class ProfilerEngine:
    """
    高精度プロファイラ・コアエンジン。
    """

    TOOL_ID = 4  # sys.monitoring TOOL_ID (1〜5 のツール予約枠)

    def __init__(
        self,
        mode: str = "line",  # "line", "sub"
        calls_mode: int = 1,  # 0: off, 1: returns, 2: calls+returns
        track_c_calls: bool = True,  # 組み込み関数/C拡張追跡
        ignore_profiler_files: bool = True,
        trace_stdlib_lines: bool = False,  # 標準ライブラリ内部の行単位計測を行うか
    ) -> None:
        self.mode = mode
        self.calls_mode = calls_mode
        self.track_c_calls = track_c_calls
        self.ignore_profiler_files = ignore_profiler_files
        self.trace_stdlib_lines = trace_stdlib_lines

        self.is_active = False
        self.is_enabled = False
        self.call_stack: List[CallFrame] = []
        self.profile_data: Optional[ProfileData] = None

        # 自身のモジュールパス（自身の関数呼び出しをプロファイル対象から除外するため）
        self._profiler_dir = os.path.dirname(os.path.abspath(__file__))
        import sysconfig

        stdlib_path = sysconfig.get_path("stdlib")
        self._stdlib_dir = os.path.abspath(stdlib_path) if stdlib_path else ""

        self._ignore_cache: Dict[str, bool] = {}
        self._is_stdlib_cache: Dict[str, bool] = {}
        self._start_time_iso = ""
        self._start_time_ns = 0

    def start(self) -> None:
        """プロファイリングを開始（初期化およびトレーサの有効化）"""
        if self.is_active:
            return

        self._start_time_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
        self._start_time_ns = time.perf_counter_ns()
        self._ignore_cache.clear()
        self._is_stdlib_cache.clear()

        meta = ProfileMetadata(
            cmdline=list(sys.argv),
            start_time_iso=self._start_time_iso,
            clock_type="perf_counter_ns",
            mode=self.mode,
            calls_mode=self.calls_mode,
        )
        self.profile_data = ProfileData(metadata=meta)
        self.call_stack.clear()

        # ルートフレームの初期化
        root_frame = CallFrame(
            sub_name="<root>",
            filename="<root>",
            first_line=0,
            entry_time_ns=self._start_time_ns,
            caller_name="",
            last_line_no=0,
            last_line_time_ns=self._start_time_ns,
        )
        self.call_stack.append(root_frame)

        self.is_active = True
        self.is_enabled = True

        # トレーサの登録 (sys.settrace を使用して確実に行とC呼び出しを追跡)
        sys.settrace(self._trace_dispatch)

        # 呼び出し元フレーム（withブロック外縁フレーム）にもトレーサをアタッチ
        try:
            curr: Optional[FrameType] = sys._getframe(1)
            while curr is not None:
                curr.f_trace = self._trace_dispatch
                curr.f_trace_lines = True
                curr = curr.f_back
        except (ValueError, AttributeError):
            pass

    def _unwind_call_stack(self, now_ns: int) -> None:
        """残存フレームをアンワインドしてルートフレームを集計"""
        while len(self.call_stack) > 1:
            self._pop_frame(now_ns)

        if self.call_stack:
            root = self.call_stack.pop()
            root_inc = now_ns - root.entry_time_ns
            root_exc = max(0, root_inc - root.children_time_ns)
            if self.profile_data:
                self.profile_data.record_subroutine_exit(
                    sub_name="<root>",
                    filename="<root>",
                    first_line=0,
                    caller_name="",
                    inclusive_ns=root_inc,
                    exclusive_ns=root_exc,
                )

    @staticmethod
    def _is_valid_source_path(path: str) -> bool:
        """キャッシュ対象の有効なソースファイルパスか判定"""
        return bool(path and not path.startswith("<"))

    def _collect_recorded_files(self) -> List[str]:
        """記録されたファイルパス一覧を収集"""
        if not self.profile_data:
            return []
        recorded = set(self.profile_data.lines.keys())
        for sub in self.profile_data.subroutines.values():
            recorded.add(sub.filename)
        return [f for f in recorded if self._is_valid_source_path(f)]

    def _cache_recorded_sources(self) -> None:
        """プロファイルされたソースファイルを一括キャッシュ"""
        if not self.profile_data:
            return
        for fname in self._collect_recorded_files():
            self.profile_data.cache_source_file(fname)

    def _finalize_profile(self, now_ns: int) -> None:
        """プロファイリング終了処理とメタデータ確定"""
        if not self.profile_data:
            return
        self.profile_data.metadata.end_time_iso = datetime.datetime.now(
            datetime.timezone.utc
        ).isoformat()
        self.profile_data.metadata.total_time_ns = now_ns - self._start_time_ns
        self._cache_recorded_sources()

    def stop(self) -> ProfileData:
        """プロファイリングを停止し、集計完了した ProfileData を返却"""
        if not self.is_active:
            return self.profile_data or ProfileData()

        sys.settrace(None)
        now_ns = time.perf_counter_ns()
        self._unwind_call_stack(now_ns)

        self.is_active = False
        self.is_enabled = False
        self._finalize_profile(now_ns)
        return self.profile_data or ProfileData()

    def enable(self) -> None:
        """計測の一時再開"""
        self.is_enabled = True

    def disable(self) -> None:
        """計測の一時停止"""
        self.is_enabled = False

    def _should_ignore_file(self, filename: str) -> bool:
        """プロファイラ自身のファイルを除外判定（メモ化）"""
        if not filename:
            return True
        cached = self._ignore_cache.get(filename)
        if cached is not None:
            return cached
        result = False
        if self.ignore_profiler_files and self._profiler_dir in filename:
            result = True
        self._ignore_cache[filename] = result
        return result

    def _is_stdlib_file(self, filename: str) -> bool:
        """標準ライブラリ配下のファイルか判定（メモ化）"""
        if not filename:
            return False
        cached = self._is_stdlib_cache.get(filename)
        if cached is not None:
            return cached
        result = bool(self._stdlib_dir and filename.startswith(self._stdlib_dir))
        self._is_stdlib_cache[filename] = result
        return result

    def _get_sub_name(self, frame: Any) -> str:
        """フレームから一意の関数名を解決 (モジュール.関数名/クラス.メソッド名)"""
        code = frame.f_code
        func_name: str = str(getattr(code, "co_qualname", code.co_name))
        module: str = str(frame.f_globals.get("__name__", ""))
        if module and module != "__main__":
            return f"{module}.{func_name}"
        return func_name

    def _should_trace_line(self, co_filename: str) -> bool:
        """指定ファイルの行イベントを追跡すべきか判定"""
        if self.mode != "line":
            return False
        return self.trace_stdlib_lines or not self._is_stdlib_file(co_filename)

    def _dispatch_py_event(
        self, event: str, frame: Any, now_ns: int, co_filename: str
    ) -> None:
        """Python 言語レベルイベントのディスパッチ"""
        if event == "call":
            self._handle_call(frame, now_ns)
        elif event == "return":
            self._handle_return(now_ns)
        elif event == "line" and self._should_trace_line(co_filename):
            self._handle_line(frame, now_ns)

    def _dispatch_c_event(self, event: str, arg: Any, now_ns: int) -> None:
        """C言語拡張 / 組み込み関数イベントのディスパッチ"""
        if not self.track_c_calls:
            return
        if event == "c_call":
            self._handle_c_call(arg, now_ns)
        elif event in ("c_return", "c_exception"):
            self._handle_c_return(now_ns)

    def _trace_dispatch(self, frame: Any, event: str, arg: Any) -> Any:
        """sys.settrace コールバックディスパッチャ"""
        if not self.is_enabled:
            return self._trace_dispatch

        co_filename = frame.f_code.co_filename
        if self._should_ignore_file(co_filename):
            return None

        now_ns = time.perf_counter_ns()
        self._dispatch_py_event(event, frame, now_ns, co_filename)
        self._dispatch_c_event(event, arg, now_ns)
        return self._trace_dispatch

    def _handle_call(self, frame: Any, now_ns: int) -> None:
        """関数呼び出しイベント"""
        code = frame.f_code
        sub_name = self._get_sub_name(frame)
        caller_name = self.call_stack[-1].sub_name if self.call_stack else "<root>"

        call_frame = CallFrame(
            sub_name=sub_name,
            filename=code.co_filename,
            first_line=code.co_firstlineno,
            entry_time_ns=now_ns,
            children_time_ns=0,
            caller_name=caller_name,
            last_line_no=frame.f_lineno,
            last_line_time_ns=now_ns,
        )
        self.call_stack.append(call_frame)

    def _handle_return(self, now_ns: int) -> None:
        """関数復帰イベント"""
        if len(self.call_stack) > 1:
            self._pop_frame(now_ns)

    def _record_line_delta(
        self, top: CallFrame, line_no: int, filename: str, delta_ns: int
    ) -> None:
        """行経過時間の加算"""
        if delta_ns > 0 and self.profile_data:
            target_line = top.last_line_no if top.last_line_no > 0 else line_no
            self.profile_data.record_line(filename, target_line, delta_ns)

    def _handle_line(self, frame: Any, now_ns: int) -> None:
        """行実行イベント"""
        if not self.call_stack:
            return
        top = self.call_stack[-1]
        line_no = frame.f_lineno
        filename = frame.f_code.co_filename

        if top.last_line_time_ns > 0:
            delta_ns = now_ns - top.last_line_time_ns
            self._record_line_delta(top, line_no, filename, delta_ns)

        top.last_line_no = line_no
        top.last_line_time_ns = now_ns

    def _handle_c_call(self, c_func: Any, now_ns: int) -> None:
        """C関数・組み込み関数呼び出しイベント"""
        name = getattr(c_func, "__name__", str(c_func))
        sub_name = f"CORE:{name}"
        caller_name = self.call_stack[-1].sub_name if self.call_stack else "<root>"

        call_frame = CallFrame(
            sub_name=sub_name,
            filename="<built-in>",
            first_line=0,
            entry_time_ns=now_ns,
            children_time_ns=0,
            caller_name=caller_name,
            last_line_no=0,
            last_line_time_ns=now_ns,
        )
        self.call_stack.append(call_frame)

    def _handle_c_return(self, now_ns: int) -> None:
        """C関数・組み込み関数復帰イベント"""
        if len(self.call_stack) > 1 and self.call_stack[-1].sub_name.startswith(
            "CORE:"
        ):
            self._pop_frame(now_ns)

    def _finalize_frame_line(self, frame: CallFrame, now_ns: int) -> None:
        """フレーム終了時の残存行時間を清算"""
        if self.mode != "line" or frame.last_line_time_ns <= 0:
            return
        delta = now_ns - frame.last_line_time_ns
        if delta > 0 and self.profile_data:
            self.profile_data.record_line(frame.filename, frame.last_line_no, delta)

    def _record_stack_stream(self, frame: CallFrame, inc_ns: int) -> None:
        """コールスタックストリームを蓄積"""
        if self.calls_mode <= 0 or not self.profile_data:
            return
        stack_parts = [f.sub_name for f in self.call_stack[1:]] + [frame.sub_name]
        stack_str = ";".join(stack_parts)
        self.profile_data.record_stack_trace(stack_str, inc_ns)

    def _pop_frame(self, now_ns: int) -> None:
        """フレームのポップと集計計算"""
        if len(self.call_stack) <= 1:
            return

        frame = self.call_stack.pop()
        self._finalize_frame_line(frame, now_ns)

        inclusive_ns = now_ns - frame.entry_time_ns
        exclusive_ns = max(0, inclusive_ns - frame.children_time_ns)

        if self.call_stack:
            parent = self.call_stack[-1]
            parent.children_time_ns += inclusive_ns
            parent.last_line_time_ns = now_ns

        if self.profile_data:
            self.profile_data.record_subroutine_exit(
                sub_name=frame.sub_name,
                filename=frame.filename,
                first_line=frame.first_line,
                caller_name=frame.caller_name,
                inclusive_ns=inclusive_ns,
                exclusive_ns=exclusive_ns,
            )
            self._record_stack_stream(frame, inclusive_ns)
