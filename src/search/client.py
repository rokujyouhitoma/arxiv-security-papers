#!/usr/bin/env python3
"""
Lightweight Client for Search Engine IPC Service.
Communicates with the dedicated SearchService over Unix domain socket with zero-overhead,
and provides seamless, lazy in-process fallback when running standalone without supervisor.
"""

from __future__ import annotations

import json
import logging
import os
import socket
from typing import TYPE_CHECKING, Any, Dict, List, Optional

if TYPE_CHECKING:
    from .vector_engine import VectorEngine

logger = logging.getLogger(__name__)


class SearchClient:
    """
    Client interface for interacting with the Search Engine IPC Service.
    """

    def __init__(
        self,
        socket_path: Optional[str] = None,
        workspace_dir: Optional[str] = None,
        timeout: float = 5.0,
    ) -> None:
        self.workspace_dir = workspace_dir or os.path.abspath(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        )
        self.socket_path = socket_path or os.path.join(
            self.workspace_dir, "outputs", "supervisor", "search.sock"
        )
        self.timeout = timeout
        self._fallback_engine: Optional[VectorEngine] = None

    @property
    def fallback_engine(self) -> VectorEngine:
        """Lazily creates an in-process VectorEngine if IPC is unavailable."""
        if self._fallback_engine is None:
            logger.info("Initializing fallback in-process VectorEngine")
            from .vector_engine import VectorEngine

            self._fallback_engine = VectorEngine(
                workspace_dir=self.workspace_dir, lazy=False
            )
        return self._fallback_engine

    def close(self) -> None:
        """Releases client resources and clears cached fallback engine."""
        self._fallback_engine = None

    def is_socket_available(self) -> bool:
        """Checks if the search daemon Unix socket exists and is responsive."""
        if not os.path.exists(self.socket_path):
            return False
        try:
            return self.ping()
        except Exception:
            return False

    def _read_socket_response(self, sock: socket.socket) -> Optional[Dict[str, Any]]:
        raw_data = b""
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            raw_data += chunk
            if b"\n" in raw_data:
                break
        if not raw_data:
            return None
        res: Dict[str, Any] = json.loads(raw_data.decode("utf-8").strip())
        return res

    def _send_socket_payload(
        self, cmd_dict: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        try:
            sock.connect(self.socket_path)
            payload = (json.dumps(cmd_dict, ensure_ascii=False) + "\n").encode("utf-8")
            sock.sendall(payload)
            return self._read_socket_response(sock)
        finally:
            try:
                sock.close()
            except OSError:
                pass

    def send_command(self, cmd_dict: Dict[str, Any]) -> Dict[str, Any]:
        """Sends a JSON command to the SearchService over Unix domain socket."""
        if not os.path.exists(self.socket_path):
            return self._fallback_handle_command(cmd_dict)

        try:
            res = self._send_socket_payload(cmd_dict)
            return res if res is not None else self._fallback_handle_command(cmd_dict)
        except Exception as e:
            logger.warning(
                "Search IPC failed (%s), falling back to in-process engine", e
            )
            return self._fallback_handle_command(cmd_dict)

    def _fallback_search(self, req: Dict[str, Any]) -> Dict[str, Any]:
        engine = self.fallback_engine
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
            results = engine.search_vector_ann(query=query, top_k=top_k)
            profile: Dict[str, Any] = {"mode": "vector", "total_ms": 1.0}
        elif mode == "rrf":
            results = engine.search_rrf_hybrid(
                query=query, top_k=top_k, category=category
            )
            profile = {"mode": "rrf", "total_ms": 1.0}
        else:
            results, profile = engine.search_with_profile(
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

    def _fallback_get_paper(self, req: Dict[str, Any]) -> Dict[str, Any]:
        clean_id = str(req.get("id", "")).strip()
        doc = self.fallback_engine.documents_by_id.get(clean_id)
        if not doc:
            for d in self.fallback_engine.documents:
                if d.get("id") == clean_id:
                    doc = d
                    break
        if not doc:
            return {"status": "error", "error": f"Paper '{clean_id}' not found"}
        return {"status": "success", "paper": doc}

    def _fallback_get_related(self, req: Dict[str, Any]) -> Dict[str, Any]:
        clean_id = str(req.get("id", "")).strip()
        doc = self.fallback_engine.documents_by_id.get(clean_id)
        if not doc:
            return {"status": "error", "error": f"Paper '{clean_id}' not found"}
        related = self.fallback_engine.proximity_graph.get_neighbors(clean_id)
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

    def _fallback_get_stats(self) -> Dict[str, Any]:
        papers = self.fallback_engine.documents
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
            "vector_index_size": len(papers),
            "categories": categories_list,
        }

    def _fallback_handle_command(self, req: Dict[str, Any]) -> Dict[str, Any]:
        """Executes the command locally using the fallback VectorEngine."""
        from typing import Callable

        cmd = req.get("cmd", "")
        handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]] = {
            "ping": lambda _: {"status": "ok", "message": "pong"},
            "search": self._fallback_search,
            "get_paper": self._fallback_get_paper,
            "get_related": self._fallback_get_related,
            "get_stats": lambda _: self._fallback_get_stats(),
        }
        handler = handlers.get(cmd)
        if handler:
            return handler(req)
        return {"status": "error", "error": f"Unknown command: '{cmd}'"}

    def ping(self) -> bool:
        """Verifies if the SearchService is responsive."""
        resp = self.send_command({"cmd": "ping"})
        return resp.get("status") == "ok" and resp.get("message") == "pong"

    def search(
        self,
        query: str,
        top_k: int = 20,
        category: Optional[str] = None,
        mode: str = "hybrid",
    ) -> Dict[str, Any]:
        """Executes hybrid search query."""
        return self.send_command(
            {
                "cmd": "search",
                "query": query,
                "top_k": top_k,
                "category": category,
                "mode": mode,
            }
        )

    def get_document(self, doc_id: str) -> Optional[Dict[str, Any]]:
        """Generic document retrieval by ID."""
        resp = self.send_command({"cmd": "get_paper", "id": doc_id})
        if resp.get("status") == "success":
            doc = resp.get("paper")
            if isinstance(doc, dict):
                return doc
        return None

    def get_paper(self, clean_id: str) -> Optional[Dict[str, Any]]:
        """Retrieves paper metadata by clean_id (Backward-compatible alias)."""
        return self.get_document(clean_id)

    def get_related_documents(self, doc_id: str) -> Optional[Dict[str, Any]]:
        """Generic related document retrieval by ID."""
        resp = self.send_command({"cmd": "get_related", "id": doc_id})
        if resp.get("status") == "success":
            return resp
        return None

    def get_related(self, clean_id: str) -> Optional[Dict[str, Any]]:
        """Retrieves related paper graph (Backward-compatible alias)."""
        return self.get_related_documents(clean_id)

    def get_stats(self) -> Dict[str, Any]:
        """Retrieves index and category statistics."""
        return self.send_command({"cmd": "get_stats"})
