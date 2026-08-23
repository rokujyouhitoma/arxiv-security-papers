#!/usr/bin/env python3
"""
Arbiter (Master Process) for Gunicorn-style Process Supervisor.
Pre-binds listening sockets, orchestrates stateless Web worker pools and stateful
Database subsystems, traps POSIX signals, enforces heartbeat watchdogs, and hosts
the Unix domain socket IPC control server.
"""

from __future__ import annotations

import importlib
import os
import signal
import socket
import sys
import time
from typing import Any, Callable, Dict, List, Optional, Set, cast

from .config import SupervisorConfig
from .control import ControlServer
from .heartbeat import HeartbeatWatchdog
from .workers import WORKER_CLASSES, BaseWorker, DatabaseWorker, SyncWorker


class Arbiter:
    """
    Master process orchestrator managing worker processes and life cycles.
    """

    def __init__(self, config: Optional[SupervisorConfig] = None) -> None:
        self.config = config or SupervisorConfig()
        self.watchdog = HeartbeatWatchdog(timeout=self.config.timeout)
        self.server_socket: Optional[socket.socket] = None
        self.control_server: Optional[ControlServer] = None
        self.wsgi_app: Optional[Callable[..., Any]] = None

        self.pid = os.getpid()
        self.running = False
        self.boot_time = time.time()

        # Worker Tracking
        # pid -> worker_instance (or process handle)
        self.web_workers: Dict[int, BaseWorker] = {}
        self.db_workers: Dict[int, DatabaseWorker] = {}
        self.reloading_old_pids: Set[int] = set()

        self._signal_queue: List[int] = []

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

    def handle_control_command(self, req: Dict[str, Any]) -> Dict[str, Any]:
        """Dispatches administrative commands received from the Unix control socket."""
        cmd = req.get("cmd", "")
        if cmd == "ping":
            return {"status": "ok", "message": "pong", "timestamp": time.time()}

        if cmd == "status":
            return {
                "status": "ok",
                "arbiter_pid": self.pid,
                "uptime": round(time.time() - self.boot_time, 2),
                "target_workers": self.config.workers,
                "active_web_workers": len(self.web_workers),
                "active_db_workers": len(self.db_workers),
                "workers": self.watchdog.get_all_statuses(),
                "bind": f"{self.config.bind_host}:{self.config.bind_port}",
                "worker_class": self.config.worker_class,
            }

        if cmd == "scale":
            new_count = int(req.get("workers", self.config.workers))
            if new_count < 1:
                return {"status": "error", "error": "Worker count must be >= 1"}
            self.config.workers = new_count
            self.adjust_worker_pool()
            return {"status": "ok", "target_workers": self.config.workers}

        if cmd == "reload":
            self.reload()
            return {"status": "ok", "message": "Rolling reload triggered"}

        if cmd == "stop":
            self.running = False
            return {"status": "ok", "message": "Shutdown sequence initiated"}

        return {"status": "error", "error": f"Unknown command: '{cmd}'"}

    def spawn_worker(self, worker_type: str = "web") -> Optional[int]:
        """Forks a new child worker (Web or Database)."""
        worker_cls = WORKER_CLASSES.get(self.config.worker_class, SyncWorker)
        worker_id = f"{worker_type}_{int(time.time() * 1000) % 100000}"

        try:
            pid = os.fork()
        except AttributeError:
            # Fork not supported (e.g. mock / non-posix environment)
            return None

        if pid == 0:
            # --- CHILD PROCESS ---
            self.init_child_process()
            app = self.load_wsgi_app()

            if worker_type == "db":
                db_worker = DatabaseWorker(
                    worker_id=worker_id,
                    config=self.config,
                )
                db_worker.run()
            else:
                web_worker = worker_cls(
                    worker_id=worker_id,
                    config=self.config,
                    server_socket=self.server_socket,
                    app_target=app,
                )
                web_worker.run()
            sys.exit(0)
        else:
            # --- PARENT (ARBITER) PROCESS ---
            if worker_type == "db":
                db_inst = DatabaseWorker(worker_id=worker_id, config=self.config)
                db_inst.pid = pid
                self.db_workers[pid] = db_inst
                self.watchdog.register_worker(pid, "database")
            else:
                web_inst = worker_cls(
                    worker_id=worker_id,
                    config=self.config,
                    server_socket=self.server_socket,
                    app_target=self.wsgi_app,
                )
                web_inst.pid = pid
                self.web_workers[pid] = web_inst
                self.watchdog.register_worker(pid, self.config.worker_class)

            return pid

    def init_child_process(self) -> None:
        """Resets signal handlers and closes administrative control socket in child."""
        if self.control_server:
            self.control_server.close_in_child()
        # Reset signal handlers in child
        signal.signal(signal.SIGCHLD, signal.SIG_DFL)

    def adjust_worker_pool(self) -> None:
        """Maintains target web worker count (scaling up or down)."""
        current_active = len(self.web_workers)
        target = self.config.workers

        if current_active < target:
            needed = target - current_active
            for _ in range(needed):
                self.spawn_worker("web")
        elif current_active > target:
            excess = current_active - target
            pids = list(self.web_workers.keys())[:excess]
            for pid in pids:
                try:
                    os.kill(pid, signal.SIGQUIT)
                except OSError:
                    pass
                self.web_workers.pop(pid, None)
                self.watchdog.remove_worker(pid)

    def handle_sigchld(self) -> None:
        """Reaps terminated children and respawns if killed unexpectedly."""
        while True:
            try:
                pid, status = os.waitpid(-1, os.WNOHANG)
                if pid <= 0:
                    break
            except OSError:
                break

            self.watchdog.remove_worker(pid)
            if pid in self.web_workers:
                self.web_workers.pop(pid, None)
                if self.running and pid not in self.reloading_old_pids:
                    # Unexpected termination: respawn immediately
                    self.spawn_worker("web")
                self.reloading_old_pids.discard(pid)
            elif pid in self.db_workers:
                self.db_workers.pop(pid, None)
                if self.running:
                    self.spawn_worker("db")

    def reload(self) -> None:
        """Performs zero-downtime rolling restart of all web workers."""
        old_pids = set(self.web_workers.keys())
        self.reloading_old_pids.update(old_pids)

        # Spawn new workers
        for _ in range(self.config.workers):
            self.spawn_worker("web")

        # Graceful drain old workers
        for pid in old_pids:
            try:
                os.kill(pid, signal.SIGQUIT)
            except OSError:
                pass

    def check_hung_workers(self) -> None:
        """Checks for unresponsive workers and kills them with SIGKILL."""
        hung_pids = self.watchdog.get_hung_workers(self.config.timeout)
        for pid in hung_pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
            self.watchdog.remove_worker(pid)
            self.web_workers.pop(pid, None)
            self.db_workers.pop(pid, None)
            if self.running:
                self.spawn_worker("web")

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

    def shutdown(self) -> None:
        """
        Executes strictly ordered graceful shutdown sequence:
        1. Stop accepting new connections (SIGQUIT to Web Workers).
        2. Wait for web workers to drain.
        3. Flush DB buffers and terminate Database Worker (SIGTERM).
        4. Close listening sockets and clean up control server.
        """
        self.running = False
        self._drain_and_kill(
            self.web_workers, signal.SIGQUIT, self.config.graceful_timeout
        )
        self._drain_and_kill(
            self.db_workers, signal.SIGTERM, self.config.db_sync_timeout
        )
        self._cleanup_resources()

    def _write_pid_file(self) -> None:
        """Writes PID file if configured."""
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

    def _handle_queued_signals(self) -> None:
        """Processes queued OS signals."""
        while self._signal_queue:
            sig = self._signal_queue.pop(0)
            if sig in (signal.SIGTERM, signal.SIGINT):
                self.running = False
                break
            if sig == signal.SIGHUP:
                self.reload()
            elif hasattr(signal, "SIGTTIN") and sig == signal.SIGTTIN:
                self.config.workers += 1
                self.adjust_worker_pool()
            elif hasattr(signal, "SIGTTOU") and sig == signal.SIGTTOU:
                if self.config.workers > 1:
                    self.config.workers -= 1
                    self.adjust_worker_pool()
            elif sig == signal.SIGCHLD:
                self.handle_sigchld()

    def start(self) -> None:
        """Main lifecycle entrypoint starting the Supervisor cluster."""
        self.running = True
        self.init_signals()
        self.init_server_socket()
        self.load_wsgi_app()
        self._write_pid_file()
        self._start_control_server()

        # Phase 1: Database Startup (Ordered Lifecycle)
        if self.config.manage_database:
            for _ in range(self.config.db_worker_count):
                self.spawn_worker("db")

        # Phase 2: Web Worker Pre-fork
        self.adjust_worker_pool()

        # Phase 3: Master Event Loop
        try:
            while self.running:
                self._handle_queued_signals()
                if not self.running:
                    break
                self.handle_sigchld()
                self.check_hung_workers()
                time.sleep(0.5)
        finally:
            self.shutdown()


ProcessArbiter = Arbiter

__all__ = ["Arbiter", "ProcessArbiter"]
