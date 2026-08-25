#!/usr/bin/env python3
"""
Dedicated High-Performance Search IPC Service.
Hosts the VectorEngine in a dedicated background worker process and serves search queries,
metadata retrieval, and graph exploration over a Unix domain socket IPC channel.
"""

from __future__ import annotations

import atexit
import json
import logging
import os
import socket
import threading
from typing import Any, Dict, List, Optional

from ..vector_engine import VectorEngine

logger = logging.getLogger(__name__)


class SearchService:
    """
    Standalone Search Engine Service serving query and metadata requests via Unix Domain Socket.
    """

    def __init__(
        self,
        socket_path: str,
        workspace_dir: Optional[str] = None,
        vector_engine: Optional[VectorEngine] = None,
    ) -> None:
        self.socket_path = socket_path
        self.workspace_dir = workspace_dir or os.path.abspath(
            os.path.dirname(
                os.path.dirname(
                    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
                )
            )
        )
        self._vector_engine = vector_engine
        self._server_sock: Optional[socket.socket] = None
        self._thread: Optional[threading.Thread] = None
        self._running = False

    @property
    def vector_engine(self) -> VectorEngine:
        """Lazily initializes and loads VectorEngine on first demand."""
        if self._vector_engine is None:
            self._vector_engine = VectorEngine(
                workspace_dir=self.workspace_dir, lazy=False
            )
        return self._vector_engine

    def _handle_search(self, req: Dict[str, Any]) -> Dict[str, Any]:
        query = req.get("query", "").strip()
        top_k = int(req.get("top_k", 20))
        category = req.get("category")
        mode = req.get("mode", "hybrid")

        if not query:
            return {
                "status": "success",
                "query": "",
                "total": 0,
                "results": [],
                "profile": {},
            }

        if mode == "vector":
            results = self.vector_engine.search_vector_ann(query=query, top_k=top_k)
            profile: Dict[str, Any] = {"mode": "vector", "total_ms": 1.0}
        elif mode == "rrf":
            results = self.vector_engine.search_rrf_hybrid(
                query=query, top_k=top_k, category=category
            )
            profile = {"mode": "rrf", "total_ms": 1.0}
        else:
            results, profile = self.vector_engine.search_with_profile(
                query=query, top_k=top_k, category=category
            )

        return {
            "status": "success",
            "query": query,
            "category": category,
            "mode": mode,
            "total": len(results),
            "profile": profile,
            "results": results,
        }

    def _handle_get_paper(self, req: Dict[str, Any]) -> Dict[str, Any]:
        clean_id = str(req.get("id", "")).strip()
        if not clean_id:
            return {"status": "error", "error": "Missing paper id"}

        doc = self.vector_engine.documents_by_id.get(clean_id)
        if not doc:
            for d in self.vector_engine.documents:
                if d.get("id") == clean_id:
                    doc = d
                    break
        if not doc:
            return {
                "status": "error",
                "error": f"Paper '{clean_id}' not found",
            }
        return {"status": "success", "paper": doc}

    def _handle_get_related(self, req: Dict[str, Any]) -> Dict[str, Any]:
        clean_id = str(req.get("id", "")).strip()
        if not clean_id:
            return {"status": "error", "error": "Missing paper id"}

        doc = self.vector_engine.documents_by_id.get(clean_id)
        if not doc:
            return {
                "status": "error",
                "error": f"Paper '{clean_id}' not found",
            }

        related = self.vector_engine.proximity_graph.get_neighbors(clean_id)
        mermaid = f"graph TD;\n  root[{clean_id}]"
        for r in related:
            r_id = r.get("id", "paper")
            mermaid += f"\n  root --> node_{r_id}[{r_id}]"

        return {
            "status": "success",
            "paper_id": clean_id,
            "related_papers": related,
            "mermaid_graph": mermaid,
        }

    def _handle_get_stats(self) -> Dict[str, Any]:
        papers = self.vector_engine.documents
        cats: Dict[str, int] = {}
        for p in papers:
            for c in p.get("tags", []):
                cats[str(c)] = cats.get(str(c), 0) + 1

        categories_list: List[Dict[str, Any]] = [
            {"name": k, "count": v} for k, v in cats.items()
        ]
        categories_list.sort(key=lambda x: int(x["count"]), reverse=True)

        return {
            "status": "success",
            "total_papers": len(papers),
            "vector_index_size": (
                len(self.vector_engine.vector_storage.metadata)
                if os.path.exists(self.vector_engine.vector_storage_path)
                else len(papers)
            ),
            "categories": categories_list,
        }

    def handle_command(self, req: Dict[str, Any]) -> Dict[str, Any]:
        """Dispatches JSON IPC commands to the underlying VectorEngine."""
        cmd = req.get("cmd", "")
        if cmd == "ping":
            return {"status": "ok", "message": "pong"}
        if cmd == "search":
            return self._handle_search(req)
        if cmd == "get_paper":
            return self._handle_get_paper(req)
        if cmd == "get_related":
            return self._handle_get_related(req)
        if cmd == "get_stats":
            return self._handle_get_stats()
        return {"status": "error", "error": f"Unknown command: '{cmd}'"}

    def start(self) -> None:
        """Binds to the Unix socket and starts the listener thread."""
        os.makedirs(os.path.dirname(os.path.abspath(self.socket_path)), exist_ok=True)
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass

        self._server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._server_sock.bind(self.socket_path)
        self._server_sock.listen(32)
        self._server_sock.settimeout(0.5)
        self._running = True

        atexit.register(self._atexit_cleanup)

        # Pre-load VectorEngine during service start
        _ = self.vector_engine

        self._thread = threading.Thread(target=self._listen_loop, daemon=True)
        self._thread.start()
        logger.info("SearchService IPC listening at %s", self.socket_path)

    def _listen_loop(self) -> None:
        while self._running and self._server_sock:
            try:
                client_sock, _ = self._server_sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break

            client_thread = threading.Thread(
                target=self._handle_client, args=(client_sock,), daemon=True
            )
            client_thread.start()

    def _handle_client(self, client_sock: socket.socket) -> None:
        client_sock.settimeout(5.0)
        try:
            raw_data = b""
            while True:
                chunk = client_sock.recv(65536)
                if not chunk:
                    break
                raw_data += chunk
                if b"\n" in raw_data:
                    break
            if not raw_data:
                return

            req = json.loads(raw_data.decode("utf-8").strip())
            resp = self.handle_command(req)
            resp_bytes = (json.dumps(resp, ensure_ascii=False) + "\n").encode("utf-8")
            client_sock.sendall(resp_bytes)
        except Exception as e:
            err_resp = {"status": "error", "error": str(e)}
            try:
                client_sock.sendall((json.dumps(err_resp) + "\n").encode("utf-8"))
            except OSError:
                pass
        finally:
            try:
                client_sock.close()
            except OSError:
                pass

    def close_in_child(self) -> None:
        """Closes server socket in child process without unlinking the socket file."""
        self._running = False
        if self._server_sock:
            try:
                self._server_sock.close()
            except OSError:
                pass
            self._server_sock = None

    def _atexit_cleanup(self) -> None:
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass

    def stop(self) -> None:
        """Stops the listener thread and removes the socket file."""
        self._running = False
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
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1.0)
