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
import tracemalloc
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


def make_tool_response(
    data: Optional[Dict[str, Any]] = None,
    meta: Optional[Dict[str, Any]] = None,
    status: str = "success",
) -> Dict[str, Any]:
    """
    Constructs a standardized, high-cohesion MCP tool response payload.
    """
    res: Dict[str, Any] = {"status": status}
    if data:
        res.update(data)
    if meta:
        res["_meta"] = meta
    return res


def make_error_response(
    message: str,
    code: str = "EXECUTION_ERROR",
    details: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Constructs a standardized MCP error response payload.
    """
    res: Dict[str, Any] = {
        "status": "error",
        "error_code": code,
        "message": message,
    }
    if details:
        res["details"] = details
    return res


def _build_log_strings(
    server_name: str,
    method: str,
    name: str,
    execution_ms: float,
    status: str,
    cpu_ms: float,
    peak_memory_kb: float,
    metrics_data: Dict[str, Any],
    error_message: Optional[str],
) -> str:
    metrics_str = (
        ", ".join(f"{k}: {v}" for k, v in metrics_data.items()) if metrics_data else ""
    )
    metrics_part = f" | {metrics_str}" if metrics_str else ""
    err_part = f" | Error: {error_message}" if error_message else ""
    return (
        f"[MCP-PERF] ⚡ [{server_name}] {method} '{name}' | "
        f"Time: {execution_ms:.2f}ms (CPU: {cpu_ms:.2f}ms) | Peak RAM: {peak_memory_kb:.1f}KB | "
        f"Status: {status}{metrics_part}{err_part}"
    )


def _write_perf_record(record: Dict[str, Any]) -> None:
    try:
        _ensure_log_dir()
        with _LOG_LOCK:
            with open(_MCP_PERF_LOG_PATH, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception as e:
        sys.stderr.write(f"[MCP-PERF] Failed to write log: {e}\n")


def log_mcp_performance(
    server_name: str,
    method: str,
    name: str,
    execution_ms: float,
    status: str = "success",
    cpu_ms: float = 0.0,
    peak_memory_kb: float = 0.0,
    memory_delta_kb: float = 0.0,
    args_summary: Optional[Dict[str, Any]] = None,
    metrics: Optional[Dict[str, Any]] = None,
    error_message: Optional[str] = None,
) -> None:
    """
    Logs MCP server execution performance (time, CPU, and memory) to both stderr (console)
    and outputs/logs/mcp_perf_log.jsonl.
    """
    metrics_data = metrics or {}
    args_data = args_summary or {}

    record: Dict[str, Any] = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "server": server_name,
        "method": method,
        "name": name,
        "execution_ms": round(execution_ms, 3),
        "cpu_ms": round(cpu_ms, 3),
        "peak_memory_kb": round(peak_memory_kb, 3),
        "memory_delta_kb": round(memory_delta_kb, 3),
        "status": status,
        "args": args_data,
        "metrics": metrics_data,
    }
    if error_message:
        record["error"] = error_message

    log_line = _build_log_strings(
        server_name,
        method,
        name,
        execution_ms,
        status,
        cpu_ms,
        peak_memory_kb,
        metrics_data,
        error_message,
    )
    sys.stderr.write(log_line + "\n")
    sys.stderr.flush()
    _write_perf_record(record)


def _extract_metrics(res: Any) -> Dict[str, Any]:
    if not isinstance(res, dict):
        return {}
    if "count" in res:
        return {"count": res["count"]}
    for key in ("results", "papers"):
        val = res.get(key)
        if isinstance(val, list):
            return {"count": len(val)}
    return {}


def paginate_results(
    items: List[Any],
    offset: int = 0,
    limit: int = 10,
    max_limit: int = 50,
) -> tuple[List[Any], Dict[str, Any]]:
    """Applies safe slicing and returns paginated items with pagination metadata."""
    safe_offset = max(0, offset)
    safe_limit = max(1, min(limit, max_limit))
    total = len(items)
    paginated = items[safe_offset : safe_offset + safe_limit]
    has_more = (safe_offset + safe_limit) < total
    pagination_meta: Dict[str, Any] = {
        "total": total,
        "offset": safe_offset,
        "limit": safe_limit,
        "has_more": has_more,
    }
    if has_more:
        pagination_meta["next_offset"] = safe_offset + safe_limit
    return paginated, pagination_meta


def _handle_tool_call_success(
    server_name: str,
    tool_name: str,
    args: Dict[str, Any],
    res: Any,
    t0_wall: float,
    t0_cpu: float,
    start_mem: int,
) -> None:
    exec_ms = (time.perf_counter() - t0_wall) * 1000.0
    cpu_ms = (time.process_time() - t0_cpu) * 1000.0
    end_mem, peak_mem = tracemalloc.get_traced_memory()
    status = (
        "error" if isinstance(res, dict) and res.get("status") == "error" else "success"
    )
    log_mcp_performance(
        server_name=server_name,
        method="tools/call",
        name=tool_name,
        execution_ms=exec_ms,
        status=status,
        cpu_ms=cpu_ms,
        peak_memory_kb=peak_mem / 1024.0,
        memory_delta_kb=(end_mem - start_mem) / 1024.0,
        args_summary=args,
        metrics=_extract_metrics(res),
    )


def _handle_tool_call_error(
    server_name: str,
    tool_name: str,
    args: Dict[str, Any],
    err: Exception,
    t0_wall: float,
    t0_cpu: float,
    start_mem: int,
) -> Dict[str, Any]:
    exec_ms = (time.perf_counter() - t0_wall) * 1000.0
    cpu_ms = (time.process_time() - t0_cpu) * 1000.0
    end_mem, peak_mem = tracemalloc.get_traced_memory()
    log_mcp_performance(
        server_name=server_name,
        method="tools/call",
        name=tool_name,
        execution_ms=exec_ms,
        status="error",
        cpu_ms=cpu_ms,
        peak_memory_kb=peak_mem / 1024.0,
        memory_delta_kb=(end_mem - start_mem) / 1024.0,
        args_summary=args,
        error_message=str(err),
    )
    return {"status": "error", "message": str(err)}


def _dispatch_tools_call(
    server_name: str,
    p: Dict[str, Any],
    t_handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
) -> Dict[str, Any]:
    tool_name = p.get("name", "")
    args = p.get("arguments", {})
    was_tracing = tracemalloc.is_tracing()
    if not was_tracing:
        tracemalloc.start()
    tracemalloc.reset_peak()
    t0_wall, t0_cpu = time.perf_counter(), time.process_time()
    start_mem, _ = tracemalloc.get_traced_memory()

    if tool_name in t_handlers:
        try:
            res = t_handlers[tool_name](args)
            _handle_tool_call_success(
                server_name, tool_name, args, res, t0_wall, t0_cpu, start_mem
            )
        except Exception as handler_err:
            res = _handle_tool_call_error(
                server_name, tool_name, args, handler_err, t0_wall, t0_cpu, start_mem
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
    if not was_tracing:
        tracemalloc.stop()
    return {
        "content": [
            {"type": "text", "text": json.dumps(res, ensure_ascii=False, indent=2)}
        ]
    }


def _dispatch_prompts_get(
    server_name: str,
    p: Dict[str, Any],
    p_handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
) -> Dict[str, Any]:
    prompt_name = p.get("name", "")
    args = p.get("arguments", {})
    was_tracing = tracemalloc.is_tracing()
    if not was_tracing:
        tracemalloc.start()
    tracemalloc.reset_peak()
    t0_wall = time.perf_counter()
    t0_cpu = time.process_time()
    start_mem, _ = tracemalloc.get_traced_memory()

    if prompt_name in p_handlers:
        try:
            res = p_handlers[prompt_name](args)
            exec_ms = (time.perf_counter() - t0_wall) * 1000.0
            cpu_ms = (time.process_time() - t0_cpu) * 1000.0
            end_mem, peak_mem = tracemalloc.get_traced_memory()
            log_mcp_performance(
                server_name=server_name,
                method="prompts/get",
                name=prompt_name,
                execution_ms=exec_ms,
                status="success",
                cpu_ms=cpu_ms,
                peak_memory_kb=peak_mem / 1024.0,
                memory_delta_kb=(end_mem - start_mem) / 1024.0,
                args_summary=args,
            )
        except Exception as e:
            res = {"error": f"Handler error in prompt '{prompt_name}': {e}"}
            log_mcp_performance(
                server_name=server_name,
                method="prompts/get",
                name=prompt_name,
                execution_ms=0.0,
                status="error",
                error_message=str(e),
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
    if not was_tracing:
        tracemalloc.stop()
    return res


def _dispatch_resources_read(
    server_name: str,
    p: Dict[str, Any],
    r_handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
) -> Dict[str, Any]:
    uri = p.get("uri", "")
    was_tracing = tracemalloc.is_tracing()
    if not was_tracing:
        tracemalloc.start()
    tracemalloc.reset_peak()
    t0_wall = time.perf_counter()
    t0_cpu = time.process_time()
    start_mem, _ = tracemalloc.get_traced_memory()

    if uri in r_handlers:
        try:
            res = r_handlers[uri](p)
            exec_ms = (time.perf_counter() - t0_wall) * 1000.0
            cpu_ms = (time.process_time() - t0_cpu) * 1000.0
            end_mem, peak_mem = tracemalloc.get_traced_memory()
            log_mcp_performance(
                server_name=server_name,
                method="resources/read",
                name=uri,
                execution_ms=exec_ms,
                status="success",
                cpu_ms=cpu_ms,
                peak_memory_kb=peak_mem / 1024.0,
                memory_delta_kb=(end_mem - start_mem) / 1024.0,
            )
        except Exception as e:
            res = {"error": f"Handler error in resource '{uri}': {e}"}
            log_mcp_performance(
                server_name=server_name,
                method="resources/read",
                name=uri,
                execution_ms=0.0,
                status="error",
                error_message=str(e),
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
    if not was_tracing:
        tracemalloc.stop()
    return res


def _handle_initialize(
    server_name: str, req_id: Any, p: Dict[str, Any]
) -> Dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {"listChanged": False},
                "prompts": {"listChanged": False},
                "resources": {"subscribe": False, "listChanged": False},
            },
            "serverInfo": {
                "name": server_name,
                "version": "1.0.0",
            },
        },
    }


def _dispatch_rpc_request(
    server_name: str,
    req: Dict[str, Any],
    tools: List[Dict[str, Any]],
    t_handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
    prompts: List[Dict[str, Any]],
    p_handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
    resources: List[Dict[str, Any]],
    r_handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
) -> Optional[Dict[str, Any]]:
    method = req.get("method")
    req_id = req.get("id")
    p = req.get("params", {})

    if method == "initialize":
        return _handle_initialize(server_name, req_id, p)
    if method == "notifications/initialized":
        return None
    if method == "ping":
        return {"jsonrpc": "2.0", "id": req_id, "result": {}}

    res_map: Dict[str, Callable[[], Any]] = {
        "tools/list": lambda: {"tools": tools},
        "tools/call": lambda: _dispatch_tools_call(server_name, p, t_handlers),
        "prompts/list": lambda: {"prompts": prompts},
        "prompts/get": lambda: _dispatch_prompts_get(server_name, p, p_handlers),
        "resources/list": lambda: {"resources": resources},
        "resources/read": lambda: _dispatch_resources_read(server_name, p, r_handlers),
    }

    if method in res_map:
        return {"jsonrpc": "2.0", "id": req_id, "result": res_map[method]()}
    return {"jsonrpc": "2.0", "id": req_id, "result": {}}


def _process_mcp_line(
    line: str,
    server_name: str,
    tools: List[Dict[str, Any]],
    t_handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
    prompts: List[Dict[str, Any]],
    p_handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
    resources: List[Dict[str, Any]],
    r_handlers: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
) -> None:
    line_clean = line.strip()
    if not line_clean:
        return
    try:
        req = json.loads(line_clean)
        resp = _dispatch_rpc_request(
            server_name,
            req,
            tools,
            t_handlers,
            prompts,
            p_handlers,
            resources,
            r_handlers,
        )
        if resp is not None:
            sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
            sys.stdout.flush()
    except Exception as e:
        sys.stderr.write(f"Error handling MCP request: {e}\n")


def _init_tool_registries(
    tools_manifest: Optional[List[Dict[str, Any]]],
    tool_handlers: Optional[Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]]],
) -> tuple[List[Dict[str, Any]], Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]]]:
    return (tools_manifest if tools_manifest is not None else []), (
        tool_handlers if tool_handlers is not None else {}
    )


def _init_prompt_resource_registries(
    prompts_manifest: Optional[List[Dict[str, Any]]],
    prompt_handlers: Optional[Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]]],
    resources_manifest: Optional[List[Dict[str, Any]]],
    resource_handlers: Optional[Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]]],
) -> tuple[
    List[Dict[str, Any]],
    Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
    List[Dict[str, Any]],
    Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]],
]:
    p = prompts_manifest if prompts_manifest is not None else []
    ph = prompt_handlers if prompt_handlers is not None else {}
    r = resources_manifest if resources_manifest is not None else []
    rh = resource_handlers if resource_handlers is not None else {}
    return p, ph, r, rh


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
    """Standard event loop processing JSON-RPC messages from stdin."""
    tools, t_handlers = _init_tool_registries(tools_manifest, tool_handlers)
    prompts, p_handlers, resources, r_handlers = _init_prompt_resource_registries(
        prompts_manifest, prompt_handlers, resources_manifest, resource_handlers
    )

    for line in sys.stdin:
        _process_mcp_line(
            line,
            server_name,
            tools,
            t_handlers,
            prompts,
            p_handlers,
            resources,
            r_handlers,
        )
