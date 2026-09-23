"""
src/core/profiler/cli.py
========================
PyNYTProf 統合 CLI ディスパッチャ ＆ 環境変数インジェクションエンジン。
DSN-28 Section 7 準拠。

サブコマンド:
- run: Python スクリプトをプロファイル実行
- html: プロファイルデータから HTML レポート一式を生成
- flamegraph: 単体インタラクティブ Flame Graph SVG を生成
- callgrind: KCachegrind 互換 Callgrind 形式にエクスポート
- merge: 複数プロファイルを単一データへ合算マージ
"""

from __future__ import annotations

import argparse
import os
import runpy
import sys
from typing import Any, Callable, Dict, List, Optional

from core.profiler.chart import FlameChartGenerator, TraceEventExporter
from core.profiler.diff import ProfileDiffer
from core.profiler.engine import ProfilerEngine
from core.profiler.exporter import CallgrindExporter
from core.profiler.flamegraph import FlameGraphGenerator
from core.profiler.merge import ProfileMerger
from core.profiler.reporter import HTMLReporter
from core.profiler.storage import ProfileStorage

# ---------------------------------------------------------------------------
# 環境変数パーサ helpers
# ---------------------------------------------------------------------------


def _set_calls(options: Dict[str, Any], v: str) -> None:
    """calls トークンを安全に int 変換して適用する"""
    try:
        options["calls"] = int(v)
    except ValueError:
        options["calls"] = 1


def _set_bool_flag(options: Dict[str, Any], key: str, v: str) -> None:
    """on/off 系フラグを適用する"""
    options[key] = v in ("1", "true", "yes")


_ENV_TOKEN_HANDLERS: Dict[str, Any] = {
    "file": lambda opts, v: opts.update({"file": v}),
    "mode": lambda opts, v: opts.update({"mode": v}),
    "lines": lambda opts, v: opts.update(
        {"mode": "line" if v in ("1", "true", "yes") else "sub"}
    ),
    "calls": _set_calls,
    "slowops": lambda opts, v: _set_bool_flag(opts, "slowops", v),
    "c_calls": lambda opts, v: _set_bool_flag(opts, "slowops", v),
}


def _apply_env_token(options: Dict[str, Any], k: str, v: str) -> None:
    """単一 key=value トークンを options に適用する"""
    handler = _ENV_TOKEN_HANDLERS.get(k)
    if handler is not None:
        handler(options, v)


def parse_pynytprof_env(env_val: str) -> Dict[str, Any]:
    """
    環境変数 PYNYTPROF のコロン区切り設定をパース。
    例: "file=prof.out:lines=1:calls=1:slowops=1"
    """
    options: Dict[str, Any] = {
        "file": "pynytprof.out",
        "mode": "line",
        "calls": 1,
        "slowops": True,
    }
    if not env_val:
        return options

    for token in env_val.split(":"):
        token = token.strip()
        if not token or "=" not in token:
            continue
        k, v = token.split("=", 1)
        _apply_env_token(options, k.strip().lower(), v.strip())

    return options


# ---------------------------------------------------------------------------
# cmd_run helpers
# ---------------------------------------------------------------------------


def _resolve_run_params(
    args: argparse.Namespace,
) -> tuple[str, str, int]:
    """引数と環境変数から (out_file, mode, calls_mode) を解決する"""
    out_file = args.output
    mode = "line" if args.lines else "sub"
    calls_mode = 2 if args.calls_all else (1 if args.calls else 0)

    if "PYNYTPROF" in os.environ:
        env_opts = parse_pynytprof_env(os.environ.get("PYNYTPROF", ""))
        out_file = env_opts.get("file", out_file)
        mode = env_opts.get("mode", mode)
        calls_mode = env_opts.get("calls", calls_mode)

    return out_file, mode, calls_mode


def _run_script(script_path: str) -> int:
    """対象スクリプトを runpy で実行し終了コードを返す"""
    try:
        runpy.run_path(script_path, run_name="__main__")
        return 0
    except SystemExit as e:
        return e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
    except Exception as e:  # noqa: BLE001
        print(f"Error during script execution: {e}", file=sys.stderr)
        return 1


