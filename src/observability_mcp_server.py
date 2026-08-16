#!/usr/bin/env python3
"""
Observability-Focused Model Context Protocol (MCP) Server for AI Coding Agents.
Provides profiling, memory allocation tracking, micro-benchmarking, and bytecode inspection tools:
- profile_code_performance: cProfile + pstats bottleneck identification
- track_memory_allocations: tracemalloc line-by-line memory allocation tracking
- benchmark_alternatives: timeit comparison of implementation candidates
- inspect_bytecode: dis instruction analysis and disassembly
- get_system_metrics: Search engine and cache runtime metrics
"""

import ast
import cProfile
import dis
import io
import json
import os
import pstats
import sys
import time
import timeit
import tracemalloc
from typing import Any, Callable, Dict, List, Optional, Set, Tuple, cast

if "src" not in sys.path:
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

SERVER_NAME = "arxiv-security-observability-mcp-server"
SERVER_VERSION = "1.0.0"

# ---------------------------------------------------------------------------
# AST Security Validator (Secure Coding Guard)
# ---------------------------------------------------------------------------

BLOCKED_MODULES: Set[str] = {"subprocess", "socket", "pty", "shutil"}
BLOCKED_CALLS: Set[str] = {"system", "popen", "spawn", "fork", "kill", "remove", "rmdir", "unlink"}


def validate_safe_code(code_str: str) -> Optional[str]:
    """
    Parses Python code into AST and rejects dangerous system/network calls before execution.
    Returns None if safe, or an error message if dangerous patterns are detected.
    """
    try:
        tree = ast.parse(code_str)
    except SyntaxError as e:
        return f"Syntax error: {str(e)}"

    for node in ast.walk(tree):
        # Block dangerous imports
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name in BLOCKED_MODULES:
                    return f"Security Exception: Import of module '{alias.name}' is prohibited."
        elif isinstance(node, ast.ImportFrom):
            if node.module in BLOCKED_MODULES:
                return f"Security Exception: Import from module '{node.module}' is prohibited."

        # Block dangerous attribute calls (e.g. os.system)
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute):
                if node.func.attr in BLOCKED_CALLS:
                    return f"Security Exception: Call to '{node.func.attr}' is prohibited."
            elif isinstance(node.func, ast.Name):
                if node.func.id in {"eval", "exec", "__import__"}:
                    return f"Security Exception: Dynamic call to '{node.func.id}' is prohibited."

    return None


# ---------------------------------------------------------------------------
# Tool Implementations
# ---------------------------------------------------------------------------

def handle_profile_code_performance(params: Dict[str, Any]) -> Dict[str, Any]:
    """Profiles Python code execution using cProfile and pstats with AST safety checks."""
    code_str = params.get("code", "")
    top_n = params.get("top_n", 10)
    sort_by = params.get("sort_by", "cumtime")

    if not code_str.strip():
        return {"error": "Parameter 'code' is required."}

    sec_err = validate_safe_code(code_str)
    if sec_err:
        return {"error": sec_err}

    profiler = cProfile.Profile()
    local_scope: Dict[str, Any] = {}

    t0 = time.perf_counter()
    try:
        compiled = compile(code_str, "<mcp_profile>", "exec")
        profiler.enable()
        exec(compiled, {}, local_scope)
        profiler.disable()
    except Exception as e:
        profiler.disable()
        return {"error": f"Execution error during profiling: {str(e)}"}

    wall_time_ms = round((time.perf_counter() - t0) * 1000.0, 3)

    s = io.StringIO()
    ps = pstats.Stats(profiler, stream=s).sort_stats(sort_by)
    ps.print_stats(top_n)
    stats_text = s.getvalue()

    return {
        "wall_time_ms": wall_time_ms,
        "sort_by": sort_by,
        "top_bottlenecks": stats_text,
        "message": f"Successfully profiled code in {wall_time_ms} ms.",
    }


