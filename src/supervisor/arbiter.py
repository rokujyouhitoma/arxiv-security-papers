#!/usr/bin/env python3
"""
Arbiter (Master Process) for Generalized Process Supervisor.
Pre-binds listening sockets, orchestrates declarative worker pools and managed services,
traps POSIX signals, enforces heartbeat watchdogs, and hosts the Unix domain socket IPC control server.
"""

from __future__ import annotations

import importlib
import logging
import os
import signal
import socket
import sys
import time
import traceback
from typing import Any, Callable, Dict, List, NoReturn, Optional, Set, cast

from .config import SupervisorConfig
from .contracts import (
    DefaultLifecycleHook,
    LifecycleHook,
    ServiceRole,
    ServiceState,
    WorkerSpec,
)
from .control import ControlServer
from .heartbeat import HeartbeatWatchdog
from .workers import WORKER_CLASSES, BaseWorker, ManagedServiceWorker, SyncWorker


class ManagedPool:
    """Represents an isolated, managed process pool configured via WorkerSpec."""

    def __init__(self, spec: WorkerSpec) -> None:
        self.spec = spec
        self.name = spec.name
        self.workers: Dict[int, BaseWorker] = {}
        self.target_count = spec.target_count
        self.state: ServiceState = ServiceState.READY