def _save_profile(engine: ProfilerEngine, out_file: str, calls_mode: int) -> None:
    """プロファイルデータを保存し calls ファイルを出力する"""
    profile_data = engine.stop()
    ProfileStorage.save(profile_data, out_file)
    print(f"[*] PyNYTProf: Raw profile data saved to '{out_file}'")

    if calls_mode > 0:
        calls_file = os.path.splitext(out_file)[0] + ".calls"
        ProfileStorage.export_calls_file(profile_data, calls_file)
        print(f"[*] PyNYTProf: Call stack stream exported to '{calls_file}'")


def cmd_run(args: argparse.Namespace) -> int:
    """スクリプトのプロファイル実行"""
    script_path = args.script
    if not os.path.exists(script_path):
        print(f"Error: Script not found: {script_path}", file=sys.stderr)
        return 1

    # 引数の透過受け渡し
    sys.argv = [script_path] + args.script_args
    # カレントディレクトリを sys.path に追加
    script_dir = os.path.dirname(os.path.abspath(script_path))
    if script_dir not in sys.path:
        sys.path.insert(0, script_dir)

    out_file, mode, calls_mode = _resolve_run_params(args)
    trace_stdlib = getattr(args, "trace_stdlib_lines", False)
    engine = ProfilerEngine(
        mode=mode, calls_mode=calls_mode, trace_stdlib_lines=trace_stdlib
    )
    print(
        f"[*] PyNYTProf: Profiling '{script_path}' (mode={mode}, calls={calls_mode})..."
    )
    engine.start()

    exit_code = _run_script(script_path)
    _save_profile(engine, out_file, calls_mode)
    return exit_code


# ---------------------------------------------------------------------------
# cmd_html
# ---------------------------------------------------------------------------


def cmd_html(args: argparse.Namespace) -> int:
    """HTML レポート生成"""
    in_file = args.input
    if not os.path.exists(in_file):
        print(f"Error: Input profile not found: {in_file}", file=sys.stderr)
        return 1

    out_dir = args.output_dir
    print(f"[*] PyNYTProf: Reading profile '{in_file}'...")
    profile_data = ProfileStorage.load(in_file)

    trace_filter = getattr(args, "trace_filter", None)
    if trace_filter:
        data_trace_id = getattr(profile_data.metadata, "trace_id", "")
        if data_trace_id != trace_filter:
            print(
                f"[*] PyNYTProf: Trace filter '{trace_filter}' did not match profile trace_id '{data_trace_id}'.",
                file=sys.stderr,
            )
            return 1
        print(f"[*] PyNYTProf: Trace filter matched: '{trace_filter}'")

    reporter = HTMLReporter()
    index_path = reporter.generate_report(profile_data, out_dir, title=args.title)
    print("[*] PyNYTProf: HTML Report successfully generated at:")
    print(f"    file://{os.path.abspath(index_path)}")
    return 0


# ---------------------------------------------------------------------------
# cmd_flamegraph helpers
# ---------------------------------------------------------------------------


def _build_sub_link_map(
    profile_data: Any,
    out_file: str,
    report_dir: Optional[str],
) -> Dict[str, str]:
    """subroutine -> source_*.html#anchor の相対リンクマップを構築する"""
    import html as _html

    reporter = HTMLReporter()
    file_slug_map: Dict[str, str] = {
        fname: reporter._file_to_slug(fname)
        for fname in profile_data.source_files.keys()
    }

    if report_dir:
        svg_abs = os.path.abspath(out_file)
        svg_dir = os.path.dirname(svg_abs)
        report_abs = os.path.abspath(report_dir)
        rel_prefix = os.path.relpath(report_abs, svg_dir).rstrip("/") + "/"
    else:
        rel_prefix = ""

    sub_link_map: Dict[str, str] = {}
    for sub in profile_data.subroutines.values():
        slug = file_slug_map.get(sub.filename, "")
        if slug:
            sub_link_map[sub.name] = f"{rel_prefix}{slug}#{_html.escape(sub.name)}"
    return sub_link_map


