#!/usr/bin/env python3
"""
Vector DB Protocol & Message Framing Specification.
Establishes a strictly typed, loosely-coupled command/response protocol
for vector storage, ANN search, and lifecycle management.
"""

import time
from typing import Any, Dict, List, Optional, Sequence, Tuple


from ..index.embedding import DeterministicEmbedding
from ..index.index import HNSWIndex
from ..sql import SQLExecutor
from ..storage.storage import VectorStorage


class VectorDBProtocolError(Exception):
    """Raised when an invalid operation or protocol error occurs."""

    pass


class VectorDBProtocolHandler:
    """
    Protocol Request Dispatcher and Server Handler.
    Processes standardized protocol frames and maps them to storage and indexing actions,
    collecting execution and memory metrics at the protocol boundary.
    """

    SUPPORTED_OPERATIONS = {
        "ping",
        "info",
        "insert",
        "bulk_write",
        "search_knn",
        "get_by_id",
        "execute_sql",
    }

    def __init__(
        self,
        storage: VectorStorage,
        index: Optional[HNSWIndex] = None,
        embedding: Optional[DeterministicEmbedding] = None,
    ) -> None:
        self.storage = storage
        self.dim = storage.dim
        self.index = index or HNSWIndex(dim=self.dim)
        self.embedding = embedding or DeterministicEmbedding(dim=self.dim)
        self.sql_executor = SQLExecutor(
            default_storage=self.storage,
            default_index=self.index,
            embedding=self.embedding,
        )

    def _op_ping(self, params: Dict[str, Any]) -> Dict[str, Any]:
        return {"message": "pong", "timestamp": time.time()}

    def _op_info(self, params: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "dimension": self.dim,
            "count": self.storage.count,
            "storage_file": self.storage.file_path,
            "hnsw_max_level": self.index.max_level,
            "hnsw_nodes": len(self.index.vectors),
        }

    def _op_insert(self, params: Dict[str, Any]) -> Dict[str, Any]:
        raw_vector = params.get("vector")
        metadata = params.get("metadata", {})
        if not raw_vector:
            raise VectorDBProtocolError("Missing 'vector' parameter for insert")
        vector = self.embedding.normalize(raw_vector)
        idx = self.storage.append(vector, metadata)
        self.index.add_item(idx, vector)
        return {"index": idx, "id": metadata.get("id", str(idx))}

    def _op_bulk_write(self, params: Dict[str, Any]) -> Dict[str, Any]:
        raw_vectors = params.get("vectors", [])
        metadata = params.get("metadata", [])
        if len(raw_vectors) != len(metadata):
            raise VectorDBProtocolError(
                f"Vectors count ({len(raw_vectors)}) != metadata count ({len(metadata)})"
            )
        vectors = [self.embedding.normalize(v) for v in raw_vectors]
        self.storage.write_all(vectors, metadata)
        self.index = HNSWIndex(dim=self.dim)
        self.index.build_from_storage(vectors)
        return {"count": len(vectors), "status": "indexed"}

    def _resolve_query_vector(self, params: Dict[str, Any]) -> Sequence[float]:
        vector = params.get("vector")
        if vector:
            return self.embedding.normalize(vector)
        if "text" in params:
            return self.embedding.embed_text(params["text"])
        raise VectorDBProtocolError("Missing 'vector' or 'text' query parameter")

    def _format_knn_matches(
        self, matches: List[Tuple[int, float]]
    ) -> List[Dict[str, Any]]:
        match_results: List[Dict[str, Any]] = []
        for idx, sim in matches:
            if idx < len(self.storage.metadata):
                meta = self.storage.get_metadata(idx)
                match_results.append(
                    {
                        "index": idx,
                        "id": meta.get("id", str(idx)),
                        "score": round(sim, 4),
                        "metadata": meta,
                    }
                )
        return match_results

    def _op_search_knn(self, params: Dict[str, Any]) -> Dict[str, Any]:
        vector = self._resolve_query_vector(params)
        top_k = int(params.get("top_k", 10))
        ef_search = params.get("ef_search")
        ef = int(ef_search) if ef_search is not None else None
        matches = self.index.search(vector, top_k=top_k, ef_search=ef)
        match_results = self._format_knn_matches(matches)
        return {"total_matches": len(match_results), "matches": match_results}

    def _op_get_by_id(self, params: Dict[str, Any]) -> Dict[str, Any]:
        doc_id = params.get("id")
        if not doc_id:
            raise VectorDBProtocolError("Missing 'id' parameter")
        vec = self.storage.get_vector_by_id(doc_id)
        meta_idx = self.storage.id_to_idx.get(doc_id)
        doc_meta: Optional[Dict[str, Any]] = (
            self.storage.get_metadata(meta_idx) if meta_idx is not None else None
        )
        return {
            "found": vec is not None,
            "id": doc_id,
            "vector": list(vec) if vec is not None else None,
            "metadata": doc_meta,
        }

    def _op_execute_sql(self, params: Dict[str, Any]) -> Dict[str, Any]:
        sql = params.get("sql", "")
        role = params.get("role", "admin")
        if not sql:
            raise VectorDBProtocolError("Missing 'sql' parameter")
        return self.sql_executor.execute(sql, role=role, params=params)

    def _dispatch_operation(self, op: str, params: Dict[str, Any]) -> Dict[str, Any]:
        dispatchers = {
            "ping": self._op_ping,
            "info": self._op_info,
            "insert": self._op_insert,
            "bulk_write": self._op_bulk_write,
            "search_knn": self._op_search_knn,
            "get_by_id": self._op_get_by_id,
            "execute_sql": self._op_execute_sql,
        }
        return dispatchers[op](params)

    def handle_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """
        Executes a single protocol request and returns a structured response frame.
        """
        op = request.get("op", "")
        params = request.get("params", {})
        req_id = request.get("request_id")

        if op not in self.SUPPORTED_OPERATIONS:
            return {
                "status": "error",
                "op": op,
                "request_id": req_id,
                "error": f"Unknown operation: '{op}'. Supported: {sorted(self.SUPPORTED_OPERATIONS)}",
                "metrics": {"wall_time_ms": 0.0, "cpu_time_ms": 0.0},
                "result": {},
            }

        t0_wall = time.perf_counter()
        t0_cpu = time.process_time()

        try:
            result = self._dispatch_operation(op, params)
            wall_ms = (time.perf_counter() - t0_wall) * 1000.0
            cpu_ms = (time.process_time() - t0_cpu) * 1000.0

            return {
                "status": "ok",
                "op": op,
                "request_id": req_id,
                "result": result,
                "metrics": {
                    "wall_time_ms": round(wall_ms, 3),
                    "cpu_time_ms": round(cpu_ms, 3),
                },
            }

        except Exception as e:
            wall_ms = (time.perf_counter() - t0_wall) * 1000.0
            cpu_ms = (time.process_time() - t0_cpu) * 1000.0
            return {
                "status": "error",
                "op": op,
                "request_id": req_id,
                "error": str(e),
                "metrics": {
                    "wall_time_ms": round(wall_ms, 3),
                    "cpu_time_ms": round(cpu_ms, 3),
                },
                "result": {},
            }