class Arbiter:
    """
    Generic master process orchestrator managing declarative worker pools and life cycles.
    """

    def __init__(
        self,
        config: Optional[SupervisorConfig] = None,
        specs: Optional[List[WorkerSpec]] = None,
    ) -> None:
        self.config = config or SupervisorConfig()
        self.watchdog = HeartbeatWatchdog(timeout=self.config.timeout)
        self.server_socket: Optional[socket.socket] = None
        self.control_server: Optional[ControlServer] = None
        self.wsgi_app: Optional[Callable[..., Any]] = None

        self.pid = os.getpid()
        self.running = False
        self.boot_time = time.time()

        # Generic Pool Registry (pool_name -> ManagedPool)
        self.pools: Dict[str, ManagedPool] = {}
        self.reloading_old_pids: Set[int] = set()
        self._signal_queue: List[int] = []

        # Initialize pools from provided specs or config
        self._init_pools(specs)

    def _init_pools(self, custom_specs: Optional[List[WorkerSpec]] = None) -> None:
        """Registers managed pools from custom specs or auto-constructed config specs."""
        specs = custom_specs or self.config.build_worker_specs()
        for spec in specs:
            self.register_pool(spec)

    def register_pool(self, spec: WorkerSpec) -> ManagedPool:
        """Registers a declarative WorkerSpec as an active managed pool."""
        pool = ManagedPool(spec)
        self.pools[spec.name] = pool
        return pool

    def load_wsgi_app(self) -> Callable[..., Any]:
        """Dynamically imports and resolves the target WSGI application object."""
        if self.wsgi_app:
            return self.wsgi_app

        app_uri = self.config.app_uri
        if ":" in app_uri:
            module_name, obj_name = app_uri.split(":", 1)
        else:
            module_name, obj_name = app_uri, "application"

        try:
            mod = importlib.import_module(module_name)
            app_obj = getattr(mod, obj_name)
            self.wsgi_app = cast(Callable[..., Any], app_obj)
            return self.wsgi_app
        except Exception:
            # Fallback to minimal WSGI app if import fails
            def fallback_app(
                environ: Dict[str, Any], start_response: Callable[..., Any]
            ) -> List[bytes]:
                start_response("200 OK", [("Content-Type", "application/json")])
                return [b'{"status":"ok","message":"Supervisor Active"}']

            self.wsgi_app = fallback_app
            return fallback_app

    def load_hook(self, hook_uri: Optional[str]) -> LifecycleHook:
        """Dynamically imports and instantiates a LifecycleHook from URI ('module.path:ClassName')."""
        if not hook_uri:
            return DefaultLifecycleHook()
        if ":" in hook_uri:
            module_name, obj_name = hook_uri.split(":", 1)
        else:
            module_name, obj_name = hook_uri, "LifecycleHook"
        try:
            mod = importlib.import_module(module_name)
            cls_obj = getattr(mod, obj_name)
            instance = cls_obj()
            if isinstance(instance, LifecycleHook):
                return instance
            return DefaultLifecycleHook()
        except Exception:
            return DefaultLifecycleHook()

    def init_server_socket(self) -> socket.socket:
        """Pre-binds listening socket to allow child worker inheritance."""
        if self.server_socket is not None:
            return self.server_socket

        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except (AttributeError, OSError):
            pass

        sock.bind((self.config.bind_host, self.config.bind_port))
        sock.listen(self.config.backlog)
        sock.setblocking(False)
        self.server_socket = sock
        return sock

    def init_signals(self) -> None:
        """Configures POSIX signal handlers on the Arbiter process."""
        signals = [
            signal.SIGTERM,
            signal.SIGINT,
            signal.SIGHUP,
            signal.SIGQUIT,
            signal.SIGCHLD,
            signal.SIGUSR1,
        ]
        if hasattr(signal, "SIGTTIN"):
            signals.append(signal.SIGTTIN)
        if hasattr(signal, "SIGTTOU"):
            signals.append(signal.SIGTTOU)

        for sig in signals:
            try:
                signal.signal(sig, self._signal_handler)
            except (ValueError, OSError):
                pass

    def _signal_handler(self, signum: int, _frame: Any) -> None:
        """Pushes received signals onto the internal event queue for deferred loop handling."""
        self._signal_queue.append(signum)

    def _handle_status_command(self) -> Dict[str, Any]:
        """Handles status query command with dynamic pool metrics."""
        pools_meta: Dict[str, Any] = {}
        for name, pool in self.pools.items():
            pools_meta[name] = {
                "target": pool.target_count,
                "active": len(pool.workers),
                "pids": list(pool.workers.keys()),
                "role": (
                    pool.spec.role.value
                    if hasattr(pool.spec.role, "value")
                    else str(pool.spec.role)
                ),
            }

        return {
            "status": "ok",
            "arbiter_pid": self.pid,
            "uptime": round(time.time() - self.boot_time, 2),
            "pools": pools_meta,
            "workers": self.watchdog.get_all_statuses(),
        }

    def _resolve_pool_name(self, target_label: str) -> Optional[str]:
        """Resolves target pool name from registered pools."""
        lbl = target_label.strip().lower()
        for name in self.pools:
            if name.lower() == lbl:
                return name
        return None

    def _extract_scale_target(self, req: Dict[str, Any]) -> Optional[str]:
        """Extracts and validates target pool name from scale request."""
        target_label = str(
            req.get("pool")
            or req.get("name")
            or req.get("label")
            or req.get("type")
            or ""
        )
        if not target_label and self.pools:
            return next(iter(self.pools))
        return self._resolve_pool_name(target_label)

    def _handle_scale_command(self, req: Dict[str, Any]) -> Dict[str, Any]:
        """Handles dynamic pool-isolated scaling command."""
        pool_name = self._extract_scale_target(req)
        if not pool_name or pool_name not in self.pools:
            return {
                "status": "error",
                "error": f"Unknown target worker pool: '{req.get('pool', '')}'",
            }

        raw_count = req.get("workers")
        if raw_count is None:
            raw_count = req.get("count")
        if raw_count is None:
            new_count = self.pools[pool_name].target_count
        else:
            new_count = int(raw_count)

        if new_count < 1:
            return {"status": "error", "error": "Worker count must be >= 1"}

        self.scale(pool_name, new_count)
        return {
            "status": "ok",
            "target_pool": pool_name,
            "target_workers": self.pools[pool_name].target_count,
            "active_workers": len(self.pools[pool_name].workers),
        }

    def handle_control_command(self, req: Dict[str, Any]) -> Dict[str, Any]:
        """Dispatches administrative commands received from the Unix control socket."""
        cmd = req.get("cmd", "")
        if cmd == "ping":
            return {"status": "ok", "message": "pong", "timestamp": time.time()}
        if cmd == "status":
            return self._handle_status_command()
        if cmd == "scale":
            return self._handle_scale_command(req)
        if cmd == "reload":
            self.reload()
            return {"status": "ok", "message": "Rolling reload triggered"}
        if cmd == "stop":
            self.running = False
            return {"status": "ok", "message": "Shutdown sequence initiated"}
        return {"status": "error", "error": f"Unknown command: '{cmd}'"}

    def _run_child_worker(self, spec: WorkerSpec, worker_id: str) -> NoReturn:
        """Executes worker lifecycle loop in child process."""
        self.init_child_process()
        if spec.worker_class == "service" or spec.role == ServiceRole.STATEFUL_SERVICE:
            hook_uri = spec.metadata.get("hook_uri") if spec.metadata else None
            hook = spec.hook or self.load_hook(hook_uri)
            svc_worker = ManagedServiceWorker(
                worker_id=worker_id,
                config=self.config,
                service_name=spec.name,
                hook=hook,
                sync_interval=spec.sync_interval,
            )
            svc_worker.run()
        else:
            worker_cls = WORKER_CLASSES.get(spec.worker_class, SyncWorker)
            app = spec.app_target or self.load_wsgi_app()
            sock = spec.server_socket or self.server_socket
            web_worker = worker_cls(
                worker_id=worker_id,
                config=self.config,
                server_socket=sock,
                app_target=app,
            )
            web_worker.run()
        sys.exit(0)

    def spawn_worker(self, pool_name: Optional[str] = None) -> Optional[int]:
        """Forks a new child worker for the designated managed pool."""
        if not pool_name:
            if not self.pools:
                return None
            pool_name = next(iter(self.pools))
        else:
            pool_name = self._resolve_pool_name(pool_name) or pool_name

        pool = self.pools.get(pool_name)
        if not pool:
            return None

        spec = pool.spec
        worker_id = f"{spec.name}_{int(time.time() * 1000) % 100000}"

        try:
            pid = os.fork()
        except AttributeError:
            return None

        if pid == 0:
            self._run_child_worker(spec, worker_id)
        else:
            pool.workers[pid] = cast(BaseWorker, None)
            self.watchdog.register_worker(pid, spec.name)
            return pid

    def init_child_process(self) -> None:
        """Resets signal handlers and closes administrative control socket in child."""
        if self.control_server:
            self.control_server.close_in_child()
        # Reset signal handlers in child
        signal.signal(signal.SIGCHLD, signal.SIG_DFL)

    def adjust_pool(self, pool_name: str, target: Optional[int] = None) -> None:
        """Maintains target worker count for a specific pool (scaling up or down)."""
        pool_name = self._resolve_pool_name(pool_name) or pool_name
        pool = self.pools.get(pool_name)
        if not pool:
            return

        if target is not None:
            pool.target_count = max(0, target)

        current_active = len(pool.workers)
        target_count = pool.target_count

        if current_active < target_count:
            needed = target_count - current_active
            for _ in range(needed):
                self.spawn_worker(pool_name)
        elif current_active > target_count:
            excess = current_active - target_count
            pids = list(pool.workers.keys())[:excess]
            for pid in pids:
                try:
                    os.kill(pid, signal.SIGTERM)
                except OSError:
                    pass
                pool.workers.pop(pid, None)
                self.watchdog.remove_worker(pid)

    def scale(self, pool_name: str, count: int) -> None:
        """Sets target pool capacity and adjusts pool size immediately."""
        pool_name = self._resolve_pool_name(pool_name) or pool_name
        if pool_name in self.pools:
            self.pools[pool_name].target_count = count
            self.adjust_pool(pool_name, count)

    def _find_pool_for_pid(self, pid: int) -> Optional[ManagedPool]:
        """Locates the ManagedPool containing the given worker PID."""
        for pool in self.pools.values():
            if pid in pool.workers:
                return pool
        return None

    def _handle_child_exit(self, pid: int, status: int = 0) -> None:
        """Cleans up terminated child process and restarts it if unexpected."""
        self.watchdog.remove_worker(pid)
        pool = self._find_pool_for_pid(pid)
        if not pool:
            return

        pool.workers.pop(pid, None)
        exit_code = (
            os.waitstatus_to_exitcode(status)
            if hasattr(os, "waitstatus_to_exitcode")
            else (status >> 8)
        )

        if pool.spec.role == ServiceRole.ONESHOT_TASK:
            if exit_code == 0:
                pool.state = ServiceState.COMPLETED
                logging.info(
                    "[Arbiter] ONESHOT task '%s' completed successfully (PID: %d).",
                    pool.name,
                    pid,
                )
            else:
                if pool.spec.retry_count < pool.spec.max_retries and self.running:
                    pool.spec.retry_count += 1
                    logging.warning(
                        "[Arbiter] ONESHOT task '%s' failed (Exit code: %d). Retrying (%d/%d)...",
                        pool.name,
                        exit_code,
                        pool.spec.retry_count,
                        pool.spec.max_retries,
                    )
                    self.spawn_worker(pool.name)
                else:
                    pool.state = ServiceState.FAILED
                    logging.error(
                        "[Arbiter] ONESHOT task '%s' failed permanently (Exit code: %d).",
                        pool.name,
                        exit_code,
                    )
            return

        if self.running and pid not in self.reloading_old_pids:
            self.spawn_worker(pool.name)
        self.reloading_old_pids.discard(pid)

    def handle_sigchld(self) -> None:
        """Reaps terminated children and respawns if killed unexpectedly."""
        while True:
            try:
                pid, status = os.waitpid(-1, os.WNOHANG)
                if pid <= 0:
                    break
            except (OSError, ChildProcessError):
                break
            self._handle_child_exit(pid, status)

    def reload(self, pool_name: Optional[str] = None) -> None:
        """Performs zero-downtime rolling restart of workers in designated or all stateless pools."""
        target_pools = (
            [self.pools[pool_name]]
            if (pool_name and pool_name in self.pools)
            else list(self.pools.values())
        )

        for pool in target_pools:
            if pool.spec.role != ServiceRole.STATELESS_POOL and pool_name is None:
                # Do not restart stateful background services during default web rolling reload
                continue

            old_pids = set(pool.workers.keys())
            self.reloading_old_pids.update(old_pids)

            # Spawn replacement workers
            for _ in range(pool.target_count):
                self.spawn_worker(pool.name)

            # Graceful drain old workers
            for pid in old_pids:
                try:
                    os.kill(pid, signal.SIGQUIT)
                except OSError:
                    pass

    def check_hung_workers(self) -> None:
        """Checks for unresponsive workers and kills them with SIGKILL.

        Only workers with ``is_handling_request=True`` are considered hung
        (see HeartbeatWatchdog.get_hung_workers). After killing a hung worker,
        the corresponding pool worker is respawned to maintain pool size.
        """
        hung_pids = self.watchdog.get_hung_workers(self.config.request_timeout)
        for pid in hung_pids:
            pool = self._find_pool_for_pid(pid)
            if pool:
                pool_name = "db" if pool.name in ("database", "db") else pool.name
            else:
                pool_name = "web"
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
            self.watchdog.remove_worker(pid)
            if pool:
                pool.workers.pop(pid, None)
            if self.running:
                self.spawn_worker(pool_name)

    def _drain_and_kill(
        self, workers: Dict[int, Any], initial_sig: int, timeout: float
    ) -> None:
        """Signals workers, waits for them to exit, and kills any remaining."""
        for pid in list(workers.keys()):
            try:
                os.kill(pid, initial_sig)
            except OSError:
                pass

        start_t = time.time()
        while workers and (time.time() - start_t < timeout):
            self.handle_sigchld()
            time.sleep(0.1)

        for pid in list(workers.keys()):
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass

    def _cleanup_resources(self) -> None:
        """Cleans up control server, server socket, and PID file."""
        if self.control_server:
            self.control_server.stop()
        if self.server_socket:
            try:
                self.server_socket.close()
            except OSError:
                pass
            self.server_socket = None

        if self.config.pid_file and os.path.exists(self.config.pid_file):
            try:
                os.unlink(self.config.pid_file)
            except OSError:
                pass

    def _build_dependency_graph(self) -> tuple[Dict[str, int], Dict[str, list[str]]]:
        """Builds in-degree mapping and adjacency list for pools."""
        in_degree: Dict[str, int] = {p: 0 for p in self.pools}
        adj: Dict[str, list[str]] = {p: [] for p in self.pools}

        for name, pool in self.pools.items():
            deps = getattr(pool.spec, "dependencies", []) or []
            for dep in deps:
                dep_name = self._resolve_pool_name(dep) or dep
                if dep_name in self.pools:
                    adj[dep_name].append(name)
                    in_degree[name] += 1
        return in_degree, adj

    def resolve_boot_order(self) -> list[str]:
        """Resolves pool/service boot order using Kahn's topological sort algorithm."""
        in_degree, adj = self._build_dependency_graph()

        zero_in = [n for n, deg in in_degree.items() if deg == 0]
        zero_in.sort(
            key=lambda n: (
                0 if self.pools[n].spec.role != ServiceRole.STATELESS_POOL else 1
            )
        )
        ordered: list[str] = []

        while zero_in:
            curr = zero_in.pop(0)
            ordered.append(curr)
            for neighbor in adj[curr]:
                in_degree[neighbor] -= 1
                if in_degree[neighbor] == 0:
                    zero_in.append(neighbor)

        if len(ordered) != len(self.pools):
            unresolved = set(self.pools) - set(ordered)
            raise ValueError(
                f"Circular dependency detected in supervisor pools: {unresolved}"
            )

        return ordered

    def shutdown(self) -> None:
        """
        Executes strictly ordered graceful shutdown sequence:
        1. Drain pools in reverse topological dependency order.
        2. Close listening sockets and clean up control server.
        """
        self.running = False

        try:
            shutdown_order = list(reversed(self.resolve_boot_order()))
        except Exception:
            shutdown_order = list(self.pools.keys())

        for pool_name in shutdown_order:
            pool = self.pools.get(pool_name)
            if pool:
                sig = (
                    signal.SIGQUIT
                    if pool.spec.role == ServiceRole.STATELESS_POOL
                    else signal.SIGTERM
                )
                self._drain_and_kill(pool.workers, sig, self.config.graceful_timeout)

        self._cleanup_resources()

    def _check_existing_pid(self) -> None:
        """Checks if a valid running instance is already registered in the PID file."""
        if not self.config.pid_file or not os.path.exists(self.config.pid_file):
            return
        existing_pid = None
        try:
            with open(self.config.pid_file, "r", encoding="utf-8") as f:
                content = f.read().strip()
            if content:
                existing_pid = int(content)
                if existing_pid != self.pid:
                    os.kill(existing_pid, 0)
                    raise RuntimeError(
                        f"Supervisor arbiter is already running with PID {existing_pid}."
                    )
        except (ValueError, ProcessLookupError):
            pass
        except PermissionError:
            raise RuntimeError(
                f"Supervisor arbiter is running with PID {existing_pid} (Permission Denied)."
            )

    def daemonize(self) -> None:
        """Detaches the supervisor from the controlling terminal using POSIX double-forking."""
        self._check_existing_pid()

        try:
            pid = os.fork()
            if pid > 0:
                sys.exit(0)
        except OSError as e:
            raise RuntimeError(f"First fork failed: {e}") from e

        os.setsid()
        os.umask(0)

        try:
            pid = os.fork()
            if pid > 0:
                sys.exit(0)
        except OSError as e:
            raise RuntimeError(f"Second fork failed: {e}") from e

        self.pid = os.getpid()
        self._redirect_standard_streams()

    @staticmethod
    def _safe_dup2(src_fd: int, dst_fd: int) -> None:
        """Safely duplicates src_fd onto dst_fd ignoring OS pseudofile errors."""
        try:
            os.dup2(src_fd, dst_fd)
        except Exception:
            pass

    def _open_log_fd(self) -> int:
        """Opens and returns target log file descriptor, or /dev/null if unconfigured."""
        if self.config.log_file:
            log_dir = os.path.dirname(os.path.abspath(self.config.log_file))
            if log_dir:
                os.makedirs(log_dir, exist_ok=True)
            return os.open(
                self.config.log_file,
                os.O_WRONLY | os.O_CREAT | os.O_APPEND,
                0o644,
            )
        return os.open(os.devnull, os.O_RDWR)

    def _redirect_standard_streams(self) -> None:
        """Redirects stdin to /dev/null and stdout/stderr to configured log_file."""
        for stream in (sys.stdout, sys.stderr):
            try:
                stream.flush()
            except Exception:
                pass

        try:
            devnull = os.open(os.devnull, os.O_RDWR)
            self._safe_dup2(devnull, 0)
            out_fd = self._open_log_fd()
            self._safe_dup2(out_fd, 1)
            self._safe_dup2(out_fd, 2)
            if out_fd > 2:
                os.close(out_fd)
            if devnull > 2:
                os.close(devnull)
        except Exception as exc:
            logging.error("[Arbiter] Failed to redirect standard streams: %s", exc)

    def _write_pid_file(self) -> None:
        """Writes PID file if configured."""
        self._check_existing_pid()
        if not self.config.pid_file:
            return
        os.makedirs(
            os.path.dirname(os.path.abspath(self.config.pid_file)), exist_ok=True
        )
        with open(self.config.pid_file, "w", encoding="utf-8") as f:
            f.write(str(self.pid))

    def _start_control_server(self) -> None:
        """Starts IPC Control Server if configured."""
        if not self.config.control_socket:
            return
        self.control_server = ControlServer(
            socket_path=self.config.control_socket,
            command_handler=self.handle_control_command,
        )
        self.control_server.start()

    def _dispatch_single_signal(self, sig: int) -> bool:
        """Dispatches an individual signal. Returns False if arbiter should stop."""
        if sig in (signal.SIGTERM, signal.SIGINT):
            self.running = False
            return False
        if sig == signal.SIGHUP:
            self.reload()
        elif hasattr(signal, "SIGTTIN") and sig == signal.SIGTTIN:
            self._handle_sigttin()
        elif hasattr(signal, "SIGTTOU") and sig == signal.SIGTTOU:
            self._handle_sigttou()
        elif sig == signal.SIGCHLD:
            self.handle_sigchld()
        return True

    def _handle_sigttin(self) -> None:
        if self.pools:
            first_pool = next(iter(self.pools))
            self.scale(first_pool, self.pools[first_pool].target_count + 1)

    def _handle_sigttou(self) -> None:
        if self.pools:
            first_pool = next(iter(self.pools))
            if self.pools[first_pool].target_count > 1:
                self.scale(first_pool, self.pools[first_pool].target_count - 1)

    def _handle_queued_signals(self) -> None:
        """Processes queued OS signals."""
        while self._signal_queue:
            sig = self._signal_queue.pop(0)
            if not self._dispatch_single_signal(sig):
                break

    def start(self) -> None:
        """Main lifecycle entrypoint starting the Supervisor cluster."""
        self.running = True
        self.init_signals()
        self.init_server_socket()
        self._write_pid_file()
        self._start_control_server()

        # DAG-ordered Pool Boot Sequence
        boot_order = self.resolve_boot_order()
        for pool_name in boot_order:
            self.adjust_pool(pool_name)

        # Master Event Loop
        try:
            while self.running:
                self._handle_queued_signals()
                if not self.running:
                    break
                self.handle_sigchld()
                self.check_hung_workers()
                time.sleep(0.5)
        except BaseException as exc:  # pragma: no cover
            logging.critical(
                "[Arbiter] Unexpected crash in main event loop: %s\n%s",
                exc,
                traceback.format_exc(),
            )
        finally:
            self.shutdown()


ProcessArbiter = Arbiter

__all__ = ["Arbiter", "ProcessArbiter"]