def _generate_flamegraph_svg(
    args: argparse.Namespace,
    in_file: str,
    out_file: str,
) -> str:
    """入力ファイル種別に応じて SVG テキストを生成する"""
    no_links: bool = getattr(args, "no_links", False)
    report_dir: Optional[str] = getattr(args, "report_dir", None)

    if in_file.endswith(".calls"):
        # .calls 形式は ProfileData を持たないため sub_link_map は構築不可
        link_prefix = "" if no_links else "source_details.html#"
        return FlameGraphGenerator().generate_svg(
            in_file,
            title=args.title,
            link_prefix=link_prefix,
        )

    profile_data = ProfileStorage.load(in_file)
    if no_links:
        sub_link_map: Dict[str, str] = {}
        link_prefix = ""
    else:
        sub_link_map = _build_sub_link_map(profile_data, out_file, report_dir)
        link_prefix = ""  # sub_link_map を優先するため prefix は不要

    return FlameGraphGenerator().generate_svg(
        profile_data,
        title=args.title,
        link_prefix=link_prefix,
        sub_link_map=sub_link_map,
    )


def cmd_flamegraph(args: argparse.Namespace) -> int:
    """Flame Graph SVG 単体生成"""
    in_file = args.input
    if not os.path.exists(in_file):
        print(f"Error: Input file not found: {in_file}", file=sys.stderr)
        return 1

    out_file = args.output or (os.path.splitext(in_file)[0] + ".svg")
    svg_text = _generate_flamegraph_svg(args, in_file, out_file)

    with open(out_file, "w", encoding="utf-8") as f:
        f.write(svg_text)
    print(f"[*] PyNYTProf: Flame Graph SVG saved to '{out_file}'")
    return 0


# ---------------------------------------------------------------------------
# cmd_callgrind / cmd_merge
# ---------------------------------------------------------------------------


def cmd_callgrind(args: argparse.Namespace) -> int:
    """Callgrind 形式エクスポート"""
    in_file = args.input
    if not os.path.exists(in_file):
        print(f"Error: Input profile not found: {in_file}", file=sys.stderr)
        return 1

    out_file = args.output or ("callgrind.out." + str(os.getpid()))
    profile_data = ProfileStorage.load(in_file)
    CallgrindExporter.export(profile_data, out_file)
    print(f"[*] PyNYTProf: Callgrind file saved to '{out_file}'")
    return 0


def cmd_merge(args: argparse.Namespace) -> int:
    """複数プロファイルの合算マージ"""
    files = args.files
    if len(files) < 2:
        print(
            "Error: At least 2 profile files are required to merge.",
            file=sys.stderr,
        )
        return 1

    out_file = args.output
    ProfileMerger.merge_files(files, output_file=out_file)
    print(f"[*] PyNYTProf: Merged {len(files)} files into '{out_file}'")
    return 0


def _validate_diff_inputs(before_path: str, after_path: str) -> bool:
    """差分入力ファイルの存在を検証する"""
    if not os.path.exists(before_path):
        print(f"Error: Baseline profile not found: {before_path}", file=sys.stderr)
        return False
    if not os.path.exists(after_path):
        print(f"Error: Target profile not found: {after_path}", file=sys.stderr)
        return False
    return True


def _configure_differ_thresholds(
    differ: ProfileDiffer, args: argparse.Namespace
) -> None:
    """ProfileDiffer のノイズしきい値を設定する"""
    ns_val = getattr(args, "noise_threshold_ns", None)
    if ns_val is not None:
        differ.NOISE_THRESHOLD_NS = ns_val
    ratio_val = getattr(args, "noise_threshold_ratio", None)
    if ratio_val is not None:
        differ.NOISE_THRESHOLD_RATIO = ratio_val


