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
import time
from typing import Any, Dict, List, Optional, Tuple

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
    start_parser.add_argument(
        "-D",
        "--daemon",
        action="store_true",
        default=None,
        help="Daemonize the supervisor process (run in background)",
    )
    start_parser.add_argument(
        "--log-file",
        type=str,
        default=None,
        help="Log file destination when running in daemon mode",
    )
    start_parser.add_argument(
        "--pid",
        "--pid-file",
        dest="pid_file",
        type=str,
        default=None,
        help="Path to PID file",
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

    # Command: restart
    restart_parser = subparsers.add_parser(
        "restart", help="Gracefully stop running supervisor and start a new one"
    )
    for p in [restart_parser]:
        p.add_argument(
            "--bind",
            "-b",
            type=str,
            default=None,
            help="Address to bind (e.g. 0.0.0.0:8000 or 8000)",
        )
        p.add_argument(
            "--workers",
            "-w",
            type=int,
            default=None,
            help="Number of worker processes",
        )
        p.add_argument(
            "--worker-class",
            "-k",
            type=str,
            default=None,
            help="Worker class: 'sync', 'thread', or 'service'",
        )
        p.add_argument(
            "--threads",
            type=int,
            default=None,
            help="Number of worker threads per process",
        )
        p.add_argument(
            "--timeout",
            "-t",
            type=float,
            default=None,
            help="Worker silence timeout in seconds",
        )
        p.add_argument(
            "--app",
            type=str,
            default=None,
            help="Application entrypoint URI (e.g. web.server:app)",
        )
        p.add_argument(
            "--daemon",
            action="store_true",
            default=None,
            help="Daemonize the supervisor process (run in background)",
        )
        p.add_argument(
            "--log-file",
            type=str,
            default=None,
            help="Log file destination when running in daemon mode",
        )
        p.add_argument(
            "--pid",
            "--pid-file",
            dest="pid_file",
            type=str,
            default=None,
            help="Path to PID file",
        )

    # Command: ping
    subparsers.add_parser("ping", help="Verify arbiter responsiveness via IPC")

    return parser


def parse_bind(bind_str: str) -> tuple[str, int]:
    """Parses host:port string into tuple."""
    if ":" in bind_str:
        host, port_str = bind_str.split(":", 1)
        return host, int(port_str)
    return "0.0.0.0", int(bind_str)


def _apply_optional_args(cfg_dict: Dict[str, Any], args: argparse.Namespace) -> None:
    if args.workers is not None:
        cfg_dict["workers"] = args.workers
    if getattr(args, "daemon", False):
        cfg_dict["daemon"] = True
    if getattr(args, "log_file", None) is not None:
        cfg_dict["log_file"] = args.log_file
    if getattr(args, "pid_file", None) is not None:
        cfg_dict["pid_file"] = args.pid_file


def _resolve_arg(args: argparse.Namespace, name: str, default: Any) -> Any:
    val = getattr(args, name, None)
    return val if val is not None else default


def _build_base_cfg_dict(
    args: argparse.Namespace,
    workspace_dir: str,
    control_sock: str,
) -> Dict[str, Any]:
    host, port = parse_bind(args.bind) if args.bind else ("0.0.0.0", 8000)
    return {
        "bind_host": host,
        "bind_port": port,
        "worker_class": _resolve_arg(args, "worker_class", "sync"),
        "threads": _resolve_arg(args, "threads", 1),
        "timeout": _resolve_arg(args, "timeout", 30.0),
        "app_uri": _resolve_arg(args, "app", "web.server:app"),
        "control_socket": control_sock,
        "workspace_dir": workspace_dir,
    }


def _build_default_config(
    args: argparse.Namespace,
    workspace_dir: str,
    control_sock: str,
) -> SupervisorConfig:
    """Builds default SupervisorConfig from args."""
    cfg_dict = _build_base_cfg_dict(args, workspace_dir, control_sock)
    _apply_optional_args(cfg_dict, args)
    return SupervisorConfig.from_dict(cfg_dict)


def _apply_config_overrides(
    config: SupervisorConfig,
    args: argparse.Namespace,
    control_sock: str,
) -> SupervisorConfig:
    """Applies CLI argument overrides to existing SupervisorConfig."""
    if getattr(args, "bind", None) is not None:
        config.bind_host, config.bind_port = parse_bind(args.bind)

    field_map = [
        ("workers", "workers"),
        ("worker_class", "worker_class"),
        ("threads", "threads"),
        ("timeout", "timeout"),
        ("app", "app_uri"),
        ("daemon", "daemon"),
        ("log_file", "log_file"),
        ("pid_file", "pid_file"),
    ]
    for arg_name, cfg_name in field_map:
        val = getattr(args, arg_name, None)
        if val is not None:
            setattr(config, cfg_name, val)

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


def _handle_already_running(err_msg: str) -> int:
    print(f"\n⚠️  [Supervisor Arbiter Error] {err_msg}")
    print("\n💡 Available actions:")
    print("  • View dashboard: python -m supervisor.cli top")
    print("  • Check status:   python -m supervisor.cli status")
    print("  • Stop arbiter:   python -m supervisor.cli stop")
    print("  • Restart:        python -m supervisor.cli restart\n")
    return 1


def _handle_runtime_error(ex: RuntimeError) -> int:
    err_msg = str(ex)
    if "already running" in err_msg:
        return _handle_already_running(err_msg)
    print(f"\n\u274c [Supervisor Arbiter Error] {err_msg}")
    return 1


def _maybe_daemonize(arbiter: Any, config: SupervisorConfig) -> None:
    if config.daemon:
        print(
            f"\U0001f680 [Supervisor Arbiter] Daemonizing (Log: {config.log_file}, PID: {config.pid_file})..."
        )
        arbiter.daemonize()


def _run_arbiter(config: SupervisorConfig) -> int:
    arbiter = None
    try:
        arbiter = Arbiter(config)
        _maybe_daemonize(arbiter, config)
        arbiter.start()
        return 0
    except KeyboardInterrupt:
        print("\n[*] Interrupted by user. Shutting down...")
        if arbiter:
            arbiter.shutdown()
        return 0
    except RuntimeError as ex:
        return _handle_runtime_error(ex)
    except Exception as ex:
        print(
            f"\n\u274c [Supervisor Arbiter Fatal Error] Unexpected failure during startup: {ex}"
        )
        return 1


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
    return _run_arbiter(config)


def _read_file_pid(path: Optional[str]) -> Optional[int]:
    """Reads PID from given file path if valid."""
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read().strip()
            return int(content) if content.isdigit() else None
    except Exception:
        return None


def _query_ipc_pid(control_sock: str) -> Optional[int]:
    """Queries running Arbiter PID via IPC control client."""
    if not os.path.exists(control_sock):
        return None
    try:
        status_resp = ControlClient(control_sock).get_status()
        return int(status_resp.get("arbiter_pid", 0)) or None
    except Exception:
        return None


def _resolve_old_pid(
    pid_file: Optional[str], lock_file: Optional[str], control_sock: str
) -> Optional[int]:
    """Resolves running Arbiter PID from pid_file, lock_file, or IPC status."""
    return (
        _read_file_pid(pid_file)
        or _read_file_pid(lock_file)
        or _query_ipc_pid(control_sock)
    )


def _escalate_to_sigkill(old_pid: int) -> None:
    import signal

    try:
        os.kill(old_pid, signal.SIGKILL)
    except OSError:
        pass
    time.sleep(0.2)


def _poll_pid_termination(old_pid: int) -> bool:
    import signal

    for step in range(50):
        try:
            os.kill(old_pid, 0)
            if step == 30:
                try:
                    os.kill(old_pid, signal.SIGTERM)
                except OSError:
                    pass
            time.sleep(0.1)
        except OSError:
            return True
    return False


def _wait_for_pid_shutdown(old_pid: int) -> None:
    """Waits up to 5 seconds for old PID shutdown, escalating to SIGKILL if necessary."""
    print(f"[*] Waiting for Arbiter (PID: {old_pid}) to shut down...")
    terminated = _poll_pid_termination(old_pid)
    if not terminated:
        print(
            f"[!] Arbiter (PID: {old_pid}) did not shut down gracefully. Sending SIGKILL..."
        )
        _escalate_to_sigkill(old_pid)


def _cleanup_paths(*paths: Optional[str]) -> None:
    """Safely removes given file paths."""
    for path in paths:
        if path and os.path.exists(path):
            try:
                os.remove(path)
            except OSError:
                pass


def _stop_running_arbiter(control_sock: str, old_pid: Optional[int]) -> Optional[int]:
    import signal

    if os.path.exists(control_sock):
        try:
            resp = ControlClient(control_sock).stop()
            print(
                f"[+] Sent stop signal to running Arbiter via IPC: {resp.get('status', 'sent')}"
            )
        except Exception:
            pass
    if old_pid is not None:
        try:
            os.kill(old_pid, 0)
            os.kill(old_pid, signal.SIGTERM)
        except OSError:
            old_pid = None
    return old_pid


def _handle_restart(
    args: argparse.Namespace,
    config_obj: Optional[SupervisorConfig],
    workspace_dir: str,
    control_sock: str,
) -> int:
    """Handles supervisor restart by stopping running instance and starting fresh."""
    print("🔄 [Supervisor Arbiter] Initiating restart sequence...")
    config = _build_start_config(args, config_obj, workspace_dir, control_sock)
    old_pid = _resolve_old_pid(config.pid_file, config.lock_file, control_sock)
    old_pid = _stop_running_arbiter(control_sock, old_pid)
    if old_pid is not None:
        _wait_for_pid_shutdown(old_pid)
    _cleanup_paths(config.pid_file, config.lock_file, control_sock)
    return _handle_start(args, config_obj, workspace_dir, control_sock)


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


def _resolve_cli_context(
    args: argparse.Namespace,
) -> Tuple[str, Optional[SupervisorConfig], str]:
    """Resolves workspace dir, supervisor config, and control socket path."""
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
    return workspace_dir, config_obj, control_sock


def _dispatch_control_client(
    cmd: str, args: argparse.Namespace, control_sock: str
) -> int:
    """Dispatches command to control client with graceful error messages."""
    try:
        client = ControlClient(control_sock)
        return _handle_control(cmd, args, client)
    except (ConnectionRefusedError, FileNotFoundError, OSError) as ex:
        print(
            f"\n❌ [Supervisor Control Error] Unable to connect to Arbiter control socket ({control_sock}): {ex}"
        )
        print("\n💡 Is Supervisor running?")
        print("  • Start in background: python -m supervisor.cli start --daemon")
        print("  • Start in foreground: python -m supervisor.cli start\n")
        return 1
    except Exception as ex:
        print(f"\n❌ [Supervisor Control Error] Command '{cmd}' failed: {ex}")
        return 1


def main(argv: Optional[List[str]] = None) -> int:
    """Main CLI entrypoint dispatching commands."""
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 1

    workspace_dir, config_obj, control_sock = _resolve_cli_context(args)
    cmd = args.command or "start"
    if cmd == "start":
        return _handle_start(args, config_obj, workspace_dir, control_sock)
    if cmd == "restart":
        return _handle_restart(args, config_obj, workspace_dir, control_sock)

    return _dispatch_control_client(cmd, args, control_sock)


if __name__ == "__main__":
    sys.exit(main())
