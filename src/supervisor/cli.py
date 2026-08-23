#!/usr/bin/env python3
"""
CLI entry point for Process Supervisor (Gunicorn-style Process Manager).
Supports commands: start, status, scale, reload, stop, ping.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import List, Optional

from .arbiter import Arbiter
from .config import SupervisorConfig
from .control import ControlClient


def build_parser() -> argparse.ArgumentParser:
    """Constructs the command-line argument parser for the supervisor."""
    parser = argparse.ArgumentParser(
        prog="supervisor",
        description="Gunicorn-style Pre-Fork Process Supervisor & Arbiter Engine",
    )
    parser.add_argument(
        "--config", "-c", type=str, default=None, help="Path to JSON config file"
    )
    parser.add_argument(
        "--control-socket",
        "-s",
        type=str,
        default=None,
        help="Path to Unix domain socket for IPC control",
    )

    subparsers = parser.add_subparsers(dest="command", help="Supervisor command")

    # Command: start
    start_parser = subparsers.add_parser(
        "start", help="Start supervisor arbiter and worker pool"
    )
    start_parser.add_argument(
        "--bind", "-b", type=str, default=None, help="Bind address host:port"
    )
    start_parser.add_argument(
        "--workers", "-w", type=int, default=None, help="Number of worker processes"
    )
    start_parser.add_argument(
        "--worker-class",
        "-k",
        type=str,
        default=None,
        choices=["sync", "gthread", "async"],
        help="Worker concurrency model",
    )
    start_parser.add_argument(
        "--threads",
        "-t",
        type=int,
        default=None,
        help="Threads per worker (for gthread)",
    )
    start_parser.add_argument(
        "--timeout",
        type=float,
        default=None,
        help="Heartbeat watchdog timeout in seconds",
    )
    start_parser.add_argument(
        "--app",
        "-a",
        type=str,
        default=None,
        help="WSGI application URI (module:app)",
    )
    start_parser.add_argument(
        "--no-db", action="store_true", help="Disable managed database worker"
    )

    # Command: status
    subparsers.add_parser(
        "status", help="Query live status of Arbiter and Workers via IPC"
    )

    # Command: scale
    scale_parser = subparsers.add_parser(
        "scale", help="Dynamically resize web worker pool"
    )
    scale_parser.add_argument(
        "--workers", "-w", type=int, required=True, help="New target worker count"
    )

    # Command: reload
    subparsers.add_parser(
        "reload", help="Trigger zero-downtime rolling reload (SIGHUP)"
    )

    # Command: stop
    subparsers.add_parser("stop", help="Gracefully stop supervisor and all workers")

    # Command: ping
    subparsers.add_parser("ping", help="Verify arbiter responsiveness via IPC")

    return parser


def parse_bind(bind_str: str) -> tuple[str, int]:
    """Parses host:port string into tuple."""
    if ":" in bind_str:
        host, port_str = bind_str.split(":", 1)
        return host, int(port_str)
    return "0.0.0.0", int(bind_str)


def main(argv: Optional[List[str]] = None) -> int:
    """Main CLI entrypoint dispatching commands."""
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 1

    workspace_dir = os.path.abspath(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    )

    config_obj: Optional[SupervisorConfig] = None
    if args.config:
        config_obj = SupervisorConfig.from_file(args.config)
    else:
        config_obj = SupervisorConfig.auto_discover(workspace_dir)

    control_sock = args.control_socket or (
        config_obj.control_socket
        if config_obj and config_obj.control_socket
        else os.path.join(workspace_dir, "outputs", "supervisor", "control.sock")
    )

    # Default command is start
    cmd = args.command or "start"

    if cmd == "start":
        if config_obj is None:
            host, port = parse_bind(args.bind) if args.bind else ("0.0.0.0", 8000)
            cfg_dict = {
                "bind_host": host,
                "bind_port": port,
                "worker_class": args.worker_class or "sync",
                "threads": args.threads or 1,
                "timeout": args.timeout or 30.0,
                "app_uri": args.app or "web.server:app",
                "manage_database": not getattr(args, "no_db", False),
                "control_socket": control_sock,
                "workspace_dir": workspace_dir,
            }
            if args.workers is not None:
                cfg_dict["workers"] = args.workers
            config = SupervisorConfig.from_dict(cfg_dict)
        else:
            config = config_obj
            if getattr(args, "bind", None) is not None:
                host, port = parse_bind(args.bind)
                config.bind_host = host
                config.bind_port = port
            if getattr(args, "workers", None) is not None:
                config.workers = args.workers
            if getattr(args, "worker_class", None) is not None:
                config.worker_class = args.worker_class
            if getattr(args, "threads", None) is not None:
                config.threads = args.threads
            if getattr(args, "timeout", None) is not None:
                config.timeout = args.timeout
            if getattr(args, "app", None) is not None:
                config.app_uri = args.app
            if getattr(args, "no_db", False):
                config.manage_database = False
            if control_sock:
                config.control_socket = control_sock
            config.validate()

        print(
            f"🚀 [Supervisor Arbiter] Booting {config.workers} '{config.worker_class}' workers "
            f"on {config.bind_host}:{config.bind_port} (App: {config.app_uri})..."
        )
        arbiter = Arbiter(config)
        try:
            arbiter.start()
            return 0
        except KeyboardInterrupt:
            print("\n[*] Interrupted by user. Shutting down...")
            arbiter.shutdown()
            return 0

    client = ControlClient(control_sock)

    if cmd == "status":
        resp = client.get_status()
        print(json.dumps(resp, indent=2, ensure_ascii=False))
        return 0 if resp.get("status") == "ok" else 1

    if cmd == "scale":
        resp = client.scale_workers(args.workers)
        print(f"[+] Scaled worker pool: {resp}")
        return 0 if resp.get("status") == "ok" else 1

    if cmd == "reload":
        resp = client.reload()
        print(f"[+] Reload command: {resp}")
        return 0 if resp.get("status") == "ok" else 1

    if cmd == "stop":
        resp = client.stop()
        print(f"[+] Stop command: {resp}")
        return 0 if resp.get("status") == "ok" else 1

    if cmd == "ping":
        ok = client.ping()
        print("PONG" if ok else "FAILED")
        return 0 if ok else 1

    print(f"[ERROR] Unknown command: {cmd}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
