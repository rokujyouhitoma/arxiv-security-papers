"""
src/core/profiler/storage.py
============================
PyNYTProf プロファイルデータ構造・集計エンジン・zlib 圧縮永続化層。
DSN-28 Section 4.2 & Section 4.4 準拠。

- 浮動小数点を一切使用せず、全時間を整数ナノ秒 (int) で累積。
- NYTProf 互換の all_stacks_by_time.calls ストリーム生成。
- コンパクトバイナリ / zlib 圧縮 JSON 永続化と高速復元。
"""

from __future__ import annotations

import json
import os
import platform
import re
import zlib
from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional, Tuple


@dataclass
class LineMetric:
    """行単位の実行メトリクス"""

    count: int = 0
    time_ns: int = 0

    def add(self, delta_ns: int) -> None:
        self.count += 1
        self.time_ns += delta_ns


@dataclass
class ArcMetric:
    """呼出元 (Caller) -> 呼出先 (Callee) の Call Arc メトリクス"""

    calls: int = 0
    inclusive_time_ns: int = 0
    exclusive_time_ns: int = 0

    def add(self, inclusive_ns: int, exclusive_ns: int) -> None:
        self.calls += 1
        self.inclusive_time_ns += inclusive_ns
        self.exclusive_time_ns += exclusive_ns


@dataclass
class SubroutineMetric:
    """サブルーチン・関数単位の集計メトリクス"""

    name: str
    filename: str
    first_line: int
    calls: int = 0
    inclusive_time_ns: int = 0
    exclusive_time_ns: int = 0
    suspend_time_ns: int = 0
    # 呼び出し元一覧: caller_name -> (calls, inclusive_ns, exclusive_ns)
    callers: Dict[str, List[int]] = field(default_factory=dict)
    # 呼び出し先一覧: callee_name -> (calls, inclusive_ns, exclusive_ns)
    callees: Dict[str, List[int]] = field(default_factory=dict)

    def record_call(
        self, caller: str, inc_ns: int, exc_ns: int, suspend_ns: int = 0
    ) -> None:
        self.calls += 1
        self.inclusive_time_ns += inc_ns
        self.exclusive_time_ns += exc_ns
        self.suspend_time_ns += suspend_ns
        if caller not in self.callers:
            self.callers[caller] = [0, 0, 0]
        self.callers[caller][0] += 1
        self.callers[caller][1] += inc_ns
        self.callers[caller][2] += exc_ns


@dataclass
class ProfileMetadata:
    """プロファイル実行メタデータ (DSN-28 Section 3.2 / 8.2 準拠)"""

    cmdline: List[str] = field(default_factory=list)
    start_time_iso: str = ""
    end_time_iso: str = ""
    total_time_ns: int = 0
    python_version: str = platform.python_version()
    platform_info: str = platform.platform()
    pid: int = field(default_factory=os.getpid)
    clock_type: str = "perf_counter_ns"
    mode: str = "line"
    calls_mode: int = 1
    # --- W3C TraceContext 連携フィールド (DSN-28 Section 8.2 / DSN-10 統合) ---
    # traceparent ヘッダから抽出した trace_id (128-bit hex string)。
    # 空文字列の場合は TraceContext 未設定（スタンドアロン実行）を示す。
    trace_id: str = ""
    # W3C TraceContext の span_id (64-bit hex string)。
    span_id: str = ""
    # --- 機密情報スクラビング (DSN-28 Section 8.3 / CWE-532 準拠) ---
    # メタデータ・スタックトレース内の機密パターンを [REDACTED] に置換する。
    # 正規表現パターン文字列のリスト（シリアライズ互換のため str で保持）。
    scrub_patterns: List[str] = field(default_factory=list)


