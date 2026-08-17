#!/usr/bin/env python3
"""
Loosely-Coupled Vector DB Protocol Client.
Provides high-level typed API that communicates with Vector DB exclusively
via the standardized request/response message protocol.
"""

from typing import Any, Dict, List, Optional, Sequence

from .protocol import VectorDBProtocolError, VectorDBProtocolHandler


class VectorDBClient:
    """
    Client for interacting with Vector DB engine via protocol frames.
    Decouples callers from internal storage layout, mmap operations, and index internals.
    """

    def __init__(self, handler: VectorDBProtocolHandler) -> None:
        self._handler = handler

    def ping(self) -> bool:
        """Sends ping request to verify DB engine responsiveness."""
        resp = self._handler.handle_request({"op": "ping", "params": {}})
        return resp.get("status") == "ok"

    def get_info(self) -> Dict[str, Any]:
        """Retrieves vector DB metadata, dimensions, counts, and health status."""
        resp = self._handler.handle_request({"op": "info", "params": {}})
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
        resp = self._handler.handle_request(req)
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
        resp = self._handler.handle_request(req)
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
        resp = self._handler.handle_request(req)
        if resp.get("status") != "ok":
            raise VectorDBProtocolError(resp.get("error", "Search KNN failed"))

        matches: List[Dict[str, Any]] = resp.get("result", {}).get("matches", [])
        return matches

    def get_by_id(self, doc_id: str) -> Optional[Dict[str, Any]]:
        """Retrieves vector and metadata for a specific document ID."""
        req = {"op": "get_by_id", "params": {"id": doc_id}}
        resp = self._handler.handle_request(req)
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
        resp = self._handler.handle_request(req)
        return resp
