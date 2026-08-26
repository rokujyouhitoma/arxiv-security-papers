#!/usr/bin/env python3
"""
API Handlers for Gateway Layer.
Provides REST endpoints (/api/search, /api/paper, /api/trends, /api/stats, /api/mcp),
static asset streaming, and presentation preview routing.
"""

from __future__ import annotations

import json
import mimetypes
import os
from typing import TYPE_CHECKING, Any, Callable, Dict, List, Optional

from database.client import DatabaseClient
from mcp.papers_server import (
    PROMPTS_MANIFEST,
    RESOURCES_MANIFEST,
    TOOLS_MANIFEST,
    dispatch_tool,
    handle_get_latest_trends,
    handle_get_paper_summary,
    handle_get_prompt,
    handle_read_resource,
)
from search.client import SearchClient
from security.validation import is_safe_workspace_path

if TYPE_CHECKING:
    from search.vector_engine import VectorEngine

from ..presentation.template import render_okf_preview_html
from .logger import log_query
from .router import response_bytes, response_error, response_html, response_json

MAX_MCP_PAYLOAD_BYTES = 1024 * 1024  # 1MB


class GatewayHandlers:
    """
    Encapsulates all HTTP and JSON-RPC API endpoint implementations.
    """

    def __init__(
        self,
        workspace_dir: str,
        vector_engine: Optional[VectorEngine] = None,
        search_client: Optional[SearchClient] = None,
        database_client: Optional[DatabaseClient] = None,
    ) -> None:
        self.workspace_dir = workspace_dir
        self.site_dir = os.path.join(workspace_dir, "site")
        self._vector_engine = vector_engine
        self._search_client = search_client
        self._database_client = database_client

    @property
    def database_client(self) -> DatabaseClient:
        """Retrieves or creates DatabaseClient instance for IPC database requests."""
        if self._database_client is None:
            self._database_client = DatabaseClient(workspace_dir=self.workspace_dir)
        return self._database_client

    @property
    def search_client(self) -> SearchClient:
        """Retrieves or creates SearchClient instance for IPC search requests."""
        if self._search_client is None:
            self._search_client = SearchClient(workspace_dir=self.workspace_dir)
        return self._search_client

    @property
    def vector_engine(self) -> VectorEngine:
        """
        Retrieves the VectorEngine instance for serving queries.
        Strictly operates in serving (read-only) mode using pre-built indices.
        Never triggers index building during server startup or request handling.
        """
        if self._vector_engine is not None:
            return self._vector_engine
        return self.search_client.fallback_engine

    def _get_paper(self, clean_id: str) -> Optional[Dict[str, Any]]:
        """Finds paper metadata by clean_id."""
        if self._vector_engine is not None:
            if clean_id in self._vector_engine.documents_by_id:
                return self._vector_engine.documents_by_id[clean_id]
            for doc in self._vector_engine.documents:
                if doc.get("id") == clean_id:
                    return doc
            return None
        return self.search_client.get_paper(clean_id)

    def handle_search(
        self,
        start_response: Callable[..., Any],
        query_params: Dict[str, List[str]],
        remote_addr: str = "-",
    ) -> List[bytes]:
        """Handles /api/search with SearchClient or VectorEngine."""
        query = query_params.get("q", [""])[0].strip()
        category = query_params.get("category", [None])[0]
        mode = query_params.get("mode", ["hybrid"])[0]
        try:
            top_k = int(query_params.get("top_k", ["20"])[0])
        except ValueError:
            top_k = 20

        if not query:
            return response_json(
                start_response,
                {"status": "success", "query": "", "total": 0, "results": []},
            )

        if self._vector_engine is not None:
            if mode == "vector":
                results = self._vector_engine.search_vector_ann(
                    query=query, top_k=top_k
                )
                profile: Dict[str, Any] = {"mode": "vector", "total_ms": 1.0}
            elif mode == "rrf":
                results = self._vector_engine.search_rrf_hybrid(
                    query=query, top_k=top_k, category=category
                )
                profile = {"mode": "rrf", "total_ms": 1.0}
            else:
                results, profile = self._vector_engine.search_with_profile(
                    query=query, top_k=top_k, category=category
                )
            resp_dict: Dict[str, Any] = {
                "status": "success",
                "query": query,
                "category": category,
                "mode": mode,
                "total": len(results),
                "profile": profile,
                "results": results,
            }
        else:
            resp_dict = self.search_client.search(
                query=query, top_k=top_k, category=category, mode=mode
            )
            profile = resp_dict.get("profile", {})
            results = resp_dict.get("results", [])

        log_query(
            query=query,
            top_k=top_k,
            category=category,
            result_count=len(results),
            profile=profile,
            remote_addr=remote_addr,
        )

        return response_json(start_response, resp_dict)

    def handle_paper_related(
        self, start_response: Callable[..., Any], clean_id: str
    ) -> List[bytes]:
        """Handles /api/paper/<clean_id>/related graph exploration."""
        if self._vector_engine is not None:
            paper = self._get_paper(clean_id)
            if not paper:
                return response_error(
                    start_response,
                    f"Paper '{clean_id}' not found",
                    status="404 Not Found",
                )

            related = self._vector_engine.proximity_graph.get_neighbors(clean_id)
            mermaid = f"graph TD;\n  root[{clean_id}]"
            for r in related:
                r_id = r.get("id", "paper")
                mermaid += f"\n  root --> node_{r_id}[{r_id}]"

            return response_json(
                start_response,
                {
                    "status": "success",
                    "paper_id": clean_id,
                    "related_papers": related,
                    "mermaid_graph": mermaid,
                },
            )

        resp = self.search_client.get_related(clean_id)
        if not resp or resp.get("status") != "success":
            return response_error(
                start_response,
                f"Paper '{clean_id}' not found",
                status="404 Not Found",
            )
        return response_json(start_response, resp)

    def handle_paper(
        self, start_response: Callable[..., Any], path: str
    ) -> List[bytes]:
        """Handles /api/paper/<clean_id> retrieval."""
        subpath = path.replace("/api/paper/", "").strip()
        if subpath.endswith("/related"):
            clean_id = subpath.replace("/related", "").strip()
            return self.handle_paper_related(start_response, clean_id)

        clean_id = subpath
        paper = self._get_paper(clean_id)
        if not paper:
            return response_error(
                start_response, f"Paper '{clean_id}' not found", status="404 Not Found"
            )
        return response_json(start_response, {"status": "success", "paper": paper})

    def handle_trends(
        self,
        start_response: Callable[..., Any],
        query_params: Dict[str, List[str]],
    ) -> List[bytes]:
        """Handles /api/trends retrieval."""
        limit_str = query_params.get("limit", ["10"])[0]
        try:
            limit = int(limit_str)
        except ValueError:
            limit = 10
        trends_res = handle_get_latest_trends({"limit": limit})
        return response_json(start_response, trends_res)

    def handle_stats(self, start_response: Callable[..., Any]) -> List[bytes]:
        """Handles /api/stats metadata retrieval."""
        if self._vector_engine is not None:
            papers = self._vector_engine.documents
            cats: Dict[str, int] = {}
            for p in papers:
                for c in p.get("tags", []):
                    cats[str(c)] = cats.get(str(c), 0) + 1

            categories_list: List[Dict[str, Any]] = [
                {"name": k, "count": v} for k, v in cats.items()
            ]
            categories_list.sort(key=lambda x: int(x["count"]), reverse=True)

            stats = {
                "status": "success",
                "server_interface": "PEP 3333 WSGI",
                "total_papers": len(papers),
                "vector_index_size": (
                    len(self._vector_engine.vector_storage.metadata)
                    if os.path.exists(self._vector_engine.vector_storage_path)
                    else len(papers)
                ),
                "categories": categories_list,
            }
            return response_json(start_response, stats)

        stats = self.search_client.get_stats()
        stats["server_interface"] = "PEP 3333 WSGI"
        return response_json(start_response, stats)

    def handle_preview(
        self, start_response: Callable[..., Any], path: str
    ) -> List[bytes]:
        """Handles /preview/<clean_id> HTML rendering using Presentation layer."""
        clean_id = path.replace("/preview/", "").strip()
        paper = self._get_paper(clean_id)
        if not paper:
            return response_error(
                start_response, f"Paper '{clean_id}' not found", status="404 Not Found"
            )

        rel_path = paper.get("path", "")
        abs_path = os.path.join(self.workspace_dir, rel_path)
        if not os.path.exists(abs_path):
            return response_error(
                start_response,
                f"OKF document file not found: {rel_path}",
                status="404 Not Found",
            )

        try:
            with open(abs_path, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception as e:
            return response_error(
                start_response,
                f"Failed to read file: {e}",
                status="500 Internal Server Error",
            )

        html_doc = render_okf_preview_html(
            arxiv_id=clean_id,
            content=content,
            raw_md_path="/" + rel_path,
        )
        return response_html(start_response, html_doc)

    def _check_safe_file(self, target_path: str) -> Optional[str]:
        """Checks if a target path is safe, exists, and is a file."""
        if (
            is_safe_workspace_path(target_path, self.workspace_dir)
            and os.path.exists(target_path)
            and os.path.isfile(target_path)
        ):
            return target_path
        return None

    def _resolve_static_file(self, clean_path: str) -> Optional[str]:
        target = "index.html" if clean_path in ["", "index.html"] else clean_path
        site_path = os.path.join(self.site_dir, target)
        if os.path.exists(site_path) and os.path.isfile(site_path):
            return site_path

        # Handle outputs/ alias mapping (raw_data, okf_papers, executive_summaries)
        if target.startswith(("raw_data/", "okf_papers/", "executive_summaries/")):
            return self._check_safe_file(
                os.path.join(self.workspace_dir, "outputs", target)
            )

        return self._check_safe_file(os.path.join(self.workspace_dir, target))

    @staticmethod
    def _guess_content_type(full_path: str) -> str:
        if full_path.endswith((".js", ".mjs")):
            return "application/javascript; charset=utf-8"
        if full_path.endswith(".css"):
            return "text/css; charset=utf-8"
        if full_path.endswith(".html"):
            return "text/html; charset=utf-8"
        if full_path.endswith((".md", ".txt")):
            return "text/plain; charset=utf-8"
        mime_type, _ = mimetypes.guess_type(full_path)
        return mime_type or "application/octet-stream"

    def handle_static(
        self, start_response: Callable[..., Any], path: str
    ) -> List[bytes]:
        """Handles static asset resolution and streaming."""
        clean_path = path.lstrip("/")

        # Check path traversal
        if ".." in path or not is_safe_workspace_path(
            os.path.join(self.workspace_dir, clean_path), self.workspace_dir
        ):
            return response_error(start_response, "Forbidden", status="403 Forbidden")

        full_path = self._resolve_static_file(clean_path)
        if not full_path:
            return response_error(
                start_response, f"Resource not found: {path}", status="404 Not Found"
            )

        mime_type = self._guess_content_type(full_path)
        try:
            with open(full_path, "rb") as f:
                body = f.read()
            return response_bytes(start_response, body, content_type=mime_type)
        except Exception as e:
            return response_error(
                start_response,
                f"Failed to read file: {e}",
                status="500 Internal Server Error",
            )

    def _execute_mcp_legacy_or_rpc(
        self, req: Dict[str, Any], start_response: Callable[..., Any]
    ) -> List[bytes]:
        # Legacy format: {"name": "search_security_papers", "arguments": ...}
        if "name" in req:
            tool_name = req["name"]
            tool_args = req.get("arguments", {})
            result = dispatch_tool(tool_name, tool_args)
            return response_json(
                start_response,
                {"status": "success", "tool": tool_name, "result": result},
            )

        # JSON-RPC 2.0 format
        rpc_id = req.get("id")
        method = req.get("method")
        params = req.get("params", {})

        if not method:
            return response_error(
                start_response,
                "Missing 'name' or 'method' in request payload",
                status="400 Bad Request",
            )

        handlers_map: Dict[str, Any] = {
            "tools/list": lambda: {"tools": TOOLS_MANIFEST},
            "resources/list": lambda: {"resources": RESOURCES_MANIFEST},
            "prompts/list": lambda: {"prompts": PROMPTS_MANIFEST},
            "tools/call": lambda: dispatch_tool(
                params.get("name", ""), params.get("arguments", {})
            ),
            "resources/read": lambda: handle_read_resource(params.get("uri", "")),
            "prompts/get": lambda: handle_get_prompt(
                params.get("name", ""), params.get("arguments", {})
            ),
            "papers/summary": lambda: handle_get_paper_summary(params),
            "papers/trends": lambda: handle_get_latest_trends(params),
        }

        handler = handlers_map.get(method)
        if handler:
            result = handler()
            return response_json(
                start_response,
                {"jsonrpc": "2.0", "result": result, "id": rpc_id},
            )

        return response_json(
            start_response,
            {
                "jsonrpc": "2.0",
                "error": {
                    "code": -32601,
                    "message": f"Method not found: {method}",
                },
                "id": rpc_id,
            },
        )

    def handle_mcp_post(
        self, environ: Dict[str, Any], start_response: Callable[..., Any]
    ) -> List[bytes]:
        """Handles MCP JSON-RPC and legacy tool execution over HTTP POST."""
        try:
            length = int(environ.get("CONTENT_LENGTH", "0"))
        except ValueError:
            length = 0

        if length <= 0:
            return response_error(
                start_response, "Empty request body", status="400 Bad Request"
            )

        if length > MAX_MCP_PAYLOAD_BYTES:
            return response_error(
                start_response,
                "Payload exceeds maximum allowed size (1MB)",
                status="413 Payload Too Large",
            )

        try:
            body_bytes = environ["wsgi.input"].read(length)
            req = json.loads(body_bytes.decode("utf-8"))
            if not isinstance(req, dict) or not req:
                return response_error(
                    start_response,
                    "Request body must be non-empty JSON object",
                    status="400 Bad Request",
                )
        except Exception as e:
            return response_error(
                start_response,
                f"Invalid JSON payload: {e}",
                status="400 Bad Request",
            )

        return self._execute_mcp_legacy_or_rpc(req, start_response)
