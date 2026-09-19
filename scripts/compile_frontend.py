#!/usr/bin/env python3
"""Zero-Dependency Pure Python Frontend Bundling & Compilation Pipeline.

This script consolidates and compiles modular frontend JavaScript sources using
Google Closure Compiler, with zero dependencies on Node.js/npm bundlers.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import List, Sequence

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent

# Framework base dependencies (ordered topologically)
FRAMEWORK_SRCS = [
    "site/js/frameworks/dom-utils.js",
    "site/js/frameworks/disjoint-set.js",
    "site/js/frameworks/arc-cache.js",
    "site/js/frameworks/timing.js",
    "site/js/frameworks/event.js",
    "site/js/frameworks/publisher.js",
    "site/js/frameworks/locator.js",
    "site/js/frameworks/scheduler.js",
    "site/js/frameworks/scene.js",
    "site/js/frameworks/router.js",
    "site/js/frameworks/animation.js",
    "site/js/frameworks/api-client.js",
    "site/js/frameworks/store.js",
    "site/js/frameworks/sse-manager.js",
    "site/js/frameworks/hsm.js",
    "site/js/frameworks/modal.js",
    "site/js/frameworks/radix-trie.js",
    "site/js/frameworks/query-validator.js",
    "site/js/frameworks/graph-canvas.js",
]

# Console / Main application bundle
APP_SRCS = (
    FRAMEWORK_SRCS
    + [
        "site/js/lexer.js",
        "site/js/parser.js",
        "site/js/evaluator.js",
        "site/js/renderer.js",
        "site/js/markdown_compiler.js",
        "site/app.js",
    ]
)
APP_OUT = "site/app-min.js"

# Knowledge & CTI Graph Dashboard bundle
DASHBOARD_SRCS = FRAMEWORK_SRCS + [
    "site/js/dashboard.js",
]
DASHBOARD_OUT = "site/dashboard-min.js"

COMPILER_JAR = "tools/closure-compiler/closure-compiler-v20240317.jar"
EXTERNS_FILE = "site/externs.js"


def concat_files(src_paths: Sequence[str], dest_path: str) -> None:
    """Concatenates JavaScript source files into a single bundle with banners."""
    full_dest = WORKSPACE_ROOT / dest_path
    full_dest.parent.mkdir(parents=True, exist_ok=True)
    
    with open(full_dest, "w", encoding="utf-8") as out_f:
        out_f.write(
            f"/**\n * Auto-generated Pure Python Bundle: {dest_path}\n"
            f" * Generated at: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n"
            f" */\n\n"
        )
        for src in src_paths:
            full_src = WORKSPACE_ROOT / src
            if not full_src.exists():
                print(f"[WARN] Source file not found: {src}", file=sys.stderr)
                continue
            content = full_src.read_text(encoding="utf-8")
            out_f.write(f"// --- BEGIN {src} ---\n")
            out_f.write(content)
            out_f.write(f"\n// --- END {src} ---\n\n")


def compile_bundle(
    src_paths: Sequence[str],
    dest_path: str,
    compilation_level: str = "SIMPLE_OPTIMIZATIONS",
    warning_level: str = "VERBOSE",
    strict: bool = True,
) -> int:
    """Compiles JavaScript bundle using Google Closure Compiler with strict type checks."""
    compiler_full_path = WORKSPACE_ROOT / COMPILER_JAR
    externs_full_path = WORKSPACE_ROOT / EXTERNS_FILE
    dest_full_path = WORKSPACE_ROOT / dest_path

    if not compiler_full_path.exists():
        print(
            f"[ERROR] Closure compiler jar not found at {compiler_full_path}. "
            f"Run 'python3 tools/closure-compiler/setup_compiler.py' first.",
            file=sys.stderr,
        )
        return 1

    cmd: List[str] = [
        "java",
        "-jar",
        str(compiler_full_path),
        "--compilation_level",
        compilation_level,
        "--warning_level",
        warning_level,
        "--language_in",
        "ECMASCRIPT_NEXT",
        "--language_out",
        "ECMASCRIPT_2020",
        "--externs",
        str(externs_full_path),
        "--js_output_file",
        str(dest_full_path),
    ]
    if strict:
        cmd.extend([
            "--jscomp_error",
            "checkTypes",
            "--jscomp_error",
            "checkVars",
        ])
    for src in src_paths:
        cmd.extend(["--js", str(WORKSPACE_ROOT / src)])

    print(f"Compiling {len(src_paths)} files -> {dest_path} (strict={strict})...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.stdout.strip():
        print(res.stdout)
    if res.stderr.strip():
        print(res.stderr, file=sys.stderr)
    return res.returncode


def build_all(concat_only: bool = False, strict: bool = True) -> int:
    """Builds both app-min.js and dashboard-min.js."""
    if concat_only:
        print("Concatenating app bundle...")
        concat_files(APP_SRCS, APP_OUT)
        print("Concatenating dashboard bundle...")
        concat_files(DASHBOARD_SRCS, DASHBOARD_OUT)
        print("[SUCCESS] All bundles concatenated successfully.")
        return 0

    rc_app = compile_bundle(APP_SRCS, APP_OUT, strict=strict)
    if rc_app != 0:
        print("[FAIL] Compilation failed for app bundle.", file=sys.stderr)
        return rc_app

    rc_dash = compile_bundle(DASHBOARD_SRCS, DASHBOARD_OUT, strict=strict)
    if rc_dash != 0:
        print("[FAIL] Compilation failed for dashboard bundle.", file=sys.stderr)
        return rc_dash

    print("[SUCCESS] All frontend bundles compiled successfully with 0 errors.")
    return 0


def watch_and_rebuild(
    concat_only: bool = False, poll_interval: float = 1.0, strict: bool = True
) -> None:
    """Watches source files and triggers automatic rebuild on changes."""
    all_monitored_srcs = set(APP_SRCS + DASHBOARD_SRCS + [EXTERNS_FILE])
    last_mtimes = {}

    for src in all_monitored_srcs:
        p = WORKSPACE_ROOT / src
        if p.exists():
            last_mtimes[src] = p.stat().st_mtime

    print(f"Watching {len(all_monitored_srcs)} frontend source files for changes (poll: {poll_interval}s)...")
    print("Press Ctrl+C to stop.")

    try:
        while True:
            time.sleep(poll_interval)
            changed = False
            for src in all_monitored_srcs:
                p = WORKSPACE_ROOT / src
                if not p.exists():
                    continue
                current_mtime = p.stat().st_mtime
                if src not in last_mtimes or current_mtime > last_mtimes[src]:
                    print(f"File changed: {src}")
                    last_mtimes[src] = current_mtime
                    changed = True
            if changed:
                print("Rebuilding frontend bundles...")
                build_all(concat_only=concat_only, strict=strict)
    except KeyboardInterrupt:
        print("\nWatcher stopped.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Pure Python Zero-Dependency Frontend Bundling Pipeline"
    )
    parser.add_argument(
        "--concat-only",
        action="store_true",
        help="Only concatenate source files without invoking Closure Compiler",
    )
    parser.add_argument(
        "--strict",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Enforce strict static type checking (--jscomp_error checkTypes, checkVars) (default: True)",
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        help="Watch monitored frontend source files and rebuild automatically",
    )
    parser.add_argument(
        "--poll-interval",
        type=float,
        default=1.0,
        help="Polling interval in seconds for --watch mode (default: 1.0)",
    )

    args = parser.parse_args()

    if args.watch:
        watch_and_rebuild(
            concat_only=args.concat_only,
            poll_interval=args.poll_interval,
            strict=args.strict,
        )
        return 0

    return build_all(concat_only=args.concat_only, strict=args.strict)


if __name__ == "__main__":
    sys.exit(main())
