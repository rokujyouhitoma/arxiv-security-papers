#!/usr/bin/env python3
"""
Base JSON-RPC Transport, Server Loop, and Performance Logger for Model Context Protocol (MCP).
Standardizes stdio communication, tool dispatching, prompts, resources, and real-time performance auditing.
"""

import json
import os
import sys
import threading
import time
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional


def get_workspace_dir() -> str:
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur != os.path.dirname(cur):
        if (
            os.path.exists(os.path.join(cur, "pyproject.toml"))
            or os.path.exists(os.path.join(cur, "Makefile"))
            or os.path.exists(os.path.join(cur, ".agents"))
        ):
            return cur
        cur = os.path.dirname(cur)
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


WORKSPACE_DIR = get_workspace_dir()
_LOG_LOCK = threading.Lock()
_MCP_PERF_LOG_PATH = os.path.join(
    WORKSPACE_DIR, "outputs", "logs", "mcp_perf_log.jsonl"
)


def _ensure_log_dir() -> None:
    os.makedirs(os.path.dirname(_MCP_PERF_LOG_PATH), exist_ok=True)


def log_mcp_performance(
    server_name: str,
    method: str,
    name: str,
    execution_ms: float,
    status: str = "success",
    args_summary: Optional[Dict[str, Any]] = None,
    metrics: Optional[Dict[str, Any]] = None,
    error_message: Optional[str] = None,
) -> None:
    """
    Logs MCP server execution performance to both stderr (console) and outputs/logs/mcp_perf_log.jsonl.
    Uses stderr to preserve stdout for JSON-RPC communication without protocol interference.
    """
    metrics_data = metrics or {}
    args_data = args_summary or {}

    record: Dict[str, Any] = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "server": server_name,
        "method": method,
        "name": name,
        "execution_ms": round(execution_ms, 3),
        "status": status,
        "args": args_data,
        "metrics": metrics_data,
    }
    if error_message:
        record["error"] = error_message

    # Format metrics for console log line
    metrics_str = (
        ", ".join(f"{k}: {v}" for k, v in metrics_data.items()) if metrics_data else ""
    )
    metrics_part = f" | {metrics_str}" if metrics_str else ""
    err_part = f" | Error: {error_message}" if error_message else ""

    # 1. Output formatted real-time performance line to stderr
    log_line = (
        f"[MCP-PERF] ⚡ [{server_name}] {method} '{name}' | "
        f"Time: {execution_ms:.2f}ms | Status: {status}{metrics_part}{err_part}"
    )
    sys.stderr.write(log_line + "\n")
    sys.stderr.flush()

    # 2. Append structured record to mcp_perf_log.jsonl
    try:
        _ensure_log_dir()
        with _LOG_LOCK:
            with open(_MCP_PERF_LOG_PATH, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception as e:
        sys.stderr.write(f"[MCP-PERF] Failed to write log: {e}\n")


def run_mcp_server(
    server_name: str = "mcp-server",
    tools_manifest: Optional[List[Dict[str, Any]]] = None,
    tool_handlers: Optional[
        Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]]
    ] = None,
    prompts_manifest: Optional[List[Dict[str, Any]]] = None,
    prompt_handlers: Optional[
        Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]]
    ] = None,
    resources_manifest: Optional[List[Dict[str, Any]]] = None,
    resource_handlers: Optional[
        Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]]
    ] = None,
) -> None:
    """
    Standard event loop processing JSON-RPC messages from stdin, dispatching tools/prompts/resources,
    and recording performance measurements.
    """
    tools = tools_manifest or []
    t_handlers = tool_handlers or {}
    prompts = prompts_manifest or []
    p_handlers = prompt_handlers or {}
    resources = resources_manifest or []
    r_handlers = resource_handlers or {}

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            method = req.get("method")
            req_id = req.get("id")

            # 1. Tool capabilities
            if method == "tools/list":
                resp: Dict[str, Any] = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"tools": tools},
                }
            elif method == "tools/call":
                p = req.get("params", {})
                tool_name = p.get("name", "")
                args = p.get("arguments", {})

                t0 = time.perf_counter()
                if tool_name in t_handlers:
                    try:
                        res = t_handlers[tool_name](args)
                        exec_ms = (time.perf_counter() - t0) * 1000.0
                        status = (
                            "error"
                            if isinstance(res, dict) and res.get("status") == "error"
                            else "success"
                        )

                        # Extract metrics if available
                        metrics: Dict[str, Any] = {}
                        if isinstance(res, dict):
                            if "count" in res:
                                metrics["count"] = res["count"]
                            elif "results" in res and isinstance(res["results"], list):
                                metrics["count"] = len(res["results"])
                            elif "papers" in res and isinstance(res["papers"], list):
                                metrics["count"] = len(res["papers"])

                        log_mcp_performance(
                            server_name=server_name,
                            method="tools/call",
                            name=tool_name,
                            execution_ms=exec_ms,
                            status=status,
                            args_summary=args,
                            metrics=metrics,
                        )
                    except Exception as handler_err:
                        exec_ms = (time.perf_counter() - t0) * 1000.0
                        res = {"status": "error", "message": str(handler_err)}
                        log_mcp_performance(
                            server_name=server_name,
                            method="tools/call",
                            name=tool_name,
                            execution_ms=exec_ms,
                            status="error",
                            args_summary=args,
                            error_message=str(handler_err),
                        )
                else:
                    res = {"error": f"Unknown tool '{tool_name}'"}
                    log_mcp_performance(
                        server_name=server_name,
                        method="tools/call",
                        name=tool_name,
                        execution_ms=0.0,
                        status="error",
                        error_message=f"Unknown tool '{tool_name}'",
                    )

                resp = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": json.dumps(res, ensure_ascii=False, indent=2),
                            }
                        ]
                    },
                }

            # 2. Prompt capabilities
            elif method == "prompts/list":
                resp = {"jsonrpc": "2.0", "id": req_id, "result": {"prompts": prompts}}
            elif method == "prompts/get":
                p = req.get("params", {})
                prompt_name = p.get("name", "")
                args = p.get("arguments", {})

                t0 = time.perf_counter()
                if prompt_name in p_handlers:
                    res = p_handlers[prompt_name](args)
                    exec_ms = (time.perf_counter() - t0) * 1000.0
                    log_mcp_performance(
                        server_name=server_name,
                        method="prompts/get",
                        name=prompt_name,
                        execution_ms=exec_ms,
                        status="success",
                        args_summary=args,
                    )
                else:
                    res = {"error": f"Unknown prompt '{prompt_name}'"}
                    log_mcp_performance(
                        server_name=server_name,
                        method="prompts/get",
                        name=prompt_name,
                        execution_ms=0.0,
                        status="error",
                        error_message=f"Unknown prompt '{prompt_name}'",
                    )
                resp = {"jsonrpc": "2.0", "id": req_id, "result": res}

            # 3. Resource capabilities
            elif method == "resources/list":
                resp = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"resources": resources},
                }
            elif method == "resources/read":
                p = req.get("params", {})
                uri = p.get("uri", "")

                t0 = time.perf_counter()
                if uri in r_handlers:
                    res = r_handlers[uri](p)
                    exec_ms = (time.perf_counter() - t0) * 1000.0
                    log_mcp_performance(
                        server_name=server_name,
                        method="resources/read",
                        name=uri,
                        execution_ms=exec_ms,
                        status="success",
                    )
                else:
                    res = {"error": f"Unknown resource URI '{uri}'"}
                    log_mcp_performance(
                        server_name=server_name,
                        method="resources/read",
                        name=uri,
                        execution_ms=0.0,
                        status="error",
                        error_message=f"Unknown resource URI '{uri}'",
                    )
                resp = {"jsonrpc": "2.0", "id": req_id, "result": res}

            # 4. Unknown / Notifications
            else:
                resp = {"jsonrpc": "2.0", "id": req_id, "result": {}}

            sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
            sys.stdout.flush()
        except Exception as e:
            sys.stderr.write(f"Error handling MCP request: {e}\n")
