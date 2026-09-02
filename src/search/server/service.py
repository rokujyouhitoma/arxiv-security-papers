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

from supervisor.contracts import LifecycleHook

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
        self.requests_handled = 0

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
        offset = int(req.get("offset", 0))
        category = req.get("category")
        mode = req.get("mode", "hybrid")

        if not query:
            return {
                "status": "success",
                "query": "",
                "total": 0,
                "total_hits": 0,
                "offset": offset,
                "limit": top_k,
                "has_more": False,
                "results": [],
                "profile": {},
            }

        if mode == "vector":
            all_vec = self.vector_engine.search_vector_ann(
                query=query, top_k=top_k + offset
            )
            results = all_vec[offset : offset + top_k]
            total_hits = len(all_vec)
            profile: Dict[str, Any] = {
                "mode": "vector",
                "total_hits": total_hits,
                "offset": offset,
                "limit": top_k,
                "has_more": (offset + len(results) < total_hits),
                "total_ms": 1.0,
            }
        elif mode == "rrf":
            all_rrf = self.vector_engine.search_rrf_hybrid(
                query=query, top_k=top_k + offset, category=category
            )
            results = all_rrf[offset : offset + top_k]
            total_hits = len(all_rrf)
            profile = {
                "mode": "rrf",
                "total_hits": total_hits,
                "offset": offset,
                "limit": top_k,
                "has_more": (offset + len(results) < total_hits),
                "total_ms": 1.0,
            }
        else:
            results, profile = self.vector_engine.search_with_profile(
                query=query, top_k=top_k, category=category, offset=offset
            )
            total_hits = int(profile.get("total_hits", len(results)))

        return {
            "status": "success",
            "query": query,
            "category": category,
            "mode": mode,
            "total": len(results),
            "total_hits": total_hits,
            "offset": offset,
            "limit": top_k,
            "has_more": bool(
                profile.get("has_more", (offset + len(results) < total_hits))
            ),
            "profile": profile,
            "results": results,
        }

    def _find_document_in_engine(self, doc_id: str) -> Optional[Dict[str, Any]]:
        doc = self.vector_engine.documents_by_id.get(doc_id)
        if doc:
            return doc
        for d in self.vector_engine.documents:
            if d.get("id") == doc_id:
                return d
        return None

    def _find_paper_in_engine(self, clean_id: str) -> Optional[Dict[str, Any]]:
        return self._find_document_in_engine(clean_id)

    def _handle_get_document(self, req: Dict[str, Any]) -> Dict[str, Any]:
        doc_id = str(req.get("id", "")).strip()
        if not doc_id:
            return {"status": "error", "error": "Missing document id"}

        doc = self._find_document_in_engine(doc_id)
        if not doc:
            return {
                "status": "error",
                "error": f"Document '{doc_id}' not found",
            }
        return {"status": "success", "document": doc, "paper": doc}

    def _handle_get_paper(self, req: Dict[str, Any]) -> Dict[str, Any]:
        return self._handle_get_document(req)

    def _handle_get_related(self, req: Dict[str, Any]) -> Dict[str, Any]:
        doc_id = str(req.get("id", "")).strip()
        if not doc_id:
            return {"status": "error", "error": "Missing document id"}

        doc = self.vector_engine.documents_by_id.get(doc_id)
        if not doc:
            return {
                "status": "error",
                "error": f"Document '{doc_id}' not found",
            }

        related = self.vector_engine.proximity_graph.get_neighbors(doc_id)
        mermaid = f"graph TD;\n  root[{doc_id}]"
        for r in related:
            r_id = r.get("id", "entity")
            mermaid += f"\n  root --> node_{r_id}[{r_id}]"

        return {
            "status": "success",
            "document_id": doc_id,
            "paper_id": doc_id,
            "related_documents": related,
            "related_papers": related,
            "mermaid_graph": mermaid,
        }

    def _handle_get_stats(self) -> Dict[str, Any]:
        docs = self.vector_engine.documents
        cats: Dict[str, int] = {}
        for d in docs:
            for c in d.get("tags", []):
                cats[str(c)] = cats.get(str(c), 0) + 1

        categories_list: List[Dict[str, Any]] = [
            {"name": k, "count": v} for k, v in cats.items()
        ]
        categories_list.sort(key=lambda x: int(x["count"]), reverse=True)

        return {
            "status": "success",
            "total_documents": len(docs),
            "total_papers": len(docs),
            "vector_index_size": (
                len(self.vector_engine.vector_storage.metadata)
                if os.path.exists(self.vector_engine.vector_storage_path)
                else len(docs)
            ),
            "categories": categories_list,
        }

    def handle_command(self, req: Dict[str, Any]) -> Dict[str, Any]:
        """Dispatches JSON IPC commands to the underlying VectorEngine."""
        from typing import Callable

        cmd = req.get("cmd", "")
        handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]] = {
            "ping": lambda _: {"status": "ok", "message": "pong"},
            "search": self._handle_search,
            "get_document": self._handle_get_document,
            "get_paper": self._handle_get_paper,
            "get_related": self._handle_get_related,
            "get_stats": lambda _: self._handle_get_stats(),
        }
        handler = handlers.get(cmd)
        if handler:
            return handler(req)
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

    def _read_client_request(
        self, client_sock: socket.socket
    ) -> Optional[Dict[str, Any]]:
        raw_data = b""
        while True:
            chunk = client_sock.recv(65536)
            if not chunk:
                break
            raw_data += chunk
            if b"\n" in raw_data:
                break
        if not raw_data:
            return None
        res: Dict[str, Any] = json.loads(raw_data.decode("utf-8").strip())
        return res

    def _send_client_response(
        self, client_sock: socket.socket, resp: Dict[str, Any]
    ) -> None:
        self.requests_handled += 1
        resp_bytes = (json.dumps(resp, ensure_ascii=False) + "\n").encode("utf-8")
        client_sock.sendall(resp_bytes)

    def _send_client_error(self, client_sock: socket.socket, exc: Exception) -> None:
        err_resp = {"status": "error", "error": str(exc)}
        try:
            client_sock.sendall((json.dumps(err_resp) + "\n").encode("utf-8"))
        except OSError:
            pass

    def _handle_client(self, client_sock: socket.socket) -> None:
        from observability.propagation import (
            clear_current_trace_context,
            set_current_trace_context,
        )

        client_sock.settimeout(5.0)
        try:
            req = self._read_client_request(client_sock)
            if req is not None:
                set_current_trace_context(
                    req.get("trace_id", ""), req.get("span_id", "")
                )
                resp = self.handle_command(req)
                self._send_client_response(client_sock, resp)
        except Exception as e:
            self._send_client_error(client_sock, e)
        finally:
            clear_current_trace_context()
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

    def _cleanup_server_sock(self) -> None:
        if self._server_sock:
            try:
                self._server_sock.close()
            except OSError:
                pass
            self._server_sock = None

    def stop(self) -> None:
        """Stops the listener thread and removes the socket file."""
        self._running = False
        self._cleanup_server_sock()
        self._atexit_cleanup()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1.0)