class ProfileData:
    """
    プロファイリングセッションの完全な集計データを保持するコンテナ。
    """

    def __init__(self, metadata: Optional[ProfileMetadata] = None) -> None:
        self.metadata = metadata or ProfileMetadata()
        # filename -> {line_num: LineMetric}
        self.lines: Dict[str, Dict[int, LineMetric]] = {}
        # sub_name -> SubroutineMetric
        self.subroutines: Dict[str, SubroutineMetric] = {}
        # (caller, callee) -> ArcMetric
        self.arcs: Dict[Tuple[str, str], ArcMetric] = {}
        # セミコロン区切りスタックトレース -> 合計時間(ns)
        # 例: "main;foo;bar" -> 154000
        self.stack_traces: Dict[str, int] = {}
        # 実行中にロードされたソースファイル内容キャッシュ (file_path -> content)
        self.source_files: Dict[str, str] = {}

    def record_line(self, filename: str, line_no: int, delta_ns: int) -> None:
        """行実行メトリクスを記録"""
        if filename not in self.lines:
            self.lines[filename] = {}
        file_lines = self.lines[filename]
        if line_no not in file_lines:
            file_lines[line_no] = LineMetric()
        file_lines[line_no].add(delta_ns)

    def _record_callee(
        self, caller_name: str, sub_name: str, inc_ns: int, exc_ns: int
    ) -> None:
        """呼び出し元の callee リストを更新"""
        if not caller_name:
            return
        if caller_name not in self.subroutines:
            self.subroutines[caller_name] = SubroutineMetric(
                name=caller_name, filename="", first_line=0
            )
        caller_sub = self.subroutines[caller_name]
        if sub_name not in caller_sub.callees:
            caller_sub.callees[sub_name] = [0, 0, 0]
        caller_sub.callees[sub_name][0] += 1
        caller_sub.callees[sub_name][1] += inc_ns
        caller_sub.callees[sub_name][2] += exc_ns

    def _record_arc(
        self, caller_name: str, sub_name: str, inc_ns: int, exc_ns: int
    ) -> None:
        """呼出アークメトリクスを記録"""
        arc_key = (caller_name, sub_name)
        if arc_key not in self.arcs:
            self.arcs[arc_key] = ArcMetric()
        self.arcs[arc_key].add(inc_ns, exc_ns)

    @staticmethod
    def _update_sub_location(
        sub: SubroutineMetric, filename: str, first_line: int
    ) -> None:
        """サブルーチンの未設定ファイル・行番号を補完"""
        if not sub.filename and filename:
            sub.filename = filename
        if not sub.first_line and first_line:
            sub.first_line = first_line

    def record_subroutine_exit(
        self,
        sub_name: str,
        filename: str,
        first_line: int,
        caller_name: str,
        inclusive_ns: int,
        exclusive_ns: int,
        suspend_ns: int = 0,
    ) -> None:
        """サブルーチン終了時のメトリクスを加算"""
        if sub_name not in self.subroutines:
            self.subroutines[sub_name] = SubroutineMetric(
                name=sub_name, filename=filename, first_line=first_line
            )
        sub = self.subroutines[sub_name]
        self._update_sub_location(sub, filename, first_line)
        sub.record_call(caller_name, inclusive_ns, exclusive_ns, suspend_ns)

        self._record_callee(caller_name, sub_name, inclusive_ns, exclusive_ns)
        self._record_arc(caller_name, sub_name, inclusive_ns, exclusive_ns)

    def record_stack_trace(self, stack_str: str, time_ns: int) -> None:
        """コールスタック実行時間を集計"""
        self.stack_traces[stack_str] = self.stack_traces.get(stack_str, 0) + time_ns

    def cache_source_file(self, filename: str) -> None:
        """HTMLレポート生成用にソースファイルをキャッシュ"""
        if filename in self.source_files or not os.path.isfile(filename):
            return
        try:
            with open(filename, "r", encoding="utf-8", errors="replace") as f:
                self.source_files[filename] = f.read()
        except Exception:
            pass

    def to_dict(self) -> Dict[str, Any]:
        """直列化可能な辞書へ変換"""
        lines_serialized = {
            fname: {
                str(lno): {"count": m.count, "time_ns": m.time_ns}
                for lno, m in file_lines.items()
            }
            for fname, file_lines in self.lines.items()
        }

        subs_serialized = {}
        for sname, sub in self.subroutines.items():
            subs_serialized[sname] = {
                "name": sub.name,
                "filename": sub.filename,
                "first_line": sub.first_line,
                "calls": sub.calls,
                "inclusive_time_ns": sub.inclusive_time_ns,
                "exclusive_time_ns": sub.exclusive_time_ns,
                "suspend_time_ns": sub.suspend_time_ns,
                "callers": sub.callers,
                "callees": sub.callees,
            }

        arcs_serialized = [
            {
                "caller": k[0],
                "callee": k[1],
                "calls": m.calls,
                "inc_ns": m.inclusive_time_ns,
                "exc_ns": m.exclusive_time_ns,
            }
            for k, m in self.arcs.items()
        ]

        return {
            "version": "1.0.0",
            "metadata": asdict(self.metadata),
            "lines": lines_serialized,
            "subroutines": subs_serialized,
            "arcs": arcs_serialized,
            "stack_traces": self.stack_traces,
            "source_files": self.source_files,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> ProfileData:
        """辞書から復元"""
        meta_dict = data.get("metadata", {})
        metadata = ProfileMetadata(**meta_dict)
        profile = cls(metadata=metadata)

        for fname, file_lines in data.get("lines", {}).items():
            profile.lines[fname] = {}
            for lno_str, m_dict in file_lines.items():
                profile.lines[fname][int(lno_str)] = LineMetric(
                    count=m_dict.get("count", 0),
                    time_ns=m_dict.get("time_ns", 0),
                )

        for sname, s_dict in data.get("subroutines", {}).items():
            sub = SubroutineMetric(
                name=s_dict["name"],
                filename=s_dict["filename"],
                first_line=s_dict["first_line"],
                calls=s_dict.get("calls", 0),
                inclusive_time_ns=s_dict.get("inclusive_time_ns", 0),
                exclusive_time_ns=s_dict.get("exclusive_time_ns", 0),
                suspend_time_ns=s_dict.get("suspend_time_ns", 0),
                callers=s_dict.get("callers", {}),
                callees=s_dict.get("callees", {}),
            )
            profile.subroutines[sname] = sub

        for arc in data.get("arcs", []):
            k = (arc["caller"], arc["callee"])
            profile.arcs[k] = ArcMetric(
                calls=arc.get("calls", 0),
                inclusive_time_ns=arc.get("inc_ns", 0),
                exclusive_time_ns=arc.get("exc_ns", 0),
            )

        profile.stack_traces = data.get("stack_traces", {})
        profile.source_files = data.get("source_files", {})
        return profile


class ProfileStorage:
    """
    プロファイルデータの保存・ロード・エクスポートを管掌するストレージクラス。

    バイナリストリーム形式 (DSN-28 Section 3.2 BNF)::

        file    = magic version compressed_json
        magic   = b'PYNYTPROF\\x01'  ; 10 バイト固定
        version = <埋め込み済み; magic 末尾 \\x01 が v1 を示す>
        compressed_json = zlib.compress(json_utf8_bytes, level=6)

    将来拡張のためのチャンク形式への移行は v2 以降で検討する。
    """

    MAGIC_HEADER = b"PYNYTPROF\x01"

    @classmethod
    def save(cls, profile: ProfileData, filepath: str) -> None:
        """
        zlib 圧縮付き JSON バイナリ形式でファイルへ永続化。
        機密スクラビングパターンが設定されている場合は保存前にスクラブを実行する。
        """
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        data_dict = profile.to_dict()
        # 機密スクラビング (DSN-28 Section 8.3)
        scrub_patterns = profile.metadata.scrub_patterns
        if scrub_patterns:
            raw_str = json.dumps(data_dict, ensure_ascii=False)
            for pattern in scrub_patterns:
                try:
                    raw_str = re.sub(pattern, "[REDACTED]", raw_str)
                except re.error:
                    pass
            raw_json = raw_str.encode("utf-8")
        else:
            raw_json = json.dumps(data_dict, ensure_ascii=False).encode("utf-8")
        compressed = zlib.compress(raw_json, level=6)
        with open(filepath, "wb") as f:
            f.write(cls.MAGIC_HEADER)
            f.write(compressed)

    @classmethod
    def load(cls, filepath: str) -> ProfileData:
        """
        保存ファイルから ProfileData を復元。
        """
        with open(filepath, "rb") as f:
            header = f.read(len(cls.MAGIC_HEADER))
            if header != cls.MAGIC_HEADER:
                # プレーンJSONフォールバック
                f.seek(0)
                try:
                    data = json.loads(f.read().decode("utf-8"))
                    return ProfileData.from_dict(data)
                except Exception as e:
                    raise ValueError(
                        f"Invalid PyNYTProf file format: {filepath}"
                    ) from e

            compressed = f.read()
            decompressed = zlib.decompress(compressed)
            data = json.loads(decompressed.decode("utf-8"))
            return ProfileData.from_dict(data)

    @classmethod
    def export_calls_file(cls, profile: ProfileData, filepath: str) -> None:
        """
        Flame Graph 生成用および grep 用の all_stacks_by_time.calls ファイルを出力。
        フォーマット:
        <sub1>;<sub2>;<sub3> <time_ns>
        """
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        with open(filepath, "w", encoding="utf-8") as f:
            for stack, time_ns in sorted(profile.stack_traces.items()):
                f.write(f"{stack} {time_ns}\n")
