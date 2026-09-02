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

from ..storage.storage import VectorStorage
from .protocol import VectorDBProtocolHandler

logger = logging.getLogger(__name__)


class DatabaseService:
    """
    Standalone Database IPC Daemon listening on a Unix Domain Socket.
    Supports single-node and multi-node clustered execution.
    """

    def __init__(
        self,
        socket_path: Optional[str] = None,
        workspace_dir: Optional[str] = None,
        storage_path: Optional[str] = None,
        dim: int = 128,
        node_id: int = 0,
        cluster_size: int = 3,
    ) -> None:
        self.workspace_dir = workspace_dir or os.path.abspath(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        )
        self.node_id = int(node_id)
        self.cluster_size = int(cluster_size)

        if socket_path:
            self.socket_path = socket_path
        else:
            self.socket_path = os.path.join(
                self.workspace_dir, "outputs", "supervisor", f"db_{self.node_id}.sock"
            )

        self.storage_path = storage_path or os.path.join(
            self.workspace_dir, "outputs", "database", "papers.vdb"
        )
        self.storage = VectorStorage(self.storage_path, dim=dim)
        self.handler = VectorDBProtocolHandler(storage=self.storage)
        self.running = False
        self.requests_handled = 0
        self._server_sock: Optional[socket.socket] = None
        self._thread: Optional[threading.Thread] = None

    def _setup_canonical_sock(self, sock_dir: str) -> None:
        canonical_sock = os.path.join(sock_dir, "db.sock")
        if canonical_sock == self.socket_path:
            return
        try:
            if os.path.exists(canonical_sock):
                os.unlink(canonical_sock)
            os.symlink(os.path.basename(self.socket_path), canonical_sock)
        except OSError:
            pass

    def _clean_existing_socket(self) -> None:
        sock_dir = os.path.dirname(self.socket_path)
        if sock_dir and not os.path.exists(sock_dir):
            os.makedirs(sock_dir, exist_ok=True)
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass

    def _setup_socket(self) -> socket.socket:
        """Prepares and binds the Unix domain socket safely."""
        self._clean_existing_socket()
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(self.socket_path)
        sock.listen(64)
        sock.settimeout(1.0)
        if self.node_id == 0:
            self._setup_canonical_sock(os.path.dirname(self.socket_path))
        return sock

    def start(self) -> None:
        """Starts the IPC server daemon thread."""
        if self.running:
            return
        self.running = True
        self._server_sock = self._setup_socket()
        self._thread = threading.Thread(
            target=self._listen_loop,
            name=f"DatabaseIPCService-Node{self.node_id}",
            daemon=True,
        )
        self._thread.start()
        logger.info(
            "DatabaseService (Node %d/%d) started on %s",
            self.node_id,
            self.cluster_size,
            self.socket_path,
        )

    def _close_server_sock(self) -> None:
        if self._server_sock:
            try:
                self._server_sock.close()
            except OSError:
                pass
            self._server_sock = None

    def _teardown_canonical_sock(self) -> None:
        canonical_sock = os.path.join(os.path.dirname(self.socket_path), "db.sock")
        if os.path.islink(canonical_sock):
            try:
                os.unlink(canonical_sock)
            except OSError:
                pass

    def _unlink_sock_file(self) -> None:
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass

    def stop(self) -> None:
        """Stops the IPC server daemon and cleans up the socket."""
        self.running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        self._thread = None
        self._close_server_sock()
        self._unlink_sock_file()
        if self.node_id == 0:
            self._teardown_canonical_sock()
        logger.info("DatabaseService (Node %d) stopped.", self.node_id)

    def _write_database_log(self, record: Dict[str, Any]) -> None:
        log_dir = os.path.join(self.workspace_dir, "outputs", "logs")
        os.makedirs(log_dir, exist_ok=True)
        log_path = os.path.join(log_dir, "database.jsonl")
        try:
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
        except Exception:
            pass

    def _log_sql_request(self, req: Dict[str, Any], tid: str) -> None:
        from datetime import datetime, timezone

        from observability.masking import mask_text

        if req.get("op") == "execute_sql":
            raw_sql = str(req.get("params", {}).get("sql", "")).strip()
            masked_sql = mask_text(raw_sql)
            record = {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "level": "INFO",
                "service": "database.service",
                "trace_id": tid,
                "node_id": self.node_id,
                "event": {
                    "category": "database",
                    "action": "execute_sql",
                    "outcome": "success",
                },
                "db": {"sql": masked_sql, "node_id": self.node_id},
                "message": f"Executing SQL on Node {self.node_id}: {masked_sql}",
            }
            self._write_database_log(record)

    def _process_request_payload(self, raw: str) -> Dict[str, Any]:
        """Parses and executes request through protocol handler."""
        try:
            req = json.loads(raw.strip())
            if not isinstance(req, dict):
                return {"status": "error", "error": "Request must be a JSON object"}
            tid = req.get("trace_id", "")
            self._log_sql_request(req, tid)
            return self.handler.handle_request(req)
        except json.JSONDecodeError as err:
            return {"status": "error", "error": f"Invalid JSON: {err}"}
        except Exception as ex:
            return {"status": "error", "error": str(ex)}

    def _handle_line(self, conn: socket.socket, line: str) -> None:
        from observability.propagation import (
            clear_current_trace_context,
            set_current_trace_context,
        )

        try:
            req_data = json.loads(line.strip())
            if isinstance(req_data, dict) and req_data.get("trace_id"):
                set_current_trace_context(req_data["trace_id"], req_data.get("span_id"))
        except Exception:
            pass

        try:
            resp_dict = self._process_request_payload(line)
            self.requests_handled += 1
            conn.sendall((json.dumps(resp_dict) + "\n").encode("utf-8"))
        finally:
            clear_current_trace_context()

    def _process_buffered_lines(self, conn: socket.socket, buffer: str) -> str:
        while "\n" in buffer:
            line, buffer = buffer.split("\n", 1)
            if line.strip():
                self._handle_line(conn, line)
        return buffer

    def _handle_client_connection(self, conn: socket.socket) -> None:
        """Handles a single client IPC conversation."""
        try:
            conn.settimeout(10.0)
            buffer = ""
            while self.running:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                buffer += chunk.decode("utf-8", errors="replace")
                buffer = self._process_buffered_lines(conn, buffer)
        except (socket.timeout, OSError) as e:
            logger.debug("Database IPC client connection closed: %s", e)
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
    Supports multi-node cluster binding via worker_id introspection.
    """

    def __init__(
        self,
        socket_path: Optional[str] = None,
        workspace_dir: Optional[str] = None,
        node_id: int = 0,
        cluster_size: int = 3,
    ) -> None:
        self.socket_path = socket_path
        self.workspace_dir = workspace_dir
        self.node_id = node_id
        self.cluster_size = cluster_size
        self.service: Optional[DatabaseService] = None

    def bind_worker(self, worker_id: str) -> None:
        """Extracts node_id from worker_id (e.g. 'database_0', 'database_1', 'database_2')."""
        import re

        match = re.search(r"(\d+)$", str(worker_id))
        if match:
            self.node_id = int(match.group(1)) % max(1, self.cluster_size)
        else:
            self.node_id = 0

    def setup(self) -> bool:
        """Initializes database and starts IPC server on node-specific socket."""
        try:
            if self.service is None:
                self.service = DatabaseService(
                    socket_path=self.socket_path,
                    workspace_dir=self.workspace_dir,
                    node_id=self.node_id,
                    cluster_size=self.cluster_size,
                )
            self.service.start()
            print(
                f"⚡ [DatabaseService Worker Node {self.node_id}] "
                f"Database IPC daemon online on {self.service.socket_path}",
                flush=True,
            )
            return True
        except Exception as e:
            logger.error(
                "Failed to start DatabaseService (Node %d): %s", self.node_id, e
            )
            return False

    def health_check(self) -> bool:
        """Verifies database engine responsiveness."""
        if not self.service or not self.service.running:
            return False
        try:
            resp = self.service.handler.handle_request({"op": "ping", "params": {}})
            return resp.get("status") == "ok"
        except Exception:
            return False

    def on_flush(self) -> None:
        """Periodically syncs database buffer to disk if needed."""
        try:
            if self.service and hasattr(self.service.storage, "sync"):
                self.service.storage.sync()
        except Exception:
            pass

    def teardown(self) -> None:
        """Stops database IPC service and releases locks."""
        if self.service:
            self.service.stop()

    def get_metrics(self) -> Dict[str, Any]:
        """Returns runtime performance metrics from DatabaseService."""
        reqs = getattr(self.service, "requests_handled", 0) if self.service else 0
        return {"requests_handled": reqs}
