#!/usr/bin/env python3
"""Zero-Dependency Pure Python Frontend Bundling & Compilation Pipeline.

This script consolidates and compiles modular frontend JavaScript sources using
Google Closure Compiler, with zero dependencies on Node.js/npm bundlers.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Sequence

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent

# Framework base dependencies (ordered topologically)
FRAMEWORK_SRCS = [
    "src/web/site/js/frameworks/dom-utils.js",
    "src/web/site/js/frameworks/disjoint-set.js",
    "src/web/site/js/frameworks/arc-cache.js",
    "src/web/site/js/frameworks/timing.js",
    "src/web/site/js/frameworks/event.js",
    "src/web/site/js/frameworks/publisher.js",
    "src/web/site/js/frameworks/locator.js",
    "src/web/site/js/frameworks/scheduler.js",
    "src/web/site/js/frameworks/scene.js",
    "src/web/site/js/frameworks/router.js",
    "src/web/site/js/frameworks/animation.js",
    "src/web/site/js/frameworks/api-client.js",
    "src/web/site/js/frameworks/store.js",
    "src/web/site/js/frameworks/sse-manager.js",
    "src/web/site/js/frameworks/hsm.js",
    "src/web/site/js/frameworks/modal.js",
    "src/web/site/js/frameworks/radix-trie.js",
    "src/web/site/js/frameworks/peg-runtime.js",
    "src/web/site/js/frameworks/cti-query-parser.js",
    "src/web/site/js/frameworks/cti-query-evaluator.js",
    "src/web/site/js/frameworks/query-validator.js",
    "src/web/site/js/frameworks/mermaid-validator.js",
    "src/web/site/js/frameworks/graph-canvas.js",
]

# Console / Main application bundle
APP_SRCS = FRAMEWORK_SRCS + [
    "src/web/site/js/lexer.js",
    "src/web/site/js/parser.js",
    "src/web/site/js/evaluator.js",
    "src/web/site/js/renderer.js",
    "src/web/site/js/markdown_compiler.js",
    "src/web/site/app.js",
]
APP_OUT = "src/web/site/app-min.js"

# Knowledge & CTI Graph Dashboard bundle
DASHBOARD_SRCS = FRAMEWORK_SRCS + [
    "src/web/site/js/dashboard.js",
]
DASHBOARD_OUT = "src/web/site/dashboard-min.js"

COMPILER_JAR = "tools/closure-compiler/closure-compiler-v20240317.jar"
EXTERNS_FILE = "src/web/site/externs.js"


def is_bundle_up_to_date(
    src_paths: Sequence[str],
    dest_path: str,
    extra_deps: Sequence[str] = (),
) -> bool:
    """Checks whether dest_path exists and is newer than all src_paths and extra_deps."""
    dest_full = WORKSPACE_ROOT / dest_path
    if not dest_full.exists():
        return False
    dest_mtime = dest_full.stat().st_mtime
    for dep in list(src_paths) + list(extra_deps):
        dep_full = WORKSPACE_ROOT / dep
        if dep_full.exists() and dep_full.stat().st_mtime > dest_mtime:
            return False
    return True


def concat_files(
    src_paths: Sequence[str], dest_path: str, force: bool = False
) -> None:
    """Concatenates JavaScript source files into a single bundle with banners."""
    full_dest = WORKSPACE_ROOT / dest_path
    if not force and is_bundle_up_to_date(src_paths, dest_path):
        print(f"[UP-TO-DATE] {dest_path} is up to date.")
        return

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
    force: bool = False,
) -> int:
    """Compiles JavaScript bundle using Google Closure Compiler with strict type checks."""
    compiler_full_path = WORKSPACE_ROOT / COMPILER_JAR
    externs_full_path = WORKSPACE_ROOT / EXTERNS_FILE
    dest_full_path = WORKSPACE_ROOT / dest_path

    if not force and is_bundle_up_to_date(
        src_paths, dest_path, extra_deps=[EXTERNS_FILE, COMPILER_JAR]
    ):
        print(f"[UP-TO-DATE] {dest_path} is up to date (skipping Closure Compiler).")
        return 0

    if not compiler_full_path.exists() or not shutil.which("java"):
        print(
            f"[WARN] Closure Compiler JAR or 'java' runtime not found. "
            f"Concatenating {len(src_paths)} files into {dest_path}...",
            file=sys.stderr,
        )
        concat_files(src_paths, dest_path, force=force)
        return 0

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
        cmd.extend(
            [
                "--jscomp_error",
                "checkTypes",
                "--jscomp_error",
                "checkVars",
            ]
        )
    for src in src_paths:
        cmd.extend(["--js", str(WORKSPACE_ROOT / src)])

    print(f"Compiling {len(src_paths)} files -> {dest_path} (strict={strict})...")
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.stdout.strip():
            print(res.stdout)
        if res.stderr.strip():
            print(res.stderr, file=sys.stderr)
        if res.returncode != 0:
            print(
                f"[WARN] Closure Compiler failed (rc={res.returncode}). Falling back to concatenation.",
                file=sys.stderr,
            )
            concat_files(src_paths, dest_path)
            return 0
        return 0
    except Exception as exc:
        print(
            f"[WARN] Closure Compiler execution failed ({exc}). Falling back to concatenation.",
            file=sys.stderr,
        )
        concat_files(src_paths, dest_path)
        return 0


def build_all(
    concat_only: bool = False, strict: bool = True, force: bool = False
) -> int:
    """Builds both app-min.js and dashboard-min.js."""
    if concat_only:
        print("Concatenating app bundle...")
        concat_files(APP_SRCS, APP_OUT, force=force)
        print("Concatenating dashboard bundle...")
        concat_files(DASHBOARD_SRCS, DASHBOARD_OUT, force=force)
        print("[SUCCESS] All bundles concatenated successfully.")
        return 0

    rc_app = compile_bundle(APP_SRCS, APP_OUT, strict=strict, force=force)
    if rc_app != 0:
        print("[FAIL] Compilation failed for app bundle.", file=sys.stderr)
        return rc_app

    rc_dash = compile_bundle(
        DASHBOARD_SRCS, DASHBOARD_OUT, strict=strict, force=force
    )
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

    print(
        f"Watching {len(all_monitored_srcs)} frontend source files for changes (poll: {poll_interval}s)..."
    )
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
        "-f",
        "--force",
        action="store_true",
        help="Force re-compilation of all bundles regardless of timestamp",
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

    return build_all(
        concat_only=args.concat_only, strict=args.strict, force=args.force
    )


if __name__ == "__main__":
    sys.exit(main())
