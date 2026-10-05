#!/usr/bin/env python3
"""src/cli/commands/alisp.py

ALisp CLI management subcommand integrating execution, REPL, and audit inspection.
Conforms to DSN-24 and DSN-32. Xenon CC <= 5 (Rank A).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from ..base import BaseCommand


def _print_audit_line(entry_str: str) -> None:
    """Format and print a single JSON Lines audit log entry."""
    try:
        entry = json.loads(entry_str)
        ts = entry.get("timestamp", "")
        ev = entry.get("event_type", "")
        tr = entry.get("trace_id", "")[:8]
        msg = entry.get("message", "")
        print(f"[{ts}] {ev:<18} (trace:{tr}) {msg}")
    except Exception:
        print(entry_str)


def _load_audit_lines(path: Path, limit: int) -> List[str]:
    """Read recent non-empty lines from audit log file."""
    lines: List[str] = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if stripped:
                lines.append(stripped)
    return lines[-limit:]


class ALispCommand(BaseCommand):
    """Subcommand to execute ALisp files, launch REPL, or inspect audit logs."""

    name = "alisp"
    help_text = "Execute ALisp scripts, launch REPL, or inspect security telemetry."

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        subparsers = parser.add_subparsers(
            dest="alisp_subcommand", help="ALisp subaction"
        )

        # run <file>
        run_parser = subparsers.add_parser(
            "run", help="Execute an ALisp script file safely"
        )
        run_parser.add_argument("file", help="Path to .alisp or .lisp source file")
        run_parser.add_argument(
            "--fuel",
            type=int,
            default=100000,
            help="Maximum computational steps (default: 100000)",
        )
        run_parser.add_argument(
            "--timeout",
            type=float,
            default=5.0,
            help="Wall-clock execution timeout in seconds (default: 5.0)",
        )
        run_parser.add_argument(
            "--memory-limit",
            type=int,
            default=512 * 1024 * 1024,
            help="Physical memory quota in bytes (default: 512MB)",
        )
        run_parser.add_argument(
            "--no-sandbox",
            action="store_true",
            help="Disable OCaps and Python FFI sandbox",
        )
        run_parser.add_argument(
            "--trace",
            action="store_true",
            help="Output W3C Trace ID and telemetry diagnostics",
        )

        # eval <expr>
        eval_parser = subparsers.add_parser(
            "eval", help="Evaluate an inline ALisp S-expression"
        )
        eval_parser.add_argument("expr", help="ALisp S-expression string")
        eval_parser.add_argument(
            "--fuel",
            type=int,
            default=100000,
            help="Maximum computational steps",
        )
        eval_parser.add_argument(
            "--timeout",
            type=float,
            default=5.0,
            help="Wall-clock timeout in seconds",
        )

        # repl
        subparsers.add_parser("repl", help="Launch interactive ALisp security REPL")

        # audit
        audit_parser = subparsers.add_parser(
            "audit", help="Inspect recent ALisp audit events"
        )
        audit_parser.add_argument(
            "-n",
            "--limit",
            type=int,
            default=20,
            help="Number of recent audit events to display (default: 20)",
        )

    def handle(self, args: argparse.Namespace) -> int:
        handlers: Dict[str, Callable[[argparse.Namespace], int]] = {
            "repl": self._handle_repl,
            "run": self._handle_run,
            "eval": self._handle_eval,
            "audit": self._handle_audit,
        }
        subaction = args.alisp_subcommand or "repl"
        handler = handlers.get(subaction)
        if not handler:
            sys.stderr.write(f"Unknown ALisp action: {subaction!r}\n")
            return 1
        return handler(args)

    def _handle_repl(self, _args: argparse.Namespace) -> int:
        from alisp.repl import repl

        repl()
        return 0

    def _handle_run(self, args: argparse.Namespace) -> int:
        file_path = Path(args.file)
        if not file_path.exists():
            sys.stderr.write(f"Error: ALisp file not found: {file_path}\n")
            return 1

        source = file_path.read_text(encoding="utf-8")
        from alisp import ALispEngine, generate_trace_id

        trace_id = generate_trace_id() if args.trace else None
        engine = ALispEngine(default_fuel=args.fuel, sandbox=not args.no_sandbox)
        return self._execute_run(engine, source, args, trace_id)

    def _execute_run(
        self,
        engine: Any,
        source: str,
        args: argparse.Namespace,
        trace_id: Optional[str],
    ) -> int:
        try:
            res = engine.eval(
                source,
                fuel=args.fuel,
                timeout=args.timeout,
                memory_limit=args.memory_limit,
                trace_id=trace_id,
            )
            print(f"=> {res}")
            if trace_id:
                print(f"[TraceContext] trace_id={trace_id}")
            return 0
        except BaseException as e:
            sys.stderr.write(f"ALisp Execution Error: {e}\n")
            if trace_id:
                sys.stderr.write(f"[TraceContext] trace_id={trace_id}\n")
            return 1

    def _handle_eval(self, args: argparse.Namespace) -> int:
        from alisp import eval_alisp

        try:
            res = eval_alisp(args.expr, fuel=args.fuel, timeout=args.timeout)
            print(f"=> {res}")
            return 0
        except BaseException as e:
            sys.stderr.write(f"ALisp Evaluation Error: {e}\n")
            return 1

    def _handle_audit(self, args: argparse.Namespace) -> int:
        from alisp.telemetry import DEFAULT_AUDIT_LOG_PATH

        if not DEFAULT_AUDIT_LOG_PATH.exists():
            print(f"No audit logs found at {DEFAULT_AUDIT_LOG_PATH}")
            return 0

        recent = _load_audit_lines(DEFAULT_AUDIT_LOG_PATH, args.limit)
        print(f"--- ALisp Audit Events ({len(recent)} entries) ---")
        for line in recent:
            _print_audit_line(line)
        return 0
