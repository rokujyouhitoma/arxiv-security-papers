#!/usr/bin/env python3
"""
Arbiter (Master Process) for Generalized Process Supervisor.
Pre-binds listening sockets, orchestrates declarative worker pools and managed services,
traps POSIX signals, enforces heartbeat watchdogs, and hosts the Unix domain socket IPC control server.
"""

from __future__ import annotations

import fcntl
import importlib
import logging
import os
import signal
import socket
import sys
import time
import traceback
from typing import (
    Any,
    Callable,
    Dict,
    List,
    NoReturn,
    Optional,
    Set,
    TextIO,
    Tuple,
    cast,
)

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
from .workers import (
    WORKER_CLASSES,
    BaseWorker,
    ManagedServiceWorker,
    QueueWorker,
    SyncWorker,
)


class ManagedPool:
    """Represents an isolated, managed process pool configured via WorkerSpec."""

    def __init__(self, spec: WorkerSpec) -> None:
        self.spec = spec
        self.name = spec.name
        self.workers: Dict[int, BaseWorker] = {}
        self.target_count = spec.target_count
        self.state: ServiceState = ServiceState.READY


def _safe_unlink(path: Optional[str]) -> None:
    """Safely unlinks a file path if it exists."""
    if path and os.path.exists(path):
        try:
            os.unlink(path)
        except OSError:
            pass


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
        self._lock_file_obj: Optional[TextIO] = None

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

    def _create_fallback_wsgi_app(self) -> Callable[..., Any]:
        def fallback_app(
            environ: Dict[str, Any], start_response: Callable[..., Any]
        ) -> List[bytes]:
            start_response("200 OK", [("Content-Type", "application/json")])
            return [b'{"status":"ok","message":"Supervisor Active"}']

        return fallback_app

    def load_wsgi_app(self) -> Callable[..., Any]:
        """Dynamically imports and resolves the target WSGI application object."""
        if self.wsgi_app:
            return self.wsgi_app

        app_uri = self.config.app_uri
        module_name, obj_name = (
            app_uri.split(":", 1) if ":" in app_uri else (app_uri, "application")
        )
        try:
            mod = importlib.import_module(module_name)
            self.wsgi_app = cast(Callable[..., Any], getattr(mod, obj_name))
            return self.wsgi_app
        except Exception:
            self.wsgi_app = self._create_fallback_wsgi_app()
            return self.wsgi_app

    def load_hook(self, hook_uri: Optional[str]) -> LifecycleHook:
        """Dynamically imports and instantiates a LifecycleHook from URI ('module.path:ClassName')."""
        if not hook_uri:
            return DefaultLifecycleHook()
        module_name, obj_name = (
            hook_uri.split(":", 1) if ":" in hook_uri else (hook_uri, "LifecycleHook")
        )
        try:
            mod = importlib.import_module(module_name)
            instance = getattr(mod, obj_name)()
            return (
                instance
                if isinstance(instance, LifecycleHook)
                else DefaultLifecycleHook()
            )
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
        target_label = ""
        for k in ("pool", "name", "label", "type"):
            if k in req:
                target_label = str(req[k])
                break
        if not target_label and self.pools:
            return next(iter(self.pools))
        return self._resolve_pool_name(target_label)

    def _resolve_scale_count(self, req: Dict[str, Any], pool_name: str) -> int:
        raw_count = req.get("workers", req.get("count"))
        if raw_count is None:
            return self.pools[pool_name].target_count
        return int(raw_count)

    def _handle_scale_command(self, req: Dict[str, Any]) -> Dict[str, Any]:
        """Handles dynamic pool-isolated scaling command."""
        pool_name = self._extract_scale_target(req)
        if not pool_name or pool_name not in self.pools:
            return {
                "status": "error",
                "error": f"Unknown target worker pool: '{req.get('pool', '')}'",
            }

        new_count = self._resolve_scale_count(req, pool_name)
        if new_count < 1:
            return {"status": "error", "error": "Worker count must be >= 1"}

        self.scale(pool_name, new_count)
        return {
            "status": "ok",
            "target_pool": pool_name,
            "target_workers": self.pools[pool_name].target_count,
            "active_workers": len(self.pools[pool_name].workers),
        }

    def _handle_reload_cmd(self) -> Dict[str, Any]:
        self.reload()
        return {"status": "ok", "message": "Rolling reload triggered"}

    def _handle_stop_cmd(self) -> Dict[str, Any]:
        self.running = False
        return {"status": "ok", "message": "Shutdown sequence initiated"}

    def _dispatch_control_cmd(
        self, cmd: str, req: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        if cmd == "ping":
            return {"status": "ok", "message": "pong", "timestamp": time.time()}
        if cmd == "status":
            return self._handle_status_command()
        if cmd == "scale":
            return self._handle_scale_command(req)
        return None

    def handle_control_command(self, req: Dict[str, Any]) -> Dict[str, Any]:
        """Dispatches administrative commands received from the Unix control socket."""
        cmd = req.get("cmd", "")
        res = self._dispatch_control_cmd(cmd, req)
        if res is not None:
            return res
        if cmd == "reload":
            return self._handle_reload_cmd()
        if cmd == "stop":
            return self._handle_stop_cmd()
        return {"status": "error", "error": f"Unknown command: '{cmd}'"}

    def _run_service_worker(self, spec: WorkerSpec, worker_id: str) -> None:
        """Executes stateful service worker with LifecycleHook."""
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

    def _run_oneshot_worker(self, spec: WorkerSpec) -> int:
        """Executes one-shot batch task."""
        try:
            if callable(spec.app_target):
                spec.app_target()
            return 0
        except Exception as exc:
            logging.error(
                "[Arbiter] ONESHOT task '%s' raised exception: %s", spec.name, exc
            )
            return 1

    def _run_queue_worker(self, spec: WorkerSpec, worker_id: str) -> None:
        """Executes message queue consumer worker."""
        source_q = spec.metadata.get("source_queue") if spec.metadata else None
        poll_int = (
            float(spec.metadata.get("poll_interval", 0.1)) if spec.metadata else 0.1
        )
        q_worker = QueueWorker(
            worker_id=worker_id,
            config=self.config,
            app_target=spec.app_target,
            source_queue=source_q,
            poll_interval=poll_int,
        )
        q_worker.run()

    def _run_web_worker(self, spec: WorkerSpec, worker_id: str) -> None:
        """Executes standard pre-fork web worker."""
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

    def _run_child_worker(self, spec: WorkerSpec, worker_id: str) -> NoReturn:
        """Executes worker lifecycle loop in child process."""
        self.init_child_process()
        exit_code = 0
        if spec.worker_class == "service" or spec.role == ServiceRole.STATEFUL_SERVICE:
            self._run_service_worker(spec, worker_id)
        elif spec.role == ServiceRole.ONESHOT_TASK:
            exit_code = self._run_oneshot_worker(spec)
        elif spec.worker_class == "queue":
            self._run_queue_worker(spec, worker_id)
        else:
            self._run_web_worker(spec, worker_id)
        sys.exit(exit_code)

    def _extract_slot_from_meta(self, meta: Optional[Dict[str, Any]]) -> Optional[int]:
        if not meta:
            return None
        if "slot_idx" in meta:
            return int(meta["slot_idx"])
        if "worker_id" in meta:
            w_id = str(meta["worker_id"])
            if w_id.split("_")[-1].isdigit():
                return int(w_id.split("_")[-1])
        return None

    def _find_available_slot(self, pool: ManagedPool) -> int:
        """Finds the lowest available numeric slot index (0, 1, 2, ...)."""
        used_slots = {
            slot
            for active_pid in pool.workers.keys()
            if (
                slot := self._extract_slot_from_meta(
                    self.watchdog.get_worker_status(active_pid)
                )
            )
            is not None
        }
        slot_idx = 0
        while slot_idx in used_slots:
            slot_idx += 1
        return slot_idx

    def _find_spawn_candidate_name(self, pool_name: Optional[str]) -> Optional[str]:
        if pool_name:
            return self._resolve_pool_name(pool_name) or pool_name
        return next(iter(self.pools)) if self.pools else None

    def _resolve_spawn_pool(
        self, pool_name: Optional[str]
    ) -> Optional[Tuple[str, ManagedPool]]:
        """Resolves target pool name and ManagedPool instance for spawning."""
        target = self._find_spawn_candidate_name(pool_name)
        if target and target in self.pools:
            return target, self.pools[target]
        return None

    def spawn_worker(self, pool_name: Optional[str] = None) -> Optional[int]:
        """Forks a new child worker for the designated managed pool."""
        target = self._resolve_spawn_pool(pool_name)
        if not target:
            return None
        name, pool = target

        slot_idx = self._find_available_slot(pool)
        worker_id = f"{pool.spec.name}_{slot_idx}"

        try:
            pid = os.fork()
        except AttributeError:
            return None

        if pid == 0:
            self._run_child_worker(pool.spec, worker_id)
        else:
            pool.workers[pid] = cast(BaseWorker, None)
            self.watchdog.register_worker(
                pid,
                pool.spec.name,
                metadata={"slot_idx": slot_idx, "worker_id": worker_id},
            )
            return pid

    def init_child_process(self) -> None:
        """Resets signal handlers, sets death signal on parent exit, and closes control/lock resources."""
        if self._lock_file_obj:
            try:
                self._lock_file_obj.close()
            except Exception:
                pass
            self._lock_file_obj = None

        if self.control_server:
            self.control_server.close_in_child()
        signal.signal(signal.SIGCHLD, signal.SIG_DFL)

        try:
            import ctypes

            libc = ctypes.CDLL("libc.so.6")
            libc.prctl(1, signal.SIGKILL)  # PR_SET_PDEATHSIG = 1
        except Exception:
            pass

    def _scale_down_pool(self, pool: ManagedPool, excess: int) -> None:
        pids = list(pool.workers.keys())[:excess]
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
            pool.workers.pop(pid, None)
            self.watchdog.remove_worker(pid)

    def _scale_up_pool(self, pool_name: str, needed: int) -> None:
        for _ in range(needed):
            self.spawn_worker(pool_name)

    def _adjust_pool_size(self, pool: ManagedPool, pool_name: str) -> None:
        current_active = len(pool.workers)
        if current_active < pool.target_count:
            self._scale_up_pool(pool_name, pool.target_count - current_active)
        elif current_active > pool.target_count:
            self._scale_down_pool(pool, current_active - pool.target_count)

    def adjust_pool(self, pool_name: str, target: Optional[int] = None) -> None:
        """Maintains target worker count for a specific pool (scaling up or down)."""
        resolved_name = self._resolve_pool_name(pool_name) or pool_name
        pool = self.pools.get(resolved_name)
        if not pool:
            return

        if target is not None:
            pool.target_count = max(0, target)

        self._adjust_pool_size(pool, resolved_name)

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

    def _handle_oneshot_exit(self, pool: ManagedPool, pid: int, exit_code: int) -> None:
        if exit_code == 0:
            pool.state = ServiceState.COMPLETED
            logging.info(
                "[Arbiter] ONESHOT task '%s' completed successfully (PID: %d).",
                pool.name,
                pid,
            )
            return

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

    def _resolve_child_exit_code(self, status: int) -> int:
        if hasattr(os, "waitstatus_to_exitcode"):
            return os.waitstatus_to_exitcode(status)
        return status >> 8

    def _handle_child_exit(self, pid: int, status: int = 0) -> None:
        """Cleans up terminated child process and restarts it if unexpected."""
        self.watchdog.remove_worker(pid)
        pool = self._find_pool_for_pid(pid)
        if not pool:
            return

        pool.workers.pop(pid, None)
        exit_code = self._resolve_child_exit_code(status)

        if pool.spec.role == ServiceRole.ONESHOT_TASK:
            self._handle_oneshot_exit(pool, pid, exit_code)
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

    def _reload_single_pool(self, pool: ManagedPool) -> None:
        old_pids = set(pool.workers.keys())
        self.reloading_old_pids.update(old_pids)
        for _ in range(pool.target_count):
            self.spawn_worker(pool.name)
        for pid in old_pids:
            try:
                os.kill(pid, signal.SIGQUIT)
            except OSError:
                pass

    def _is_pool_eligible_for_reload(
        self, pool: ManagedPool, pool_name: Optional[str]
    ) -> bool:
        if pool_name is not None:
            return True
        return pool.spec.role == ServiceRole.STATELESS_POOL

    def _get_reload_targets(self, pool_name: Optional[str]) -> List[ManagedPool]:
        if pool_name and pool_name in self.pools:
            return [self.pools[pool_name]]
        return [
            p
            for p in self.pools.values()
            if self._is_pool_eligible_for_reload(p, pool_name)
        ]

    def reload(self, pool_name: Optional[str] = None) -> None:
        """Performs zero-downtime rolling restart of workers in designated or all stateless pools."""
        for pool in self._get_reload_targets(pool_name):
            self._reload_single_pool(pool)

    def _resolve_hung_pool_name(self, pool: Optional[ManagedPool]) -> str:
        if not pool:
            return "web"
        return "db" if pool.name in ("database", "db") else pool.name

    def _kill_hung_worker(self, pid: int) -> None:
        pool = self._find_pool_for_pid(pid)
        pool_name = self._resolve_hung_pool_name(pool)
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        self.watchdog.remove_worker(pid)
        if pool:
            pool.workers.pop(pid, None)
        if self.running:
            self.spawn_worker(pool_name)

    def check_hung_workers(self) -> None:
        """Checks for unresponsive workers and kills them with SIGKILL."""
        hung_pids = self.watchdog.get_hung_workers(self.config.request_timeout)
        for pid in hung_pids:
            self._kill_hung_worker(pid)

    def _signal_all_workers(self, workers: Dict[int, Any], sig: int) -> None:
        for pid in list(workers.keys()):
            try:
                os.kill(pid, sig)
            except OSError:
                pass

    def _drain_and_kill(
        self, workers: Dict[int, Any], initial_sig: int, timeout: float
    ) -> None:
        """Signals workers, waits for them to exit, and kills any remaining."""
        self._signal_all_workers(workers, initial_sig)

        start_t = time.time()
        while workers and (time.time() - start_t < timeout):
            self.handle_sigchld()
            time.sleep(0.1)

        self._signal_all_workers(workers, signal.SIGKILL)

    def _link_pool_dependency(
        self, name: str, dep: str, in_degree: Dict[str, int], adj: Dict[str, list[str]]
    ) -> None:
        dep_name = self._resolve_pool_name(dep) or dep
        if dep_name in self.pools:
            adj[dep_name].append(name)
            in_degree[name] += 1

    def _populate_pool_deps(
        self,
        name: str,
        pool: ManagedPool,
        in_degree: Dict[str, int],
        adj: Dict[str, list[str]],
    ) -> None:
        for dep in getattr(pool.spec, "dependencies", []) or []:
            self._link_pool_dependency(name, dep, in_degree, adj)

    def _build_dependency_graph(self) -> tuple[Dict[str, int], Dict[str, list[str]]]:
        """Builds in-degree mapping and adjacency list for pools."""
        in_degree: Dict[str, int] = {p: 0 for p in self.pools}
        adj: Dict[str, list[str]] = {p: [] for p in self.pools}

        for name, pool in self.pools.items():
            self._populate_pool_deps(name, pool, in_degree, adj)
        return in_degree, adj

    def _get_zero_in_degree_nodes(self, in_degree: Dict[str, int]) -> list[str]:
        zero_in = [n for n, deg in in_degree.items() if deg == 0]
        zero_in.sort(
            key=lambda n: (
                0 if self.pools[n].spec.role != ServiceRole.STATELESS_POOL else 1
            )
        )
        return zero_in

    def resolve_boot_order(self) -> list[str]:
        """Resolves pool/service boot order using Kahn's topological sort algorithm."""
        in_degree, adj = self._build_dependency_graph()
        zero_in = self._get_zero_in_degree_nodes(in_degree)
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

    def _shutdown_pool(self, pool_name: str) -> None:
        pool = self.pools.get(pool_name)
        if pool:
            sig = (
                signal.SIGQUIT
                if pool.spec.role == ServiceRole.STATELESS_POOL
                else signal.SIGTERM
            )
            self._drain_and_kill(pool.workers, sig, self.config.graceful_timeout)

    def shutdown(self) -> None:
        """Executes strictly ordered graceful shutdown sequence."""
        self.running = False
        try:
            shutdown_order = list(reversed(self.resolve_boot_order()))
        except Exception:
            shutdown_order = list(self.pools.keys())

        for pool_name in shutdown_order:
            self._shutdown_pool(pool_name)

        self._cleanup_resources()

    def _read_file_pid(self, path: Optional[str]) -> Optional[str]:
        if path and os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    val = f.read().strip()
                    if val:
                        return val
            except Exception:
                pass
        return None

    def _read_existing_arbiter_pid(self) -> str:
        """Helper to read PID from pid_file or lock_file for error diagnostics."""
        return (
            self._read_file_pid(self.config.pid_file)
            or self._read_file_pid(self.config.lock_file)
            or "unknown"
        )

    def _try_open_and_lock(self) -> TextIO:
        lock_fd = open(self.config.lock_file, "a+", encoding="utf-8")
        try:
            fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            lock_fd.seek(0)
            lock_fd.truncate()
            lock_fd.write(f"{self.pid}\n")
            lock_fd.flush()
            return lock_fd
        except Exception:
            lock_fd.close()
            raise

    def acquire_single_instance_lock(self) -> None:
        """Acquires a non-blocking exclusive flock on the lock file."""
        if not self.config.lock_file:
            return
        lock_dir = os.path.dirname(os.path.abspath(self.config.lock_file))
        if lock_dir:
            os.makedirs(lock_dir, exist_ok=True)

        try:
            self._lock_file_obj = self._try_open_and_lock()
        except (BlockingIOError, OSError) as exc:
            existing_pid = self._read_existing_arbiter_pid()
            raise RuntimeError(
                f"Supervisor arbiter is already running with PID {existing_pid}."
            ) from exc

    def release_single_instance_lock(self) -> None:
        """Releases and unlinks the singleton instance lock file."""
        if self._lock_file_obj:
            try:
                fcntl.flock(self._lock_file_obj.fileno(), fcntl.LOCK_UN)
                self._lock_file_obj.close()
            except Exception:
                pass
            self._lock_file_obj = None

        _safe_unlink(self.config.lock_file)

    def _cleanup_resources(self) -> None:
        """Cleans up control server, server socket, PID file, and instance lock."""
        if self.control_server:
            self.control_server.stop()
            self.control_server = None
        if self.server_socket:
            try:
                self.server_socket.close()
            except OSError:
                pass
            self.server_socket = None

        _safe_unlink(self.config.control_socket)
        _safe_unlink(self.config.pid_file)
        self.release_single_instance_lock()

    def _verify_pid_not_running(self, existing_pid: int) -> None:
        if existing_pid == self.pid:
            return
        try:
            os.kill(existing_pid, 0)
            raise RuntimeError(
                f"Supervisor arbiter is already running with PID {existing_pid}."
            )
        except (ProcessLookupError, ValueError):
            pass
        except PermissionError:
            raise RuntimeError(
                f"Supervisor arbiter is running with PID {existing_pid} (Permission Denied)."
            )

    def _check_existing_pid(self) -> None:
        """Checks if a valid running instance is already registered in the PID file."""
        pid_str = self._read_file_pid(self.config.pid_file)
        if pid_str and pid_str.isdigit():
            self._verify_pid_not_running(int(pid_str))

    def daemonize(self) -> None:
        """Detaches the supervisor from the controlling terminal using POSIX double-forking."""
        self._check_existing_pid()

        try:
            if os.fork() > 0:
                sys.exit(0)
        except OSError as e:
            raise RuntimeError(f"First fork failed: {e}") from e

        os.setsid()
        os.umask(0)

        try:
            if os.fork() > 0:
                sys.exit(0)
        except OSError as e:
            raise RuntimeError(f"Second fork failed: {e}") from e

        self.pid = os.getpid()
        self._redirect_standard_streams()
        self.acquire_single_instance_lock()

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

    def _do_redirect_streams(self) -> None:
        devnull = os.open(os.devnull, os.O_RDWR)
        self._safe_dup2(devnull, 0)
        out_fd = self._open_log_fd()
        self._safe_dup2(out_fd, 1)
        self._safe_dup2(out_fd, 2)
        if out_fd > 2:
            os.close(out_fd)
        if devnull > 2:
            os.close(devnull)

    def _redirect_standard_streams(self) -> None:
        """Redirects stdin to /dev/null and stdout/stderr to configured log_file."""
        for stream in (sys.stdout, sys.stderr):
            try:
                stream.flush()
            except Exception:
                pass

        try:
            self._do_redirect_streams()
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

    def _dispatch_scale_signals(self, sig: int) -> None:
        if hasattr(signal, "SIGTTIN") and sig == signal.SIGTTIN:
            self._handle_sigttin()
        elif hasattr(signal, "SIGTTOU") and sig == signal.SIGTTOU:
            self._handle_sigttou()

    def _dispatch_single_signal(self, sig: int) -> bool:
        """Dispatches an individual signal. Returns False if arbiter should stop."""
        if sig in (signal.SIGTERM, signal.SIGINT):
            self.running = False
            return False
        if sig == signal.SIGHUP:
            self.reload()
        elif sig == signal.SIGCHLD:
            self.handle_sigchld()
        else:
            self._dispatch_scale_signals(sig)
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

    def _run_event_loop(self) -> None:
        while self.running:
            self._handle_queued_signals()
            if not self.running:
                break
            self.handle_sigchld()
            self.check_hung_workers()
            time.sleep(0.5)

    def start(self) -> None:
        """Main lifecycle entrypoint starting the Supervisor cluster."""
        if not self._lock_file_obj:
            self.acquire_single_instance_lock()
        self.running = True
        self.init_signals()
        self.init_server_socket()
        self._write_pid_file()
        self._start_control_server()

        for pool_name in self.resolve_boot_order():
            self.adjust_pool(pool_name)

        try:
            self._run_event_loop()
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