def handle_track_memory_allocations(params: Dict[str, Any]) -> Dict[str, Any]:
    """Tracks peak memory and line-by-line allocations using tracemalloc with AST safety checks."""
    code_str = params.get("code", "")
    top_lines = params.get("top_lines", 5)

    if not code_str.strip():
        return {"error": "Parameter 'code' is required."}

    sec_err = validate_safe_code(code_str)
    if sec_err:
        return {"error": sec_err}

    was_tracing = tracemalloc.is_tracing()
    if not was_tracing:
        tracemalloc.start()
    tracemalloc.reset_peak()

    local_scope: Dict[str, Any] = {}
    try:
        compiled = compile(code_str, "<mcp_mem_track>", "exec")
        exec(compiled, {}, local_scope)
        cur, peak = tracemalloc.get_traced_memory()
        snapshot = tracemalloc.take_snapshot()
    except Exception as e:
        if not was_tracing:
            tracemalloc.stop()
        return {"error": f"Execution error during memory tracking: {str(e)}"}

    if not was_tracing:
        tracemalloc.stop()

    top_stats = snapshot.statistics("lineno")
    allocations: List[Dict[str, Any]] = []
    for stat in top_stats[:top_lines]:
        allocations.append({
            "traceback": str(stat.traceback),
            "size_kb": round(stat.size / 1024.0, 3),
            "count": stat.count,
        })

    return {
        "current_memory_kb": round(cur / 1024.0, 3),
        "peak_memory_kb": round(peak / 1024.0, 3),
        "top_allocations": allocations,
        "message": f"Peak memory consumed: {round(peak / 1024.0, 3)} KB.",
    }


def handle_benchmark_alternatives(params: Dict[str, Any]) -> Dict[str, Any]:
    """Benchmarks multiple alternative code candidates using timeit with AST safety checks."""
    candidates = params.get("candidates", [])
    number = params.get("number", 100)
    repeat = params.get("repeat", 3)

    if not candidates or not isinstance(candidates, list):
        return {"error": "Parameter 'candidates' must be a non-empty list of {name, code}."}

    results: List[Dict[str, Any]] = []
    for cand in candidates:
        name = cand.get("name", "candidate")
        code = cand.get("code", "")
        if not code.strip():
            continue

        sec_err = validate_safe_code(code)
        if sec_err:
            results.append({"name": name, "error": sec_err})
            continue

        try:
            compiled = compile(code, f"<mcp_bench_{name}>", "exec")

            def _run_candidate(c: Any = compiled) -> None:
                exec(c, {}, {})

            timer = timeit.Timer(_run_candidate)
            times = timer.repeat(repeat=repeat, number=number)
            min_time_ms = round((min(times) / number) * 1000.0, 5)
            avg_time_ms = round((sum(times) / len(times) / number) * 1000.0, 5)
            results.append({
                "name": name,
                "min_time_ms": min_time_ms,
                "avg_time_ms": avg_time_ms,
            })
        except Exception as e:
            results.append({"name": name, "error": str(e)})

    # Determine winner
    valid_results = [r for r in results if "min_time_ms" in r]
    winner = None
    if valid_results:
        valid_results.sort(key=lambda x: x["min_time_ms"])
        winner = valid_results[0]["name"]
        fastest_time = valid_results[0]["min_time_ms"]
        for r in valid_results:
            if fastest_time > 0:
                r["speedup_ratio"] = round(r["min_time_ms"] / fastest_time, 2)
            else:
                r["speedup_ratio"] = 1.0

    return {
        "iterations_per_run": number,
        "repeats": repeat,
        "winner": winner,
        "comparisons": results,
    }


def handle_inspect_bytecode(params: Dict[str, Any]) -> Dict[str, Any]:
    """Disassembles Python code using the dis standard library with AST validation."""
    code_str = params.get("code", "")
    if not code_str.strip():
        return {"error": "Parameter 'code' is required."}

    sec_err = validate_safe_code(code_str)
    if sec_err:
        return {"error": sec_err}

    try:
        compiled = compile(code_str, "<mcp_dis>", "exec")
        instructions: List[Dict[str, Any]] = []
        op_counts: Dict[str, int] = {}
        for instr in dis.get_instructions(compiled):
            opname = instr.opname
            op_counts[opname] = op_counts.get(opname, 0) + 1
            instructions.append({
                "opname": opname,
                "opcode": instr.opcode,
                "argval": str(instr.argval),
                "offset": instr.offset,
            })
    except Exception as e:
        return {"error": f"Disassembly error: {str(e)}"}

    return {
        "total_instructions": len(instructions),
        "opcode_distribution": op_counts,
        "instructions": instructions[:50],  # Limit to top 50
    }


