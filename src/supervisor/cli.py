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
from .top import run_top


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

    # Command: status
    subparsers.add_parser(
        "status", help="Query live status of Arbiter and Workers via IPC"
    )

    # Command: top
    top_parser = subparsers.add_parser(
        "top", help="Live top-like interactive process & worker monitoring dashboard"
    )
    top_parser.add_argument(
        "--interval",
        "-i",
        type=float,
        default=1.0,
        help="Refresh interval in seconds (default: 1.0)",
    )
    top_parser.add_argument(
        "--once",
        "-1",
        action="store_true",
        help="Print dashboard once and exit",
    )
    top_parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI color output",
    )

    # Command: scale
    scale_parser = subparsers.add_parser(
        "scale", help="Dynamically resize worker pool by pool name"
    )
    scale_parser.add_argument(
        "--workers", "-w", type=int, required=True, help="New target worker count"
    )
    scale_parser.add_argument(
        "--pool",
        "-p",
        "--label",
        dest="pool",
        type=str,
        default="",
        help="Target worker pool to scale (default: first pool)",
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


def _build_default_config(
    args: argparse.Namespace,
    workspace_dir: str,
    control_sock: str,
) -> SupervisorConfig:
    """Builds default SupervisorConfig from args."""
    host, port = parse_bind(args.bind) if args.bind else ("0.0.0.0", 8000)
    cfg_dict = {
        "bind_host": host,
        "bind_port": port,
        "worker_class": args.worker_class or "sync",
        "threads": args.threads or 1,
        "timeout": args.timeout or 30.0,
        "app_uri": args.app or "web.server:app",
        "control_socket": control_sock,
        "workspace_dir": workspace_dir,
    }
    if args.workers is not None:
        cfg_dict["workers"] = args.workers
    return SupervisorConfig.from_dict(cfg_dict)


def _apply_config_overrides(
    config: SupervisorConfig,
    args: argparse.Namespace,
    control_sock: str,
) -> SupervisorConfig:
    """Applies CLI argument overrides to existing SupervisorConfig."""
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
    if control_sock:
        config.control_socket = control_sock
    config.validate()
    return config


def _build_start_config(
    args: argparse.Namespace,
    config_obj: Optional[SupervisorConfig],
    workspace_dir: str,
    control_sock: str,
) -> SupervisorConfig:
    """Builds and validates SupervisorConfig for start command."""
    if config_obj is None:
        return _build_default_config(args, workspace_dir, control_sock)
    return _apply_config_overrides(config_obj, args, control_sock)


def _handle_start(
    args: argparse.Namespace,
    config_obj: Optional[SupervisorConfig],
    workspace_dir: str,
    control_sock: str,
) -> int:
    """Handles supervisor arbiter start command."""
    config = _build_start_config(args, config_obj, workspace_dir, control_sock)
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


def _handle_status_cmd(client: ControlClient) -> int:
    """Handles supervisor status command."""
    resp = client.get_status()
    print(json.dumps(resp, indent=2, ensure_ascii=False))
    return 0 if resp.get("status") == "ok" else 1


def _handle_top_cmd(args: argparse.Namespace, client: ControlClient) -> int:
    """Handles supervisor top monitoring command."""
    return run_top(
        client=client,
        interval=getattr(args, "interval", 1.0),
        once=getattr(args, "once", False),
        no_color=getattr(args, "no_color", False),
    )


def _cmd_scale(args: argparse.Namespace, client: ControlClient) -> int:
    pool_name = getattr(args, "pool", "") or getattr(args, "label", "")
    resp = client.scale_workers(args.workers, pool=pool_name)
    print(f"[+] Scaled worker pool ({pool_name or 'default'}): {resp}")
    return 0 if resp.get("status") == "ok" else 1


def _cmd_reload(client: ControlClient) -> int:
    resp = client.reload()
    print(f"[+] Reload command: {resp}")
    return 0 if resp.get("status") == "ok" else 1


def _cmd_stop(client: ControlClient) -> int:
    resp = client.stop()
    print(f"[+] Stop command: {resp}")
    return 0 if resp.get("status") == "ok" else 1


def _cmd_ping(client: ControlClient) -> int:
    ok = client.ping()
    print("PONG" if ok else "FAILED")
    return 0 if ok else 1


def _handle_simple_cmd(
    cmd: str, args: argparse.Namespace, client: ControlClient
) -> int:
    """Handles scale, reload, stop, ping control commands."""
    if cmd == "scale":
        return _cmd_scale(args, client)
    if cmd == "reload":
        return _cmd_reload(client)
    if cmd == "stop":
        return _cmd_stop(client)
    if cmd == "ping":
        return _cmd_ping(client)
    print(f"[ERROR] Unknown command: {cmd}")
    return 1


def _handle_control(
    cmd: str,
    args: argparse.Namespace,
    client: ControlClient,
) -> int:
    """Dispatches IPC control commands."""
    if cmd == "status":
        return _handle_status_cmd(client)
    if cmd == "top":
        return _handle_top_cmd(args, client)
    return _handle_simple_cmd(cmd, args, client)


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

    cmd = args.command or "start"
    if cmd == "start":
        return _handle_start(args, config_obj, workspace_dir, control_sock)

    client = ControlClient(control_sock)
    return _handle_control(cmd, args, client)


if __name__ == "__main__":
    sys.exit(main())