def cmd_diff(args: argparse.Namespace) -> int:
    """差分プロファイル HTML レポート生成"""
    if not _validate_diff_inputs(args.before, args.after):
        return 1

    print(f"[*] PyNYTProf: Comparing '{args.before}' -> '{args.after}'...")
    differ = ProfileDiffer.compare(args.before, args.after)
    _configure_differ_thresholds(differ, args)

    index_path = differ.render_html(args.output_dir, title=args.title)
    print("[*] PyNYTProf: Differential Report successfully generated at:")
    print(f"    file://{os.path.abspath(index_path)}")
    return 0


def _resolve_chart_html_path(args: argparse.Namespace, in_file: str) -> Optional[str]:
    """出力 HTML ファイルパスを決定"""
    out_html: Optional[str] = args.output_html or getattr(args, "output", None)
    if not out_html and not args.output_trace:
        return os.path.splitext(in_file)[0] + "_chart.html"
    return out_html


def cmd_chart(args: argparse.Namespace) -> int:
    """時系列 Flame Chart HTML / SVG および Chrome Trace Event JSON 生成"""
    in_file = args.input
    if not os.path.exists(in_file):
        print(f"Error: Input profile not found: {in_file}", file=sys.stderr)
        return 1

    profile_data = ProfileStorage.load(in_file)
    if args.output_trace:
        TraceEventExporter.export_file(profile_data, args.output_trace)
        print(f"[*] PyNYTProf: Chrome Trace Event JSON saved to '{args.output_trace}'")

    out_html = _resolve_chart_html_path(args, in_file)
    if out_html:
        title = getattr(args, "title", "PyNYTProf Timeline Flame Chart")
        FlameChartGenerator.generate_html(profile_data, out_path=out_html, title=title)
        print(f"[*] PyNYTProf: Flame Chart HTML saved to '{out_html}'")

    return 0


# ---------------------------------------------------------------------------
# パーサ
# ---------------------------------------------------------------------------


