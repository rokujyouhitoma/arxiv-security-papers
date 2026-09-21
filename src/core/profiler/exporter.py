"""
src/core/profiler/exporter.py
=============================
PyNYTProf Callgrind (KCachegrind / QCacheGrind 互換) エクスポートエンジン。
DSN-28 Section 6.1 準拠。

- プロファイルデータを標準 Callgrind 形式で出力。
- KCachegrind 等でコールツリーマップおよび有向グラフのビジュアル探索が可能。
"""

from __future__ import annotations

import os
from typing import Any, Dict, List

from core.profiler.storage import ProfileData


class CallgrindExporter:
    """
    ProfileData から Callgrind 形式テキストファイルを生成するエクスポータ。
    """

    @classmethod
    def _build_header(cls, profile: ProfileData) -> List[str]:
        """Callgrind ヘッダー行を生成"""
        total_time_ns = profile.metadata.total_time_ns
        if total_time_ns <= 0 and profile.subroutines:
            total_time_ns = sum(
                s.exclusive_time_ns for s in profile.subroutines.values()
            )
        cmd_str = (
            " ".join(profile.metadata.cmdline) if profile.metadata.cmdline else "python"
        )
        return [
            "version: 1",
            "creator: PyNYTProf (DSN-28)",
            f"pid: {profile.metadata.pid}",
            f"cmd: {cmd_str}",
            "part: 1",
            "positions: line",
            "events: Nanoseconds",
            f"summary: {total_time_ns}",
            "",
        ]

    @staticmethod
    def _group_by_file(
        subs: Any,
    ) -> Dict[str, List[Any]]:
        """サブルーチンをファイル名単位でグループ化"""
        files_map: Dict[str, List[Any]] = {}
        for sub in subs:
            fname = sub.filename or "<unknown>"
            if fname not in files_map:
                files_map[fname] = []
            files_map[fname].append(sub)
        return files_map

    @classmethod
    def _format_callee(
        cls,
        profile: ProfileData,
        filename: str,
        first_line: int,
        callee_name: str,
        vals: List[int],
    ) -> List[str]:
        """単一の callee 呼出ブロックを整形"""
        calls_count, inc_time = vals[0], vals[1]
        callee_sub = profile.subroutines.get(callee_name)
        callee_file = callee_sub.filename if callee_sub else filename
        callee_line = callee_sub.first_line if callee_sub else 1

        res = []
        if callee_file != filename:
            res.append(f"cfl={callee_file}")
        res.append(f"cfn={callee_name}")
        res.append(f"calls={calls_count} {callee_line}")
        res.append(f"{first_line} {inc_time}")
        return res

    @classmethod
    def _format_sub(cls, profile: ProfileData, filename: str, sub: Any) -> List[str]:
        """サブルーチンのエントリ行を整形"""
        first_line = sub.first_line or 1
        res = [f"fn={sub.name}", f"{first_line} {sub.exclusive_time_ns}"]
        for callee_name, vals in sub.callees.items():
            res.extend(
                cls._format_callee(profile, filename, first_line, callee_name, vals)
            )
        res.append("")
        return res

    @classmethod
    def export(cls, profile: ProfileData, filepath: str) -> None:
        """Callgrind 形式ファイルを出力"""
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        lines = cls._build_header(profile)

        files_map = cls._group_by_file(profile.subroutines.values())
        for filename, subs in files_map.items():
            lines.append(f"fl={filename}")
            for sub in subs:
                lines.extend(cls._format_sub(profile, filename, sub))

        with open(filepath, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