def handle_get_system_metrics(params: Dict[str, Any]) -> Dict[str, Any]:
    """Returns system and search engine runtime metrics."""
    from search.server.cache import FilterCache, QueryResultCache
    fc = FilterCache()
    qc = QueryResultCache()

    return {
        "status": "healthy",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "python_version": sys.version,
        "filter_cache_stats": fc.stats(),
        "query_cache_stats": qc.stats(),
    }


# ---------------------------------------------------------------------------
# MCP Tool & Resource Registries
# ---------------------------------------------------------------------------

TOOLS_REGISTRY = {
    "profile_code_performance": {
        "description": "Profiles Python code execution with cProfile + pstats to identify top bottleneck functions and cumulative times.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {"type": "string", "description": "Python code snippet or function to profile"},
                "top_n": {"type": "integer", "description": "Number of top bottleneck functions to return", "default": 10},
                "sort_by": {"type": "string", "description": "Sort key: cumtime, tottime, or calls", "default": "cumtime"},
            },
            "required": ["code"],
        },
        "handler": handle_profile_code_performance,
    },
    "track_memory_allocations": {
        "description": "Tracks peak RAM consumption and line-by-line memory allocation using tracemalloc to diagnose leaks.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {"type": "string", "description": "Python code snippet to execute and trace"},
                "top_lines": {"type": "integer", "description": "Number of top allocation lines to return", "default": 5},
            },
            "required": ["code"],
        },
        "handler": handle_track_memory_allocations,
    },
    "benchmark_alternatives": {
        "description": "Micro-benchmarks multiple Python code candidates using timeit and determines the fastest implementation.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "candidates": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "code": {"type": "string"},
                        },
                        "required": ["name", "code"],
                    },
                    "description": "List of candidate implementations to benchmark",
                },
                "number": {"type": "integer", "description": "Iterations per test run", "default": 100},
                "repeat": {"type": "integer", "description": "Repeat count", "default": 3},
            },
            "required": ["candidates"],
        },
        "handler": handle_benchmark_alternatives,
    },
    "inspect_bytecode": {
        "description": "Disassembles Python code into bytecode instructions using the dis standard library to verify low-level efficiency.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {"type": "string", "description": "Python code to disassemble into bytecode"},
            },
            "required": ["code"],
        },
        "handler": handle_inspect_bytecode,
    },
    "get_system_metrics": {
        "description": "Retrieves live search engine metrics, cache hit ratios, and runtime health stats.",
        "inputSchema": {"type": "object", "properties": {}},
        "handler": handle_get_system_metrics,
    },
}

RESOURCES_REGISTRY = {
    "observability://metrics/search_engine": {
        "name": "Search Engine Performance Metrics",
        "description": "Real-time metrics, cache statistics, and query latency distribution.",
        "mimeType": "application/json",
    },
    "observability://schema/profiler": {
        "name": "Profiler Output Schema",
        "description": "JSON schema for structured cProfile and tracemalloc outputs.",
        "mimeType": "application/json",
    },
}

PROMPTS_REGISTRY = {
    "optimize_bottleneck_prompt": {
        "description": "Template to instruct AI coding agents to refactor code based on cProfile and tracemalloc results.",
        "arguments": [
            {"name": "function_name", "description": "Name of the target function", "required": True},
            {"name": "profile_summary", "description": "cProfile/pstats summary output", "required": True},
        ],
    },
}


# ---------------------------------------------------------------------------
# JSON-RPC 2.0 Dispatcher
# ---------------------------------------------------------------------------