class SearchLifecycleHook(LifecycleHook):
    """
    Lifecycle hook for running SearchService within a ManagedServiceWorker.
    """

    def __init__(
        self,
        socket_path: Optional[str] = None,
        workspace_dir: Optional[str] = None,
    ) -> None:
        ws = workspace_dir or os.path.abspath(
            os.path.dirname(
                os.path.dirname(
                    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
                )
            )
        )
        sock = socket_path or os.path.join(ws, "outputs", "supervisor", "search.sock")
        self.service = SearchService(socket_path=sock, workspace_dir=ws)

    def setup(self) -> bool:
        """Initializes and starts search IPC server."""
        try:
            self.service.start()
            return True
        except Exception as e:
            logger.error("Failed to start SearchService: %s", e)
            return False

    def health_check(self) -> bool:
        """Verifies search engine responsiveness."""
        if not self.service._running:
            return False
        try:
            resp = self.service.handle_command({"cmd": "ping"})
            return resp.get("status") == "ok" and resp.get("message") == "pong"
        except Exception:
            return False

    def on_flush(self) -> None:
        """No-op for search engine flush."""
        pass

    def teardown(self) -> None:
        """Stops search IPC service and unlinks socket."""
        self.service.stop()

    def get_metrics(self) -> Dict[str, Any]:
        """Returns runtime performance metrics from SearchService."""
        return {
            "requests_handled": getattr(self.service, "requests_handled", 0),
        }
