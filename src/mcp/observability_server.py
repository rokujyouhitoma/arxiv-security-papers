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
from typing import Any, Callable, Dict, List, Optional, Sequence, cast

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )

from security.sandbox import validate_safe_code

SERVER_NAME = "arxiv-security-observability-mcp-server"
SERVER_VERSION = "1.0.0"


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
        allocations.append(
            {
                "traceback": str(stat.traceback),
                "size_kb": round(stat.size / 1024.0, 3),
                "count": stat.count,
            }
        )

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
        return {
            "error": "Parameter 'candidates' must be a non-empty list of {name, code}."
        }

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
            results.append(
                {
                    "name": name,
                    "min_time_ms": min_time_ms,
                    "avg_time_ms": avg_time_ms,
                }
            )
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
            instructions.append(
                {
                    "opname": opname,
                    "opcode": instr.opcode,
                    "argval": str(instr.argval),
                    "offset": instr.offset,
                }
            )
    except Exception as e:
        return {"error": f"Disassembly error: {str(e)}"}

    return {
        "total_instructions": len(instructions),
        "opcode_distribution": op_counts,
        "instructions": instructions[:50],  # Limit to top 50
    }


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
LOGS_DIR = os.path.join(WORKSPACE_DIR, "outputs", "logs")


def _read_recent_jsonl_records(log_path: str, limit: int = 100) -> List[Dict[str, Any]]:
    """Reads the most recent records from a JSONL log file."""
    if not os.path.exists(log_path):
        return []
    records: List[Dict[str, Any]] = []
    try:
        with open(log_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        for line in reversed(lines):
            line = line.strip()
            if line:
                try:
                    records.append(json.loads(line))
                    if len(records) >= limit:
                        break
                except Exception:
                    continue
    except Exception as e:
        sys.stderr.write(f"[Observability] Error reading {log_path}: {e}\n")
    return records


def handle_get_system_metrics(params: Dict[str, Any]) -> Dict[str, Any]:
    """Returns system, memory allocation, and search engine runtime metrics."""
    from search.server.cache import FilterCache, QueryResultCache

    fc = FilterCache()
    qc = QueryResultCache()

    # Memory state
    is_tracing = tracemalloc.is_tracing()
    current_ram_kb = 0.0
    peak_ram_kb = 0.0
    if is_tracing:
        cur_bytes, peak_bytes = tracemalloc.get_traced_memory()
        current_ram_kb = round(cur_bytes / 1024.0, 2)
        peak_ram_kb = round(peak_bytes / 1024.0, 2)

    # Aggregated log stats
    mcp_records = _read_recent_jsonl_records(
        os.path.join(LOGS_DIR, "mcp_perf_log.jsonl"), limit=50
    )
    search_records = _read_recent_jsonl_records(
        os.path.join(LOGS_DIR, "search_perf_log.jsonl"), limit=50
    )

    mcp_lats = [r.get("execution_ms", 0.0) for r in mcp_records]
    search_lats = [
        r.get("performance", {}).get("total_ms", 0.0) for r in search_records
    ]

    return {
        "status": "healthy",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "python_version": sys.version,
        "memory": {
            "tracemalloc_active": is_tracing,
            "current_ram_kb": current_ram_kb,
            "peak_ram_kb": peak_ram_kb,
        },
        "filter_cache_stats": fc.stats(),
        "query_cache_stats": qc.stats(),
        "recent_activity": {
            "mcp_calls_sampled": len(mcp_records),
            "mcp_avg_latency_ms": (
                round(sum(mcp_lats) / len(mcp_lats), 3) if mcp_lats else 0.0
            ),
            "search_queries_sampled": len(search_records),
            "search_avg_latency_ms": (
                round(sum(search_lats) / len(search_lats), 3) if search_lats else 0.0
            ),
        },
    }


def handle_get_performance_logs(params: Dict[str, Any]) -> Dict[str, Any]:
    """Retrieves and filters logged performance records from outputs/logs/."""
    log_type = params.get("log_type", "all").lower()
    limit = int(params.get("limit", 50))
    min_latency = float(params.get("min_latency_ms", 0.0))

    files_to_read = []
    if log_type in ("mcp", "all"):
        files_to_read.append(("mcp", os.path.join(LOGS_DIR, "mcp_perf_log.jsonl")))
    if log_type in ("search", "all"):
        files_to_read.append(
            ("search", os.path.join(LOGS_DIR, "search_perf_log.jsonl"))
        )
    if log_type in ("query", "all"):
        files_to_read.append(("query", os.path.join(LOGS_DIR, "query_log.jsonl")))

    all_records: List[Dict[str, Any]] = []
    for source, path in files_to_read:
        records = _read_recent_jsonl_records(path, limit=limit)
        for r in records:
            r_copy = dict(r)
            r_copy["log_source"] = source
            lat = (
                r_copy.get("execution_ms")
                or r_copy.get("performance", {}).get("total_ms", 0.0)
                or r_copy.get("total_ms", 0.0)
            )
            if lat >= min_latency:
                all_records.append(r_copy)

    all_records.sort(key=lambda x: str(x.get("timestamp", "")), reverse=True)
    all_records = all_records[:limit]

    latencies = [
        r.get("execution_ms")
        or r.get("performance", {}).get("total_ms", 0.0)
        or r.get("total_ms", 0.0)
        for r in all_records
    ]
    peak_mems = [
        r.get("peak_memory_kb") or r.get("performance", {}).get("peak_memory_kb", 0.0)
        for r in all_records
    ]

    return {
        "status": "success",
        "log_type": log_type,
        "record_count": len(all_records),
        "summary": {
            "avg_latency_ms": (
                round(sum(latencies) / len(latencies), 3) if latencies else 0.0
            ),
            "max_latency_ms": round(max(latencies), 3) if latencies else 0.0,
            "max_peak_memory_kb": round(max(peak_mems), 3) if peak_mems else 0.0,
        },
        "records": all_records,
    }


def handle_dump_performance_metrics(params: Dict[str, Any]) -> Dict[str, Any]:
    """Generates a structured observability report across MCP and Search Engine."""
    fmt = params.get("format", "markdown").lower()
    mcp_records = _read_recent_jsonl_records(
        os.path.join(LOGS_DIR, "mcp_perf_log.jsonl"), limit=100
    )
    search_records = _read_recent_jsonl_records(
        os.path.join(LOGS_DIR, "search_perf_log.jsonl"), limit=100
    )

    mcp_lats = [r.get("execution_ms", 0.0) for r in mcp_records]
    mcp_peaks = [r.get("peak_memory_kb", 0.0) for r in mcp_records]

    search_lats = [
        r.get("performance", {}).get("total_ms", 0.0) for r in search_records
    ]
    search_peaks = [
        r.get("performance", {}).get("peak_memory_kb", 0.0) for r in search_records
    ]

    cur_time = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    mcp_stats: Dict[str, Any] = {
        "total_calls": len(mcp_records),
        "avg_execution_ms": (
            round(sum(mcp_lats) / len(mcp_lats), 3) if mcp_lats else 0.0
        ),
        "max_execution_ms": round(max(mcp_lats), 3) if mcp_lats else 0.0,
        "max_peak_memory_kb": round(max(mcp_peaks), 3) if mcp_peaks else 0.0,
    }
    search_stats: Dict[str, Any] = {
        "total_queries": len(search_records),
        "avg_latency_ms": (
            round(sum(search_lats) / len(search_lats), 3) if search_lats else 0.0
        ),
        "max_latency_ms": round(max(search_lats), 3) if search_lats else 0.0,
        "max_peak_memory_kb": round(max(search_peaks), 3) if search_peaks else 0.0,
    }
    summary: Dict[str, Any] = {
        "timestamp": cur_time,
        "mcp": mcp_stats,
        "search": search_stats,
    }

    if fmt == "json":
        return {"status": "success", "format": "json", "metrics": summary}

    lines = [
        "# 📊 統合可観測性（Observability）パフォーマンス & メモリレポート",
        "",
        f"**生成日時 (UTC)**: `{cur_time}`",
        "",
        "## 1. MCP サーバー実行メトリクス (MCP Server Metrics)",
        "",
        "| 指標 (Metric) | 測定値 (Measured) | 備考 (Note) |",
        "| :--- | :---: | :--- |",
        f"| **総呼び出し回数** | `{mcp_stats['total_calls']}` 件 | 最新 100 件のサンプリング |",
        f"| **平均実行時間** | `{mcp_stats['avg_execution_ms']} ms` | tools/call, prompts, resources |",
        f"| **最大実行時間** | `{mcp_stats['max_execution_ms']} ms` | ピーク処理時間 |",
        f"| **最大ピークメモリ** | `{mcp_stats['max_peak_memory_kb']} KB` | tracemalloc ピーク消費 |",
        "",
        "---",
        "",
        "## 2. 検索エンジン クエリ実行メトリクス (Search Engine Metrics)",
        "",
        "| 指標 (Metric) | 測定値 (Measured) | 備考 (Note) |",
        "| :--- | :---: | :--- |",
        f"| **総クエリ実行回数** | `{search_stats['total_queries']}` 件 | 最新 100 件のサンプリング |",
        f"| **平均クエリ所要時間** | `{search_stats['avg_latency_ms']} ms` | ハイブリッド検索パイプライン |",
        f"| **最大クエリ所要時間** | `{search_stats['max_latency_ms']} ms` | 最長レイテンシ |",
        f"| **最大ピークメモリ** | `{search_stats['max_peak_memory_kb']} KB` | クエリ処理時の最大消費 |",
        "",
    ]

    return {
        "status": "success",
        "format": "markdown",
        "metrics": summary,
        "markdown_report": "\n".join(lines),
    }


def handle_evaluate_search_quality(params: Dict[str, Any]) -> Dict[str, Any]:
    """Runs IR evaluation benchmark against ground-truth datasets and returns Precision, Recall, MAP, MRR, NDCG."""
    from search.eval.dataset import DEFAULT_SECURITY_GOLD_STANDARD
    from search.eval.evaluator import SearchEvaluator
    from search.server.handler.select_handler import SelectHandler

    top_k = params.get("top_k", 5)
    handler = SelectHandler()
    evaluator = SearchEvaluator(queries=DEFAULT_SECURITY_GOLD_STANDARD, top_k=top_k)

    def _search(q: str, k: int) -> Sequence[str]:
        resp = handler.handle_select(query=q, top_k=k)
        docs = resp.get("response", {}).get("docs", [])
        return [str(d.get("id", "")) for d in docs]

    eval_res = evaluator.evaluate(_search)
    markdown_report = evaluator.generate_markdown_report(eval_res)

    return {
        "summary": eval_res["summary"],
        "markdown_report": markdown_report,
        "query_details": eval_res["query_details"],
    }


# ---------------------------------------------------------------------------
# MCP Tool & Resource Registries
# ---------------------------------------------------------------------------

TOOLS_REGISTRY = {
    "profile_code_performance": {
        "description": (
            "Profiles Python code execution with cProfile + pstats to identify top bottleneck functions "
            "and cumulative times."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "Python code snippet or function to profile",
                },
                "top_n": {
                    "type": "integer",
                    "description": "Number of top bottleneck functions to return",
                    "default": 10,
                },
                "sort_by": {
                    "type": "string",
                    "description": "Sort key: cumtime, tottime, or calls",
                    "default": "cumtime",
                },
            },
            "required": ["code"],
        },
        "handler": handle_profile_code_performance,
    },
    "track_memory_allocations": {
        "description": (
            "Tracks peak RAM consumption and line-by-line memory allocation using tracemalloc to diagnose leaks."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "Python code snippet to execute and trace",
                },
                "top_lines": {
                    "type": "integer",
                    "description": "Number of top allocation lines to return",
                    "default": 5,
                },
            },
            "required": ["code"],
        },
        "handler": handle_track_memory_allocations,
    },
    "benchmark_alternatives": {
        "description": (
            "Micro-benchmarks multiple Python code candidates using timeit and determines the fastest implementation."
        ),
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
                "number": {
                    "type": "integer",
                    "description": "Iterations per test run",
                    "default": 100,
                },
                "repeat": {
                    "type": "integer",
                    "description": "Repeat count",
                    "default": 3,
                },
            },
            "required": ["candidates"],
        },
        "handler": handle_benchmark_alternatives,
    },
    "inspect_bytecode": {
        "description": (
            "Disassembles Python code into bytecode instructions using the dis standard library "
            "to verify low-level efficiency."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "Python code to disassemble into bytecode",
                },
            },
            "required": ["code"],
        },
        "handler": handle_inspect_bytecode,
    },
    "get_system_metrics": {
        "description": "Retrieves live search engine metrics, cache hit ratios, RAM stats, and latency records.",
        "inputSchema": {"type": "object", "properties": {}},
        "handler": handle_get_system_metrics,
    },
    "get_performance_logs": {
        "description": (
            "Retrieves and filters dumped performance and memory logs from MCP and Search Engine."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "log_type": {
                    "type": "string",
                    "description": "Log type: 'all', 'mcp', 'search', or 'query'",
                    "default": "all",
                },
                "limit": {
                    "type": "integer",
                    "description": "Maximum number of records to return",
                    "default": 50,
                },
                "min_latency_ms": {
                    "type": "number",
                    "description": "Optional minimum latency filter in milliseconds",
                    "default": 0.0,
                },
            },
        },
        "handler": handle_get_performance_logs,
    },
    "dump_performance_metrics": {
        "description": (
            "Generates a comprehensive Markdown/JSON performance report across MCP and Search Engine."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "format": {
                    "type": "string",
                    "description": "Output format: 'markdown' or 'json'",
                    "default": "markdown",
                },
            },
        },
        "handler": handle_dump_performance_metrics,
    },
    "evaluate_search_quality": {
        "description": (
            "Evaluates search engine accuracy across Precision@K, Recall@K, F1, MAP, MRR, and NDCG@K "
            "using standard benchmark datasets."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "top_k": {
                    "type": "integer",
                    "description": "Top-K documents to evaluate",
                    "default": 5,
                },
            },
        },
        "handler": handle_evaluate_search_quality,
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
    "observability://metrics/unified_report": {
        "name": "Unified Observability & Memory Report",
        "description": "Consolidated Markdown report of MCP and Search Engine performance.",
        "mimeType": "text/markdown",
    },
}