def dispatch_rpc_request(req: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Dispatches a single JSON-RPC 2.0 request."""
    method = req.get("method")
    req_id = req.get("id")
    params = req.get("params", {})

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}, "resources": {}, "prompts": {}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        }

    elif method == "tools/list":
        tools_list = [
            {
                "name": name,
                "description": defs["description"],
                "inputSchema": defs["inputSchema"],
            }
            for name, defs in TOOLS_REGISTRY.items()
        ]
        return {"jsonrpc": "2.0", "id": req_id, "result": {"tools": tools_list}}

    elif method == "tools/call":
        tool_name = params.get("name")
        tool_args = params.get("arguments", {})
        if tool_name not in TOOLS_REGISTRY:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32601, "message": f"Unknown tool: {tool_name}"},
            }

        raw_handler = TOOLS_REGISTRY[tool_name]["handler"]
        handler = cast(Callable[[Dict[str, Any]], Dict[str, Any]], raw_handler)
        result = handler(tool_args)
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False, indent=2)}]
            },
        }

    elif method == "resources/list":
        res_list = [
            {
                "uri": uri,
                "name": defs["name"],
                "description": defs["description"],
                "mimeType": defs["mimeType"],
            }
            for uri, defs in RESOURCES_REGISTRY.items()
        ]
        return {"jsonrpc": "2.0", "id": req_id, "result": {"resources": res_list}}

    elif method == "resources/read":
        uri = params.get("uri")
        if uri == "observability://metrics/search_engine":
            metrics = handle_get_system_metrics({})
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "contents": [{"uri": uri, "mimeType": "application/json", "text": json.dumps(metrics, indent=2)}]
                },
            }
        elif uri == "observability://schema/profiler":
            schema_doc = {
                "type": "object",
                "properties": {
                    "wall_time_ms": {"type": "number"},
                    "cpu_time_ms": {"type": "number"},
                    "peak_memory_kb": {"type": "number"},
                    "top_bottlenecks": {"type": "string"},
                },
            }
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "contents": [{"uri": uri, "mimeType": "application/json", "text": json.dumps(schema_doc, indent=2)}]
                },
            }
        else:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32602, "message": f"Unknown resource URI: {uri}"},
            }

    elif method == "prompts/list":
        prompts_list = [
            {
                "name": name,
                "description": defs["description"],
                "arguments": defs["arguments"],
            }
            for name, defs in PROMPTS_REGISTRY.items()
        ]
        return {"jsonrpc": "2.0", "id": req_id, "result": {"prompts": prompts_list}}

    elif method == "prompts/get":
        prompt_name = params.get("name")
        if prompt_name == "optimize_bottleneck_prompt":
            args = params.get("arguments", {})
            fn_name = args.get("function_name", "target_function")
            summary = args.get("profile_summary", "No summary provided")
            text = (
                f"あなたは高信頼・高パフォーマンスなPythonコード最適化の専門家です。\n"
                f"以下の cProfile/pstats ボトルネック解析結果に基づき、`{fn_name}` をリファクタリングしてください。\n\n"
                f"### プロファイルサマリー:\n```\n{summary}\n```\n\n"
                f"### 要件:\n"
                f"1. 最も時間を消費しているホットパスの計算量を削減すること。\n"
                f"2. 不必要なメモリアロケーション（一時オブジェクト生成）を抑制すること。\n"
                f"3. 最適化前後の timeit マイクロベンチマークおよび dis 逆アセンブル命令数の変化を提示すること。\n"
            )
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "description": "Code Optimization Prompt based on Profiler Output",
                    "messages": [
                        {
                            "role": "user",
                            "content": {"type": "text", "text": text},
                        }
                    ],
                },
            }
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": -32601, "message": f"Unknown prompt: {prompt_name}"},
        }

    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    }


def run_server() -> None:
    """Runs stdio JSON-RPC server for MCP."""
    for line in sys.stdin:
        line_clean = line.strip()
        if not line_clean:
            continue
        try:
            req = json.loads(line_clean)
            resp = dispatch_rpc_request(req)
            if resp:
                sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
                sys.stdout.flush()
        except json.JSONDecodeError:
            err = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}
            sys.stdout.write(json.dumps(err) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    run_server()
