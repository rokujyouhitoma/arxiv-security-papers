#!/usr/bin/env python3
"""Reproducible Lua 5.4.7 C99 build phase profiler & assembler round-trip analyzer (Issue #945)."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import statistics
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

TU_PHASE_KEYS: tuple[str, ...] = (
    "pch_load_us",
    "cpp_us",
    "parse_us",
    "sema_us",
    "lower_us",
    "opt_us",
    "lir_verify_us",
    "isel_us",
    "x86_peephole_us",
    "asm_emit_us",
    "asm_pass1_us",
    "asm_pass2_us",
    "elf_build_us",
    "obj_write_us",
)

PHASE_LABELS: dict[str, str] = {
    "pch_load_us": "PCH 読込・復元 (pch_load)",
    "cpp_us": "C99 プリプロセッサ (cpp)",
    "parse_us": "C99 PEG パース (parse)",
    "sema_us": "意味解析・型検証 (sema)",
    "lower_us": "LIR ローワリング (lower)",
    "opt_us": "LIR 最適化 (opt -O2)",
    "lir_verify_us": "Core LIR 検証 (lir_verify)",
    "isel_us": "x86-64 命令選択 (isel)",
    "x86_peephole_us": "x86 ピープホール (x86_peephole)",
    "asm_emit_us": "Asm テキスト生成 (asm_emit) [往復①]",
    "asm_pass1_us": "Asm 再パース+符号化 (asm_pass1) [往復②]",
    "asm_pass2_us": "セクション実体化+再配置 (asm_pass2)",
    "elf_build_us": "ELF64 ET_REL 構築 (elf_build)",
    "obj_write_us": ".o ファイル書出 (obj_write)",
}

LARGE_PROBE_TUS: tuple[str, ...] = ("lvm.c", "lparser.c", "lcode.c")


def parse_profile_records(log_text: str) -> dict[str, list[dict[str, Any]]]:
    """Parse [c99-profile] key=value records from compiler stderr/log output."""
    records: dict[str, list[dict[str, Any]]] = {
        "tu": [],
        "pch": [],
        "link": [],
        "asm_parse_probe": [],
    }
    for raw_line in log_text.splitlines():
        line = raw_line.strip()
        if not line.startswith("[c99-profile] "):
            continue
        fields: dict[str, Any] = {}
        for tok in line[len("[c99-profile] ") :].split():
            if "=" not in tok:
                continue
            k, v = tok.split("=", 1)
            if k in ("kind", "file"):
                fields[k] = v
            else:
                fields[k] = int(v)
        kind = str(fields.get("kind", ""))
        if kind in records:
            records[kind].append(fields)
    return records


def sha256_file(path: Path) -> str:
    """Return lowercase hex SHA-256 digest of a file."""
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def collect_artifact_hashes(ulisp_dir: Path) -> dict[str, str]:
    """Hash all 33 Lua .o objects and static lua_ulisp binary."""
    hashes: dict[str, str] = {}
    obj_dir = ulisp_dir / "build" / "lua_obj"
    for obj in sorted(obj_dir.glob("*.o")):
        hashes[obj.name] = sha256_file(obj)
    static_bin = ulisp_dir / "build" / "lua_ulisp_static"
    if static_bin.exists():
        hashes[static_bin.name] = sha256_file(static_bin)
    return hashes


def read_cpu_model() -> str:
    """Read Linux CPU model name cleanly from /proc/cpuinfo."""
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        for line in cpuinfo.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("model name"):
                _, val = line.split(":", 1)
                return val.strip()
    return platform.processor() or "unknown"


def _parse_text_section_bytes(readelf_stdout: str) -> int:
    total = 0
    for line in readelf_stdout.splitlines():
        if " .text " not in line:
            continue
        parts = line.split()
        if ".text" in parts:
            idx = parts.index(".text")
            if idx + 4 < len(parts):
                total += int(parts[idx + 4], 16)
    return total


def read_lua_text_bytes(obj_dir: Path) -> int:
    """Sum .text section sizes across all 33 Lua .o relocatable objects."""
    objs = sorted(obj_dir.glob("*.o"))
    if not objs:
        return 0
    res = subprocess.run(
        ["readelf", "-SW", *[str(p) for p in objs]],
        check=True,
        capture_output=True,
        text=True,
        shell=False,
    )
    return _parse_text_section_bytes(res.stdout)


def run_lua_build_once(
    ulisp_dir: Path,
    jobs: int,
    use_pch: bool,
    profile_phases: bool,
    use_ulisp_cc: bool,
) -> dict[str, Any]:
    """Execute test_compile_lua.sh once and collect timings, logs, and hashes."""
    env = os.environ.copy()
    env["JOBS"] = str(jobs)
    env["USE_PCH"] = "1" if use_pch else "0"
    env["PROFILE_PHASES"] = "1" if profile_phases else "0"
    env["LUA_DIFF_GCC"] = "0"
    env["SKIP_SMOKE"] = "1"
    env["USE_GOSH"] = "1"
    if use_ulisp_cc:
        env["ULISP_CC_BIN"] = str(ulisp_dir / "bin" / "ulisp-cc")
    else:
        env.pop("ULISP_CC_BIN", None)

    t0_ns = time.perf_counter_ns()
    proc = subprocess.run(
        ["bash", str(ulisp_dir / "tests" / "test_compile_lua.sh")],
        cwd=str(ulisp_dir),
        env=env,
        shell=False,
        capture_output=True,
        text=True,
    )
    wall_us = (time.perf_counter_ns() - t0_ns) // 1000
    if proc.returncode != 0:
        raise RuntimeError(
            f"test_compile_lua.sh failed (rc={proc.returncode}, jobs={jobs}, "
            f"use_pch={use_pch}, ulisp_cc={use_ulisp_cc}):\n"
            f"{proc.stdout}\n{proc.stderr}"
        )

    obj_dir = ulisp_dir / "build" / "lua_obj"
    combined_logs: list[str] = []
    for log_name in ["pch_core.log", "pch_lib.log", "link.log"]:
        lp = obj_dir / log_name
        if lp.exists():
            combined_logs.append(lp.read_text(encoding="utf-8", errors="replace"))
    for sp in sorted(obj_dir.glob("shard_*.log")):
        combined_logs.append(sp.read_text(encoding="utf-8", errors="replace"))

    parsed = parse_profile_records("\n".join(combined_logs))
    return {
        "wall_us": wall_us,
        "records": parsed,
        "hashes": collect_artifact_hashes(ulisp_dir),
        "lua_text_bytes": read_lua_text_bytes(obj_dir),
    }


def _record_rel_gap(rec: dict[str, Any]) -> float:
    total_us = float(rec["total_us"])
    if total_us <= 0:
        return 0.0
    phase_sum = sum(float(rec[k]) for k in TU_PHASE_KEYS)
    return abs(total_us - phase_sum) / total_us


def _median_tu_entry(tu_name: str, recs: list[dict[str, Any]]) -> dict[str, Any]:
    med: dict[str, Any] = {"file": tu_name}
    for key in (*TU_PHASE_KEYS, "total_us", "asm_lines", "asm_bytes", "obj_bytes"):
        med[key] = float(statistics.median([int(r[key]) for r in recs]))
    max_rec_gap = max(_record_rel_gap(r) for r in recs)
    if max_rec_gap >= 0.02:
        raise RuntimeError(
            f"Phase closure error >= 2% in a run for {tu_name}: gap={max_rec_gap:.4f}"
        )
    med["phase_sum_us"] = sum(float(med[k]) for k in TU_PHASE_KEYS)
    med["rel_gap"] = max_rec_gap
    return med


def _summarize_pch_medians(runs: list[dict[str, Any]]) -> dict[str, dict[str, float]]:
    pch_by_file: dict[str, list[dict[str, Any]]] = {}
    for run in runs:
        for rec in run["records"]["pch"]:
            pch_by_file.setdefault(str(rec["file"]), []).append(rec)
    pch_keys = (
        "cpp_us",
        "parse_us",
        "sema_us",
        "pch_write_us",
        "total_us",
        "pch_bytes",
    )
    return {
        fname: {
            k: float(statistics.median([int(r[k]) for r in recs])) for k in pch_keys
        }
        for fname, recs in sorted(pch_by_file.items())
    }


def _group_tu_records(runs: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    by_tu: dict[str, list[dict[str, Any]]] = {}
    for run in runs:
        for rec in run["records"]["tu"]:
            by_tu.setdefault(str(rec["file"]), []).append(rec)
    if len(by_tu) != 33:
        raise RuntimeError(f"Expected 33 Lua TU profile records, got {len(by_tu)}")
    return by_tu


def _median_link(runs: list[dict[str, Any]]) -> dict[str, float]:
    link_recs = [r for run in runs for r in run["records"]["link"]]
    link_keys = ("link_us", "link_write_us", "total_us", "bin_bytes")
    return {
        k: float(statistics.median([int(r[k]) for r in link_recs])) for k in link_keys
    }


def _aggregate_tu_totals(tu_medians: dict[str, dict[str, Any]]) -> dict[str, Any]:
    vals = list(tu_medians.values())
    phase_totals_us = {k: sum(float(m[k]) for m in vals) for k in TU_PHASE_KEYS}
    return {
        "phase_totals_us": phase_totals_us,
        "tu_total_us": sum(float(m["total_us"]) for m in vals),
        "total_asm_lines": sum(int(m["asm_lines"]) for m in vals),
        "total_asm_bytes": sum(int(m["asm_bytes"]) for m in vals),
        "total_obj_bytes": sum(int(m["obj_bytes"]) for m in vals),
        "max_rel_gap": max(float(m["rel_gap"]) for m in vals),
    }


def summarize_tu_medians(runs: list[dict[str, Any]]) -> dict[str, Any]:
    """Compute per-TU and aggregated phase medians across multiple profiled runs."""
    by_tu = _group_tu_records(runs)
    tu_medians = {
        tu_name: _median_tu_entry(tu_name, recs)
        for tu_name, recs in sorted(by_tu.items())
    }
    pch_medians = _summarize_pch_medians(runs)
    agg = _aggregate_tu_totals(tu_medians)
    return {
        "wall_median_us": float(statistics.median([int(r["wall_us"]) for r in runs])),
        "tu_count": len(tu_medians),
        "tu_medians": tu_medians,
        **agg,
        "pch_medians": pch_medians,
        "pch_total_us": sum(p["total_us"] for p in pch_medians.values()),
        "link_median": _median_link(runs),
        "lua_text_bytes": int(runs[0].get("lua_text_bytes", 0)),
    }


def _emit_ulisp_cc_core_pch(
    ulisp_cc: Path, ulisp_dir: Path, lua_src: Path, out_sbi: Path
) -> None:
    core_hdr = ulisp_dir / "build" / "lua_obj" / "lua_core_pch.h"
    if not core_hdr.exists():
        raise RuntimeError(f"Missing core PCH header for probe: {core_hdr}")
    subprocess.run(
        [
            str(ulisp_cc),
            "-emit-pch",
            "-DLUA_USE_POSIX",
            "-I",
            str(lua_src),
            str(core_hdr),
            "-o",
            str(out_sbi),
        ],
        cwd=str(ulisp_dir),
        shell=False,
        check=True,
        capture_output=True,
        text=True,
    )


def run_asm_parse_microprobe(ulisp_dir: Path, runs: int) -> list[dict[str, Any]]:
    """Run --profile-asm-parse on representative large Lua TUs to split Pass 144a text parsing vs encoding."""
    ulisp_cc = ulisp_dir / "bin" / "ulisp-cc"
    lua_src = ulisp_dir / "build" / "third_party" / "lua-5.4.7" / "src"

    results: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="ulisp_asm_probe_") as tmpdir:
        tmp_path = Path(tmpdir)
        core_pch_sbi = tmp_path / "lua_core_pch.h.sbi"
        _emit_ulisp_cc_core_pch(ulisp_cc, ulisp_dir, lua_src, core_pch_sbi)
        for tu_name in LARGE_PROBE_TUS:
            src_path = lua_src / tu_name
            out_o = tmp_path / f"{tu_name}.o"
            probes: list[dict[str, Any]] = []
            for _ in range(runs):
                proc = subprocess.run(
                    [
                        str(ulisp_cc),
                        "--profile-phases",
                        "--profile-asm-parse",
                        "-DLUA_USE_POSIX",
                        "-O2",
                        "-I",
                        str(lua_src),
                        "-include-pch",
                        str(core_pch_sbi),
                        "-c",
                        "-o",
                        str(out_o),
                        str(src_path),
                    ],
                    cwd=str(ulisp_dir),
                    shell=False,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                parsed = parse_profile_records(proc.stderr)
                if not parsed["asm_parse_probe"]:
                    raise RuntimeError(f"Missing asm_parse_probe output for {tu_name}")
                probes.append(parsed["asm_parse_probe"][0])

            med_parse_only = float(
                statistics.median([int(p["parse_only_us"]) for p in probes])
            )
            med_full_pass1 = float(
                statistics.median([int(p["full_pass1_us"]) for p in probes])
            )
            med_encode_est = max(0.0, med_full_pass1 - med_parse_only)
            parse_share = (
                (med_parse_only / med_full_pass1 * 100.0) if med_full_pass1 > 0 else 0.0
            )
            results.append(
                {
                    "file": tu_name,
                    "asm_lines": int(probes[0]["asm_lines"]),
                    "asm_bytes": int(probes[0]["asm_bytes"]),
                    "parsed_insts": int(probes[0]["parsed_insts"]),
                    "parsed_dirs": int(probes[0]["parsed_dirs"]),
                    "parse_only_us": med_parse_only,
                    "full_pass1_us": med_full_pass1,
                    "encode_est_us": med_encode_est,
                    "parse_share_pct": parse_share,
                }
            )
    return results


def _ms(us: float) -> str:
    return f"{us / 1000.0:,.2f}"


def _pct(part: float, total: float) -> str:
    if total <= 0:
        return "0.00%"
    return f"{(part / total) * 100.0:.2f}%"


def _sum_rt_us(summary: dict[str, Any]) -> float:
    phases = summary["phase_totals_us"]
    return float(phases["asm_emit_us"]) + float(phases["asm_pass1_us"])


def _summary_row(
    label: str, summary: dict[str, Any], include_breakdown: bool = True
) -> str:
    tu_total = float(summary["tu_total_us"])
    pch_total = float(summary["pch_total_us"])
    link_total = float(summary["link_median"]["total_us"])
    wall = _ms(summary["wall_median_us"])
    if not include_breakdown:
        return (
            f"| {label} | {wall} | {_ms(pch_total)} | {_ms(tu_total)} "
            f"| {_ms(link_total)} | — | — |"
        )
    rt = _sum_rt_us(summary)
    parse = float(summary["phase_totals_us"]["parse_us"])
    return (
        f"| {label} | {wall} | {_ms(pch_total)} | {_ms(tu_total)} | {_ms(link_total)} "
        f"| {_ms(rt)} ({_pct(rt, tu_total)}) | {_ms(parse)} ({_pct(parse, tu_total)}) |"
    )


def _format_decision_conclusion(
    parse_us: float,
    rt_total: float,
    est_pure_roundtrip_us: float,
    aot_tu_total: float,
) -> str:
    p_pct = _pct(parse_us, aot_tu_total)
    rt_pct = _pct(rt_total, aot_tu_total)
    pure_pct = _pct(est_pure_roundtrip_us, aot_tu_total)
    if parse_us >= rt_total:
        return (
            f"**結論**: `parse`（{p_pct}）が最大単独ボトルネックであり、アセンブラ往復全体"
            f"（`asm_emit+asm_pass1`: {rt_pct}、純往復 {pure_pct}）を上回っている。"
            "したがって **#948/#949（CPS PEG 廃止・Direct-Style 静的パーサ生成）を最優先** とし、"
            "次いで Pass 140→144a のテキスト往復廃止を進めるべきである。"
        )
    if est_pure_roundtrip_us >= parse_us:
        return (
            f"**結論**: アセンブラテキスト往復の純粋オーバーヘッド（{pure_pct}、区間全体 {rt_pct}）が "
            f"`parse`（{p_pct}）を上回っており、**Pass 140→144a 直接機械語生成（テキスト往復廃止）が最大 ROI** を持つ。"
            "次いで #948/#949（静的 PEG パーサ移行）を推進するべきである。"
        )
    return (
        f"**結論**: `parse`（{p_pct}）とアセンブラ往復（純往復 {pure_pct} / 区間全体 {rt_pct}）の双方が主要ボトルネックである。"
        "まず単一施策で削り幅が大きい側の計画（#948/#949 または Pass 140→144a 直接エンコード）を先行し、"
        "残余を次段で回収する二段階最適化が最も合理的である。"
    )


def build_markdown_report(payload: dict[str, Any]) -> str:
    """Render the quantitative Japanese Markdown benchmark report."""
    meta = payload["metadata"]
    aot_pch = payload["ulisp_cc_jobs1_pch"]
    aot_nopch = payload["ulisp_cc_jobs1_nopch"]
    aot_par = payload["ulisp_cc_parallel_pch"]
    gosh_par = payload["gosh_parallel_pch"]
    probe = payload["asm_parse_probe"]
    ver = payload["verification"]

    aot_tu_total = float(aot_pch["tu_total_us"])
    aot_pch_total = float(aot_pch["pch_total_us"])
    aot_link_total = float(aot_pch["link_median"]["total_us"])
    aot_sum_all = aot_tu_total + aot_pch_total + aot_link_total

    gosh_tu_total = float(gosh_par["tu_total_us"])
    gosh_pch_total = float(gosh_par["pch_total_us"])
    gosh_link_total = float(gosh_par["link_median"]["total_us"])
    gosh_sum_all = gosh_tu_total + gosh_pch_total + gosh_link_total
    nopch_tu_total = float(aot_nopch["tu_total_us"])

    rt_emit = float(aot_pch["phase_totals_us"]["asm_emit_us"])
    rt_pass1 = float(aot_pch["phase_totals_us"]["asm_pass1_us"])
    rt_total = rt_emit + rt_pass1

    avg_probe_parse_share = statistics.mean(
        [float(p["parse_share_pct"]) for p in probe]
    )
    est_pure_parse_us = rt_pass1 * (avg_probe_parse_share / 100.0)
    est_pure_roundtrip_us = rt_emit + est_pure_parse_us

    parse_us = float(aot_pch["phase_totals_us"]["parse_us"])
    cpp_us = float(aot_pch["phase_totals_us"]["cpp_us"])
    sema_us = float(aot_pch["phase_totals_us"]["sema_us"])
    opt_us = float(aot_pch["phase_totals_us"]["opt_us"])
    lower_us = float(aot_pch["phase_totals_us"]["lower_us"])

    sorted_phases = sorted(
        TU_PHASE_KEYS,
        key=lambda k: float(aot_pch["phase_totals_us"][k]),
        reverse=True,
    )
    top_tus = sorted(
        aot_pch["tu_medians"].values(),
        key=lambda r: float(r["total_us"]),
        reverse=True,
    )[:10]

    text_kb = aot_pch["lua_text_bytes"] / 1024.0
    asm_kb = aot_pch["total_asm_bytes"] / 1024.0
    nproc = meta["nproc"]
    lines: list[str] = [
        "# Lua 5.4.7 C99 ビルド フェーズ別プロファイリング ＆ アセンブラ往復コスト定量レポート (Issue #945)",
        "",
        f"- **計測日時 (UTC)**: `{meta['timestamp_utc']}`",
        "- **関連 Issue**: "
        "[Issue #945](../issues/closed/945-profile-lua-547-c99-build-phase-breakdown-on-linux.md) / "
        "[Issue #932](../issues/closed/932-build-native-aot-ulisp-cc-compiler-driver-binary.md) / "
        "[Issue #948](../issues/948-implement-direct-style-static-scheme-peg-parser-generator-backend.md) / "
        "[Issue #949](../issues/949-migrate-c99-parser-to-aot-generated-static-scheme-parser.md)",
        "- **関連設計書**: "
        "[DSN-33-32](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md) / "
        "[DSN-33-41](../designs/DSN-33-41-ulisp_ilisp_aot_jit_continuous_benchmarking_framework.md)",
        "",
        "---",
        "",
        "## 1. 実行環境・測定プロトコルと非干渉性検証",
        "",
        f"- **OS / Kernel**: `{meta['uname']}`",
        f"- **CPU**: `{meta['cpu_model']}` (`nproc = {nproc}`)",
        f"- **対象コードベース**: 無改変 Lua 5.4.7 全 33 TU（`.text` = `{aot_pch['lua_text_bytes']:,}` B / "
        f"`{text_kb:.1f}` KB、生成アセンブリ = `{aot_pch['total_asm_lines']:,}` 行 / `{asm_kb:.1f}` KB）",
        "- **ビット一致検証 (`PROFILE_PHASES=0` vs `1`)**: "
        f"全 33 `.o` + `lua_ulisp_static` **{ver['sha256_matched']}/{ver['sha256_total']} SHA-256 完全一致**",
        f"- **計測オーバーヘッド (`ulisp-cc JOBS=1`)**: 非計測中央値 `{_ms(ver['unprofiled_wall_median_us'])} ms` "
        f"vs 計測付中央値 `{_ms(aot_pch['wall_median_us'])} ms` (**{ver['overhead_pct']:+.2f}%**, ゲート `< 2.0%`)",
        f"- **全 TU フェーズ総和整合誤差**: 最大 `{aot_pch['max_rel_gap'] * 100.0:.4f}%`（全 33 TU `< 2.0%`）",
        "",
        "---",
        "",
        "## 2. 全体サマリー (`ulisp-cc` AOT vs `gosh` 基準)",
        "",
        "| 構成 | 壁時計 (ms) | PCH 生成 (ms) | 33 TU 合計 (ms) | Pass 144 リンク (ms) | "
        "往復 `asm_emit+asm_pass1` (ms / TU比) | `parse` (ms / TU比) |",
        "| :--- | ---: | ---: | ---: | ---: | ---: | ---: |",
        _summary_row("**`ulisp-cc` (`JOBS=1, USE_PCH=1`, 3回中央値)**", aot_pch),
        _summary_row("**`ulisp-cc` (`JOBS=1, USE_PCH=0`)**", aot_nopch),
        _summary_row(
            f"**`ulisp-cc` (`JOBS={nproc}, USE_PCH=1`, 並列)**",
            aot_par,
            include_breakdown=False,
        ),
        _summary_row(f"**`gosh` (`JOBS={nproc}, USE_PCH=1`, 並列)**", gosh_par),
        "",
        "---",
        "",
        "## 3. 33 TU フェーズ別時間内訳 (`ulisp-cc` `JOBS=1, USE_PCH=1` 中央値順)",
        "",
        f"| 順位 | フェーズ | `ulisp-cc` `JOBS=1` (ms) | TU 内比率 | `USE_PCH=0` (ms) | "
        f"`gosh` `JOBS={nproc}` 合算 (ms) | `gosh` TU 内比率 |",
        "| :---: | :--- | ---: | ---: | ---: | ---: | ---: |",
    ]

    for idx, key in enumerate(sorted_phases, start=1):
        v_aot = float(aot_pch["phase_totals_us"][key])
        v_nopch = float(aot_nopch["phase_totals_us"][key])
        v_gosh = float(gosh_par["phase_totals_us"][key])
        lines.append(
            f"| {idx} | {PHASE_LABELS[key]} | {_ms(v_aot)} | {_pct(v_aot, aot_tu_total)} | "
            f"{_ms(v_nopch)} | {_ms(v_gosh)} | {_pct(v_gosh, gosh_tu_total)} |"
        )

    lines.extend(
        [
            f"| — | **33 TU 合計 (`tu_total`)** | **{_ms(aot_tu_total)}** | **100.00%** | "
            f"**{_ms(nopch_tu_total)}** | **{_ms(gosh_tu_total)}** | **100.00%** |",
            f"| — | PCH 生成 (`core` + `lib`, 2ファイル計) | {_ms(aot_pch_total)} | "
            f"(全体 {_pct(aot_pch_total, aot_sum_all)}) | 0.00 | {_ms(gosh_pch_total)} | "
            f"(全体 {_pct(gosh_pch_total, gosh_sum_all)}) |",
            f"| — | Pass 144 静的リンク (`link` + 書出) | {_ms(aot_link_total)} | "
            f"(全体 {_pct(aot_link_total, aot_sum_all)}) | {_ms(aot_nopch['link_median']['total_us'])} | "
            f"{_ms(gosh_link_total)} | (全体 {_pct(gosh_link_total, gosh_sum_all)}) |",
            "",
            "---",
            "",
            "## 4. アセンブラテキスト往復コスト定量化 ＆ 大型 TU 字句再パース切り分け",
            "",
            f"- **アセンブラ往復区間合計 (`asm_emit` + `asm_pass1`)**: `{_ms(rt_total)} ms`"
            f"（33 TU 比 **{_pct(rt_total, aot_tu_total)}**、PCH+TU+Link 比 **{_pct(rt_total, aot_sum_all)}**）",
            f"  - `asm_emit` (Pass 140 文字列生成 + 収集): `{_ms(rt_emit)} ms`（TU 比 {_pct(rt_emit, aot_tu_total)}）",
            f"  - `asm_pass1` (Pass 144a 再パース + 符号化): `{_ms(rt_pass1)} ms`（TU 比 {_pct(rt_pass1, aot_tu_total)}）",
            "- **代表大型 3 TU (`--profile-asm-parse`) による純粋テキスト再パース vs 符号化の切り分け**:",
            "",
            "| TU | アセンブリ行数 | サイズ (KB) | 解析命令数 | `asm_pass1` (ms) | "
            "`parse_only` (ms) | `encode_est` (ms) | `parse_only` 率 |",
            "| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )

    for p in probe:
        lines.append(
            f"| `{p['file']}` | {p['asm_lines']:,} | {p['asm_bytes'] / 1024.0:.1f} | {p['parsed_insts']:,} | "
            f"{_ms(p['full_pass1_us'])} | {_ms(p['parse_only_us'])} | {_ms(p['encode_est_us'])} | "
            f"{p['parse_share_pct']:.2f}% |"
        )

    lines.extend(
        [
            "",
            f"- **純粋往復オーバーヘッド推定 (`asm_emit` + `asm_pass1 × {avg_probe_parse_share:.1f}%`)**: "
            f"約 `{_ms(est_pure_roundtrip_us)} ms`（33 TU 比 **{_pct(est_pure_roundtrip_us, aot_tu_total)}**）が"
            "構造化 LIR/ASM AST から直接機械語生成することで削減可能な純粋テキスト往復コストとなる。",
            "",
            "---",
            "",
            "## 5. 上位 10 重量 TU 内訳 (`ulisp-cc` `JOBS=1, USE_PCH=1`)",
            "",
            "| 順位 | TU | 合計 (ms) | `parse` (ms) | `sema` (ms) | `opt` (ms) | "
            "`asm_emit` (ms) | `asm_pass1` (ms) | 行数 | `.o` (KB) |",
            "| :---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )

    for idx, tu in enumerate(top_tus, start=1):
        lines.append(
            f"| {idx} | `{tu['file']}` | {_ms(tu['total_us'])} | {_ms(tu['parse_us'])} | {_ms(tu['sema_us'])} | "
            f"{_ms(tu['opt_us'])} | {_ms(tu['asm_emit_us'])} | {_ms(tu['asm_pass1_us'])} | "
            f"{int(tu['asm_lines']):,} | {tu['obj_bytes'] / 1024.0:.1f} |"
        )

    link_948 = "[#948](../issues/948-implement-direct-style-static-scheme-peg-parser-generator-backend.md)"
    link_949 = "[#949](../issues/949-migrate-c99-parser-to-aot-generated-static-scheme-parser.md)"
    lines.extend(
        [
            "",
            "---",
            "",
            "## 6. 次期高速化優先度の定量的判断 (Decision)",
            "",
            "| 最適化候補 | 対象フェーズ | 対象時間 (`ulisp-cc JOBS=1`) | 33 TU 占有率 | 全体占有率 |",
            "| :--- | :--- | ---: | ---: | ---: |",
            f"| **Direct-Style 静的 PEG パーサ移行 ({link_948}/{link_949})** | `parse` | "
            f"{_ms(parse_us)} ms | {_pct(parse_us, aot_tu_total)} | {_pct(parse_us, aot_sum_all)} |",
            f"| **アセンブラテキスト往復廃止 (Pass 140→144a 直接符号化)** | `asm_emit`+`parse_only` (全往復) | "
            f"{_ms(est_pure_roundtrip_us)} ms (全 {_ms(rt_total)} ms) | "
            f"{_pct(est_pure_roundtrip_us, aot_tu_total)} (全 {_pct(rt_total, aot_tu_total)}) | "
            f"{_pct(est_pure_roundtrip_us, aot_sum_all)} (全 {_pct(rt_total, aot_sum_all)}) |",
            f"| **C99 意味解析・型チェック最適化** | `sema` | "
            f"{_ms(sema_us)} ms | {_pct(sema_us, aot_tu_total)} | {_pct(sema_us, aot_sum_all)} |",
            f"| **LIR 最適化パス (`-O2`) チューニング** | `opt` | "
            f"{_ms(opt_us)} ms | {_pct(opt_us, aot_tu_total)} | {_pct(opt_us, aot_sum_all)} |",
            f"| **C99 プリプロセッサ (`cpp`) 高速化** | `cpp` | "
            f"{_ms(cpp_us)} ms | {_pct(cpp_us, aot_tu_total)} | {_pct(cpp_us, aot_sum_all)} |",
            f"| **LIR ローワリング (`lower`) チューニング** | `lower` | "
            f"{_ms(lower_us)} ms | {_pct(lower_us, aot_tu_total)} | {_pct(lower_us, aot_sum_all)} |",
            f"| **Pass 144 静的リンカ高速化** | `link` + `link_write` | "
            f"{_ms(aot_link_total)} ms | — | {_pct(aot_link_total, aot_sum_all)} |",
            "",
            _format_decision_conclusion(
                parse_us, rt_total, est_pure_roundtrip_us, aot_tu_total
            ),
            "",
        ]
    )
    return "\n".join(lines)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Profile Lua 5.4.7 C99 build phases on Linux."
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=3,
        help="Number of ulisp-cc JOBS=1 runs for median.",
    )
    parser.add_argument(
        "--gosh-runs", type=int, default=1, help="Number of gosh parallel runs."
    )
    parser.add_argument(
        "--output-json",
        default="docs/benchmarks/lua_547_build_phase_profile.json",
        help="Output JSON report path relative to repository root.",
    )
    parser.add_argument(
        "--output-md",
        default="docs/benchmarks/lua_547_build_phase_profile.md",
        help="Output Markdown report path relative to repository root.",
    )
    return parser.parse_args()


def _verify_bit_identity(
    unprof_hashes: dict[str, str], prof_hashes: dict[str, str]
) -> None:
    if unprof_hashes == prof_hashes:
        return
    diff_keys = [
        k
        for k in sorted(set(unprof_hashes) | set(prof_hashes))
        if unprof_hashes.get(k) != prof_hashes.get(k)
    ]
    raise RuntimeError(
        f"Bit-identity check FAILED between profiled and unprofiled runs: {diff_keys}"
    )


def _resolve_output_paths(
    repo_root: Path, args: argparse.Namespace
) -> tuple[Path, Path]:
    json_out = (repo_root / args.output_json).resolve()
    md_out = (repo_root / args.output_md).resolve()
    if repo_root not in json_out.parents or repo_root not in md_out.parents:
        raise RuntimeError("Output paths must stay within repository root")
    json_out.parent.mkdir(parents=True, exist_ok=True)
    md_out.parent.mkdir(parents=True, exist_ok=True)
    return json_out, md_out


def main() -> int:
    """Entry point for Lua 5.4.7 C99 build phase profiling."""
    args = _parse_args()
    ulisp_dir = Path(__file__).resolve().parent.parent
    repo_root = ulisp_dir.parent
    par_jobs = max(1, min(8, os.cpu_count() or 4))
    json_out, md_out = _resolve_output_paths(repo_root, args)

    print(
        f"[profile_lua] 1/6 Running unprofiled ulisp-cc baseline (JOBS=1, runs={args.runs}) ..."
    )
    unprof_runs = [
        run_lua_build_once(
            ulisp_dir, jobs=1, use_pch=True, profile_phases=False, use_ulisp_cc=True
        )
        for _ in range(args.runs)
    ]

    print(f"[profile_lua] 2/6 Running profiled ulisp-cc (JOBS=1, runs={args.runs}) ...")
    prof_runs = [
        run_lua_build_once(
            ulisp_dir, jobs=1, use_pch=True, profile_phases=True, use_ulisp_cc=True
        )
        for _ in range(args.runs)
    ]

    ref_hashes = unprof_runs[0]["hashes"]
    _verify_bit_identity(ref_hashes, prof_runs[0]["hashes"])

    unprof_wall_med = float(statistics.median([int(r["wall_us"]) for r in unprof_runs]))
    aot_pch = summarize_tu_medians(prof_runs)
    overhead_pct = (
        (float(aot_pch["wall_median_us"]) - unprof_wall_med) / unprof_wall_med
    ) * 100.0

    print("[profile_lua] 3/6 Running profiled ulisp-cc without PCH (JOBS=1) ...")
    aot_nopch = summarize_tu_medians(
        [
            run_lua_build_once(
                ulisp_dir, jobs=1, use_pch=False, profile_phases=True, use_ulisp_cc=True
            )
        ]
    )

    print(f"[profile_lua] 4/6 Running parallel profiled ulisp-cc (JOBS={par_jobs}) ...")
    aot_par = summarize_tu_medians(
        [
            run_lua_build_once(
                ulisp_dir,
                jobs=par_jobs,
                use_pch=True,
                profile_phases=True,
                use_ulisp_cc=True,
            )
        ]
    )

    print(
        f"[profile_lua] 5/6 Running parallel profiled gosh (JOBS={par_jobs}, runs={args.gosh_runs}) ..."
    )
    gosh_par = summarize_tu_medians(
        [
            run_lua_build_once(
                ulisp_dir,
                jobs=par_jobs,
                use_pch=True,
                profile_phases=True,
                use_ulisp_cc=False,
            )
            for _ in range(args.gosh_runs)
        ]
    )

    print(
        "[profile_lua] 6/6 Running Pass 144a pure-text-parse micro-probe on lvm.c, lparser.c, lcode.c ..."
    )
    probe_results = run_asm_parse_microprobe(ulisp_dir, runs=args.runs)

    uname_res = os.uname()
    payload: dict[str, Any] = {
        "metadata": {
            "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "uname": f"{uname_res.sysname} {uname_res.release} {uname_res.machine}",
            "cpu_model": read_cpu_model(),
            "nproc": par_jobs,
            "runs": args.runs,
            "gosh_runs": args.gosh_runs,
        },
        "verification": {
            "sha256_matched": len(ref_hashes),
            "sha256_total": len(ref_hashes),
            "unprofiled_wall_median_us": unprof_wall_med,
            "overhead_pct": overhead_pct,
        },
        "ulisp_cc_jobs1_pch": aot_pch,
        "ulisp_cc_jobs1_nopch": aot_nopch,
        "ulisp_cc_parallel_pch": aot_par,
        "gosh_parallel_pch": gosh_par,
        "asm_parse_probe": probe_results,
    }

    json_out.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    md_out.write_text(build_markdown_report(payload), encoding="utf-8")
    msg = (
        f"[profile_lua] Wrote {json_out} and {md_out} "
        f"(overhead={overhead_pct:+.2f}%, sha256={len(ref_hashes)}/{len(ref_hashes)})"
    )
    print(msg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