PROMPTS_REGISTRY = {
    "optimize_bottleneck_prompt": {
        "description": (
            "Template to instruct AI coding agents to refactor code based on cProfile and tracemalloc results."
        ),
        "arguments": [
            {
                "name": "function_name",
                "description": "Name of the target function",
                "required": True,
            },
            {
                "name": "profile_summary",
                "description": "cProfile/pstats summary output",
                "required": True,
            },
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
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps(result, ensure_ascii=False, indent=2),
                    }
                ]
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
                    "contents": [
                        {
                            "uri": uri,
                            "mimeType": "application/json",
                            "text": json.dumps(metrics, indent=2),
                        }
                    ]
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
                    "contents": [
                        {
                            "uri": uri,
                            "mimeType": "application/json",
                            "text": json.dumps(schema_doc, indent=2),
                        }
                    ]
                },
            }
        elif uri == "observability://metrics/unified_report":
            report = handle_dump_performance_metrics({"format": "markdown"})
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "contents": [
                        {
                            "uri": uri,
                            "mimeType": "text/markdown",
                            "text": report.get("markdown_report", ""),
                        }
                    ]
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
            err = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": "Parse error"},
            }
            sys.stdout.write(json.dumps(err) + "\n")
            sys.stdout.flush()


main = run_server

if __name__ == "__main__":
    main()
