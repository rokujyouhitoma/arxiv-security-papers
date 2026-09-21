"""
src/core/profiler/merge.py
==========================
PyNYTProf マルチプロセス / 複数プロファイル統合マージエンジン。
DSN-28 Section 6.2 準拠。

- 複数プロセス (multiprocessing / fork) で生成された .pynytprof.out を合算統合。
- 行単位、サブルーチン単位、Call Arc、コールスタックストリームの算術的一致マージ。
"""

from __future__ import annotations

import os
from typing import Dict, List, Optional, Sequence

from core.profiler.storage import (
    ArcMetric,
    LineMetric,
    ProfileData,
    ProfileMetadata,
    ProfileStorage,
    SubroutineMetric,
)


class ProfileMerger:
    """
    複数プロファイルデータを単一の ProfileData に合算統合するエンジン。
    """

    @staticmethod
    def _merge_lines(merged: ProfileData, prof: ProfileData) -> None:
        """行メトリクスのマージ"""
        for filename, file_lines in prof.lines.items():
            if filename not in merged.lines:
                merged.lines[filename] = {}
            m_lines = merged.lines[filename]
            for lno, metric in file_lines.items():
                if lno not in m_lines:
                    m_lines[lno] = LineMetric(
                        count=metric.count, time_ns=metric.time_ns
                    )
                else:
                    m_lines[lno].count += metric.count
                    m_lines[lno].time_ns += metric.time_ns

    @staticmethod
    def _merge_caller_callee_map(
        target_map: Dict[str, List[int]], src_map: Dict[str, List[int]]
    ) -> None:
        """Caller/Callee リストのマージ"""
        for name, vals in src_map.items():
            if name not in target_map:
                target_map[name] = list(vals)
            else:
                target_map[name][0] += vals[0]
                target_map[name][1] += vals[1]
                target_map[name][2] += vals[2]

    @staticmethod
    def _update_sub_loc(target: SubroutineMetric, src: SubroutineMetric) -> None:
        """サブルーチンの未解決ファイル名・行番号を補完"""
        if not target.filename and src.filename:
            target.filename = src.filename
        if not target.first_line and src.first_line:
            target.first_line = src.first_line

    @classmethod
    def _merge_single_subroutine(
        cls, merged: ProfileData, sname: str, sub: SubroutineMetric
    ) -> None:
        """単一サブルーチンのマージ"""
        if sname not in merged.subroutines:
            merged.subroutines[sname] = SubroutineMetric(
                name=sub.name,
                filename=sub.filename,
                first_line=sub.first_line,
                calls=sub.calls,
                inclusive_time_ns=sub.inclusive_time_ns,
                exclusive_time_ns=sub.exclusive_time_ns,
                callers={c: list(vals) for c, vals in sub.callers.items()},
                callees={c: list(vals) for c, vals in sub.callees.items()},
            )
            return

        target_sub = merged.subroutines[sname]
        target_sub.calls += sub.calls
        target_sub.inclusive_time_ns += sub.inclusive_time_ns
        target_sub.exclusive_time_ns += sub.exclusive_time_ns
        cls._update_sub_loc(target_sub, sub)

        cls._merge_caller_callee_map(target_sub.callers, sub.callers)
        cls._merge_caller_callee_map(target_sub.callees, sub.callees)

    @classmethod
    def _merge_subroutines(cls, merged: ProfileData, prof: ProfileData) -> None:
        """サブルーチンメトリクスのマージ"""
        for sname, sub in prof.subroutines.items():
            cls._merge_single_subroutine(merged, sname, sub)

    @staticmethod
    def _merge_arcs(merged: ProfileData, prof: ProfileData) -> None:
        """Call Arc のマージ"""
        for arc_key, arc in prof.arcs.items():
            if arc_key not in merged.arcs:
                merged.arcs[arc_key] = ArcMetric(
                    calls=arc.calls,
                    inclusive_time_ns=arc.inclusive_time_ns,
                    exclusive_time_ns=arc.exclusive_time_ns,
                )
            else:
                merged.arcs[arc_key].calls += arc.calls
                merged.arcs[arc_key].inclusive_time_ns += arc.inclusive_time_ns
                merged.arcs[arc_key].exclusive_time_ns += arc.exclusive_time_ns

    @staticmethod
    def _merge_stacks_and_sources(merged: ProfileData, prof: ProfileData) -> None:
        """コールスタックストリームとソースキャッシュのマージ"""
        for stack_str, t_ns in prof.stack_traces.items():
            merged.stack_traces[stack_str] = (
                merged.stack_traces.get(stack_str, 0) + t_ns
            )
        for fname, src in prof.source_files.items():
            if fname not in merged.source_files:
                merged.source_files[fname] = src

    @classmethod
    def merge_profiles(cls, profiles: Sequence[ProfileData]) -> ProfileData:
        """
        ProfileData オブジェクト群を合算マージした新規 ProfileData を生成。
        """
        if not profiles:
            return ProfileData()
        if len(profiles) == 1:
            return profiles[0]

        first_meta = profiles[0].metadata
        merged_meta = ProfileMetadata(
            cmdline=first_meta.cmdline,
            start_time_iso=first_meta.start_time_iso,
            end_time_iso=profiles[-1].metadata.end_time_iso,
            total_time_ns=sum(p.metadata.total_time_ns for p in profiles),
            python_version=first_meta.python_version,
            platform_info=first_meta.platform_info,
            pid=os.getpid(),
            mode=first_meta.mode,
            calls_mode=first_meta.calls_mode,
        )
        merged = ProfileData(metadata=merged_meta)

        for prof in profiles:
            cls._merge_lines(merged, prof)
            cls._merge_subroutines(merged, prof)
            cls._merge_arcs(merged, prof)
            cls._merge_stacks_and_sources(merged, prof)

        return merged

    @classmethod
    def merge_files(
        cls, filepaths: Sequence[str], output_file: Optional[str] = None
    ) -> ProfileData:
        """
        ファイルパス群からプロファイルをロードしてマージし、指定があればファイル保存。
        """
        profiles = [ProfileStorage.load(fp) for fp in filepaths if os.path.isfile(fp)]
        merged = cls.merge_profiles(profiles)
        if output_file:
            ProfileStorage.save(merged, output_file)
        return merged
