#!/usr/bin/env python3
"""
Database IPC Service & Unix Domain Socket Server.
Hosts the Vector DB & SQL protocol handler over a Unix domain socket,
providing decoupled, high-performance IPC for Web gateways and workers.
"""

from __future__ import annotations

import json
import logging
import os
import socket
import threading
from typing import Any, Dict, Optional

from supervisor.contracts import LifecycleHook

from .protocol import VectorDBProtocolHandler
from .storage import VectorStorage

logger = logging.getLogger(__name__)


class DatabaseService:
    """
    Standalone Database IPC Daemon listening on a Unix Domain Socket.
    """

    def __init__(
        self,
        socket_path: Optional[str] = None,
        workspace_dir: Optional[str] = None,
        storage_path: Optional[str] = None,
        dim: int = 128,
    ) -> None:
        self.workspace_dir = workspace_dir or os.path.abspath(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        )
        self.socket_path = socket_path or os.path.join(
            self.workspace_dir, "outputs", "supervisor", "db.sock"
        )
        self.storage_path = storage_path or os.path.join(
            self.workspace_dir, "outputs", "database", "papers.vdb"
        )
        self.storage = VectorStorage(self.storage_path, dim=dim)
        self.handler = VectorDBProtocolHandler(storage=self.storage)
        self.running = False
        self._server_sock: Optional[socket.socket] = None
        self._thread: Optional[threading.Thread] = None

    def _setup_socket(self) -> socket.socket:
        """Prepares and binds the Unix domain socket."""
        sock_dir = os.path.dirname(self.socket_path)
        if sock_dir and not os.path.exists(sock_dir):
            os.makedirs(sock_dir, exist_ok=True)
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass

        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(self.socket_path)
        sock.listen(64)
        sock.settimeout(1.0)
        return sock

    def start(self) -> None:
        """Starts the IPC server daemon thread."""
        if self.running:
            return
        self.running = True
        self._server_sock = self._setup_socket()
        self._thread = threading.Thread(
            target=self._listen_loop, name="DatabaseIPCService", daemon=True
        )
        self._thread.start()
        logger.info("DatabaseService started on %s", self.socket_path)

    def stop(self) -> None:
        """Stops the IPC server daemon and cleans up the socket."""
        self.running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        self._thread = None

        if self._server_sock:
            try:
                self._server_sock.close()
            except OSError:
                pass
            self._server_sock = None

        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass
        logger.info("DatabaseService stopped.")

    def _process_request_payload(self, raw: str) -> Dict[str, Any]:
        """Parses and executes request through protocol handler."""
        try:
            req = json.loads(raw.strip())
            if not isinstance(req, dict):
                return {"status": "error", "error": "Request must be a JSON object"}
            return self.handler.handle_request(req)
        except json.JSONDecodeError as err:
            return {"status": "error", "error": f"Invalid JSON: {err}"}
        except Exception as ex:
            return {"status": "error", "error": str(ex)}

    def _handle_client_connection(self, conn: socket.socket) -> None:
        """Handles single client connection until closed."""
        conn.settimeout(5.0)
        buf = b""
        try:
            while self.running:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    raw_str = line.decode("utf-8", errors="replace")
                    resp = self._process_request_payload(raw_str)
                    out_bytes = (json.dumps(resp, ensure_ascii=False) + "\n").encode(
                        "utf-8"
                    )
                    conn.sendall(out_bytes)
        except Exception:
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def _listen_loop(self) -> None:
        """Main listening loop accepting incoming client connections."""
        while self.running and self._server_sock:
            try:
                conn, _ = self._server_sock.accept()
                t = threading.Thread(
                    target=self._handle_client_connection,
                    args=(conn,),
                    daemon=True,
                )
                t.start()
            except socket.timeout:
                continue
            except OSError:
                break


class DatabaseLifecycleHook(LifecycleHook):
    """
    Lifecycle hook for running DatabaseService within a ManagedServiceWorker.
    """

    def __init__(
        self,
        socket_path: Optional[str] = None,
        workspace_dir: Optional[str] = None,
    ) -> None:
        self.service = DatabaseService(
            socket_path=socket_path, workspace_dir=workspace_dir
        )

    def setup(self) -> bool:
        """Initializes database and starts IPC server."""
        try:
            self.service.start()
            return True
        except Exception as e:
            logger.error("Failed to start DatabaseService: %s", e)
            return False

    def health_check(self) -> bool:
        """Verifies database engine responsiveness."""
        if not self.service.running:
            return False
        try:
            resp = self.service.handler.handle_request({"op": "ping", "params": {}})
            return resp.get("status") == "ok"
        except Exception:
            return False

    def on_flush(self) -> None:
        """Periodically syncs database buffer to disk if needed."""
        try:
            if hasattr(self.service.storage, "sync"):
                self.service.storage.sync()
        except Exception:
            pass

    def teardown(self) -> None:
        """Stops database IPC service and releases locks."""
        self.service.stop()