def create_parser() -> argparse.ArgumentParser:
    """CLI 引数パーサーを作成"""
    parser = argparse.ArgumentParser(
        prog="pynytprof",
        description="PyNYTProf: High-precision Python code profiler and visualization suite (DSN-28).",
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # run
    p_run = subparsers.add_parser("run", help="Run and profile a Python script")
    p_run.add_argument(
        "-o",
        "--output",
        default="pynytprof.out",
        help="Output profile file (default: pynytprof.out)",
    )
    p_run.add_argument(
        "--lines",
        action="store_true",
        default=True,
        help="Enable statement/line level profiling (default: True)",
    )
    p_run.add_argument(
        "--no-lines",
        dest="lines",
        action="store_false",
        help="Disable line level profiling (subroutine only)",
    )
    p_run.add_argument(
        "--trace-stdlib-lines",
        action="store_true",
        default=False,
        help="Enable line-level profiling inside standard library files (default: False)",
    )
    p_run.add_argument(
        "--calls",
        action="store_true",
        default=True,
        help="Enable subroutine return streaming for flamegraph (default: True)",
    )
    p_run.add_argument(
        "--calls-all", action="store_true", help="Stream call entries and returns"
    )
    p_run.add_argument("script", help="Target Python script to profile")
    p_run.add_argument(
        "script_args",
        nargs=argparse.REMAINDER,
        help="Arguments to pass to target script",
    )

    # html
    p_html = subparsers.add_parser(
        "html", help="Generate HTML report from profile data"
    )
    p_html.add_argument(
        "-i",
        "--input",
        default="pynytprof.out",
        help="Input profile file (default: pynytprof.out)",
    )
    p_html.add_argument(
        "-d",
        "--output-dir",
        default="pynytprof_html",
        help="Output HTML directory (default: pynytprof_html)",
    )
    p_html.add_argument(
        "-t", "--title", default="PyNYTProf Performance Report", help="Report title"
    )
    p_html.add_argument(
        "--trace-filter",
        default=None,
        help="Filter profile by W3C TraceContext trace_id (DSN-28 Section 8.2)",
    )

    # flamegraph
    p_flame = subparsers.add_parser(
        "flamegraph", help="Generate standalone interactive Flame Graph SVG"
    )
    p_flame.add_argument(
        "-i",
        "--input",
        default="pynytprof.out",
        help="Input profile (.out) or calls (.calls) file",
    )
    p_flame.add_argument("-o", "--output", help="Output SVG file")
    p_flame.add_argument(
        "-t", "--title", default="PyNYTProf Flame Graph", help="Graph title"
    )
    p_flame.add_argument(
        "--report-dir",
        metavar="DIR",
        default=None,
        help=(
            "HTML report directory generated by pynytprofhtml. "
            "Links in the SVG will point to source detail pages in that directory. "
            "Example: --report-dir ./report_manage_tables"
        ),
    )
    p_flame.add_argument(
        "--no-links",
        action="store_true",
        default=False,
        help="Disable hyperlinks in the SVG (useful for standalone viewing or embedding)",
    )

    # callgrind
    p_cg = subparsers.add_parser(
        "callgrind", help="Export to KCachegrind callgrind format"
    )
    p_cg.add_argument(
        "-i", "--input", default="pynytprof.out", help="Input profile (.out) file"
    )
    p_cg.add_argument("-o", "--output", help="Output Callgrind file")

    # merge
    p_merge = subparsers.add_parser(
        "merge", help="Merge multiple profile files into one"
    )
    p_merge.add_argument(
        "-o",
        "--output",
        default="merged.pynytprof.out",
        help="Output merged profile file",
    )
    p_merge.add_argument("files", nargs="+", help="Input profile files to merge")

    # diff
    p_diff = subparsers.add_parser(
        "diff", help="Generate differential profile HTML report between two profiles"
    )
    p_diff.add_argument(
        "--before",
        "-b",
        required=True,
        help="Baseline profile file (before)",
    )
    p_diff.add_argument(
        "--after",
        "-a",
        required=True,
        help="Comparison profile file (after)",
    )
    p_diff.add_argument(
        "-d",
        "--output-dir",
        default="diff_report",
        help="Output HTML directory (default: diff_report)",
    )
    p_diff.add_argument(
        "-t",
        "--title",
        default="PyNYTProf Differential Profile Report",
        help="Report title",
    )
    p_diff.add_argument(
        "--noise-threshold-ns",
        type=int,
        default=500000,
        help="Noise threshold in nanoseconds (default: 500000)",
    )
    p_diff.add_argument(
        "--noise-threshold-ratio",
        type=float,
        default=0.05,
        help="Noise threshold ratio (default: 0.05)",
    )

    # chart
    p_chart = subparsers.add_parser(
        "chart",
        help="Generate timeline Flame Chart HTML/SVG and Chrome Trace Event JSON",
    )
    p_chart.add_argument(
        "-i", "--input", default="pynytprof.out", help="Input profile (.out) file"
    )
    p_chart.add_argument("-o", "--output-html", help="Output Flame Chart HTML file")
    p_chart.add_argument("--output-trace", help="Output Chrome Trace Event JSON file")
    p_chart.add_argument(
        "-t",
        "--title",
        default="PyNYTProf Timeline Flame Chart",
        help="Chart title",
    )

    return parser


# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

_COMMAND_MAP: Dict[str, Callable[[argparse.Namespace], int]] = {
    "run": cmd_run,
    "html": cmd_html,
    "flamegraph": cmd_flamegraph,
    "callgrind": cmd_callgrind,
    "merge": cmd_merge,
    "diff": cmd_diff,
    "chart": cmd_chart,
}


def main(argv: Optional[List[str]] = None) -> int:
    """CLI メインエントリポイント"""
    parser = create_parser()
    args = parser.parse_args(argv)

    if not args.command:
        parser.print_help()
        return 0

    handler = _COMMAND_MAP.get(args.command)
    if handler is None:
        parser.print_help()
        return 0

    return handler(args)


if __name__ == "__main__":
    sys.exit(main())
