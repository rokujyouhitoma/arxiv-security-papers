#!/usr/bin/env python3
"""
Loosely-Coupled Database & Vector DB Protocol Client.
Provides high-level typed API that communicates with DatabaseService over
Unix domain socket with zero-overhead, and provides seamless, lazy in-process
fallback (Embedded Mode) when running standalone without supervisor.
"""

from __future__ import annotations

import json
import logging
import os
import socket
from typing import Any, Dict, List, Optional, Sequence, Set

from .protocol import VectorDBProtocolError, VectorDBProtocolHandler

logger = logging.getLogger(__name__)


class DatabaseClient:
    """
    Client for interacting with DatabaseService over Unix Domain Socket or In-Process.
    Decouples callers from internal storage layout, mmap operations, and index internals.
    """

    def __init__(
        self,
        socket_path: Optional[str] = None,
        workspace_dir: Optional[str] = None,
        timeout: float = 5.0,
        handler: Optional[VectorDBProtocolHandler] = None,
    ) -> None:
        self.workspace_dir = workspace_dir or os.path.abspath(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        )
        self.socket_path = socket_path or os.path.join(
            self.workspace_dir, "outputs", "supervisor", "db.sock"
        )
        self.timeout = timeout
        self._custom_handler = handler
        self._fallback_handler: Optional[VectorDBProtocolHandler] = None

    @property
    def fallback_handler(self) -> VectorDBProtocolHandler:
        """Lazily creates an in-process VectorDBProtocolHandler if IPC is unavailable."""
        if self._custom_handler is not None:
            return self._custom_handler
        if self._fallback_handler is None:
            logger.info("Initializing fallback in-process Database Storage & Handler")
            from ..storage.storage import VectorStorage

            storage_path = os.path.join(
                self.workspace_dir, "outputs", "database", "papers.vdb"
            )
            storage = VectorStorage(storage_path, dim=128)
            self._fallback_handler = VectorDBProtocolHandler(storage=storage)
        return self._fallback_handler

    def close(self) -> None:
        """Releases client resources and closes fallback storage."""
        if self._fallback_handler is not None and hasattr(
            self._fallback_handler.storage, "close"
        ):
            self._fallback_handler.storage.close()
        self._fallback_handler = None

    def _get_candidate_sockets(self) -> List[str]:
        """Returns candidate socket paths in priority order (specified socket, canonical db.sock, then node sockets)."""
        sock_dir = os.path.dirname(self.socket_path)
        all_candidates = [
            self.socket_path,
            os.path.join(sock_dir, "db.sock"),
            *(os.path.join(sock_dir, f"db_{i}.sock") for i in range(3)),
        ]
        seen: Set[str] = set()
        candidates: List[str] = []
        for s in all_candidates:
            if s not in seen and os.path.exists(s):
                seen.add(s)
                candidates.append(s)
        return candidates

    def is_socket_available(self) -> bool:
        """Checks if any database cluster socket exists and is responsive."""
        candidates = self._get_candidate_sockets()
        if not candidates:
            return False
        try:
            return self.ping()
        except Exception:
            return False

    def _recv_response_line(self, sock: socket.socket) -> bytes:
        raw_data = b""
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            raw_data += chunk
            if b"\n" in raw_data:
                break
        if not raw_data:
            raise VectorDBProtocolError("Empty response from database daemon")
        return raw_data

    def _send_socket_request(
        self, target_sock: str, req: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Sends request to a specific Unix socket and returns parsed response."""
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        try:
            sock.connect(target_sock)
            payload = (json.dumps(req, ensure_ascii=False) + "\n").encode("utf-8")
            sock.sendall(payload)
            raw_data = self._recv_response_line(sock)
            parsed = json.loads(raw_data.decode("utf-8"))
            if isinstance(parsed, dict):
                return parsed
            return {"status": "error", "error": "Invalid response format"}
        finally:
            try:
                sock.close()
            except OSError:
                pass

    def send_request(self, req: Dict[str, Any]) -> Dict[str, Any]:
        """Sends a JSON request to the DatabaseService over Unix domain socket with cluster failover."""
        if self._custom_handler is not None:
            return self._custom_handler.handle_request(req)

        candidate_sockets = self._get_candidate_sockets()
        if not candidate_sockets:
            return self.fallback_handler.handle_request(req)

        last_err: Optional[Exception] = None
        for target_sock in candidate_sockets:
            try:
                return self._send_socket_request(target_sock, req)
            except (socket.timeout, OSError, json.JSONDecodeError) as ex:
                last_err = ex
                continue

        logger.warning(
            "All candidate database sockets %s failed (%s). Falling back to in-process.",
            candidate_sockets,
            last_err,
        )
        return self.fallback_handler.handle_request(req)

    def ping(self) -> bool:
        """Sends ping request to verify DB engine responsiveness."""
        resp = self.send_request({"op": "ping", "params": {}})
        return resp.get("status") == "ok"

    def get_info(self) -> Dict[str, Any]:
        """Retrieves vector DB metadata, dimensions, counts, and health status."""
        resp = self.send_request({"op": "info", "params": {}})
        if resp.get("status") != "ok":
            raise VectorDBProtocolError(resp.get("error", "Failed to retrieve info"))
        res: Dict[str, Any] = resp.get("result", {})
        return res

    def insert(
        self, vector: Sequence[float], metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        """Inserts a single vector and metadata through DB protocol."""
        req = {
            "op": "insert",
            "params": {"vector": list(vector), "metadata": metadata or {}},
        }
        resp = self.send_request(req)
        if resp.get("status") != "ok":
            raise VectorDBProtocolError(resp.get("error", "Insert operation failed"))
        return str(resp.get("result", {}).get("id", ""))

    def bulk_write(
        self,
        vectors: Sequence[Sequence[float]],
        metadata: List[Dict[str, Any]],
    ) -> int:
        """Writes batch vectors and builds HNSW index through DB protocol."""
        req = {
            "op": "bulk_write",
            "params": {
                "vectors": [list(v) for v in vectors],
                "metadata": metadata,
            },
        }
        resp = self.send_request(req)
        if resp.get("status") != "ok":
            raise VectorDBProtocolError(resp.get("error", "Bulk write failed"))
        return int(resp.get("result", {}).get("count", 0))

    def search_knn(
        self,
        vector: Optional[Sequence[float]] = None,
        text: Optional[str] = None,
        top_k: int = 10,
        ef_search: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        """
        Executes Top-K Approximate Nearest Neighbor search through DB protocol.
        Accepts either raw vector or text query for automatic embedding.
        """
        params: Dict[str, Any] = {"top_k": top_k}
        if vector is not None:
            params["vector"] = list(vector)
        if text is not None:
            params["text"] = text
        if ef_search is not None:
            params["ef_search"] = ef_search

        req = {"op": "search_knn", "params": params}
        resp = self.send_request(req)
        if resp.get("status") != "ok":
            raise VectorDBProtocolError(resp.get("error", "Search KNN failed"))

        matches: List[Dict[str, Any]] = resp.get("result", {}).get("matches", [])
        return matches

    def get_by_id(self, doc_id: str) -> Optional[Dict[str, Any]]:
        """Retrieves vector and metadata for a specific document ID."""
        req = {"op": "get_by_id", "params": {"id": doc_id}}
        resp = self.send_request(req)
        if resp.get("status") != "ok":
            raise VectorDBProtocolError(
                resp.get("error", f"Get by ID failed for '{doc_id}'")
            )

        result: Dict[str, Any] = resp.get("result", {})
        if not result.get("found"):
            return None
        return result

    def execute_sql(self, sql: str, role: str = "admin") -> Dict[str, Any]:
        """
        Executes a SQL query (DDL, DQL, DML, DCL, TCL) through DB protocol.
        """
        req = {"op": "execute_sql", "params": {"sql": sql, "role": role}}
        return self.send_request(req)


# Backward Compatibility Alias
VectorDBClient = DatabaseClient
