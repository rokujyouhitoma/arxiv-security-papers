#!/usr/bin/env python3
"""
Thread-safe Structured Query & Access Logging for API Gateway.
Appends analytics logs to outputs/logs/query_log.jsonl and outputs/logs/web_access.jsonl.
Zero external dependencies (pure standard library).
"""

import json
import os
import threading
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from observability.masking import mask_text
from observability.propagation import get_current_trace_id

_LOG_LOCK = threading.Lock()


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
_LOGS_DIR = os.path.join(WORKSPACE_DIR, "outputs", "logs")
_QUERY_LOG_PATH = os.path.join(_LOGS_DIR, "query_log.jsonl")
_ACCESS_LOG_PATH = os.path.join(_LOGS_DIR, "web_access.jsonl")


def _ensure_log_dir() -> None:
    os.makedirs(_LOGS_DIR, exist_ok=True)


def _write_jsonl(path: str, record: Dict[str, Any]) -> None:
    _ensure_log_dir()
    with _LOG_LOCK:
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")


def log_http_access(
    method: str,
    path: str,
    status_code: int,
    latency_ms: float,
    client_ip: str = "-",
    user_agent: str = "-",
) -> None:
    """Records one structured HTTP access log entry."""
    tid = get_current_trace_id()
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": "INFO",
        "service": "web_gateway",
        "trace_id": tid,
        "event": {
            "category": "http",
            "action": "request",
            "outcome": "success" if status_code < 400 else "failure",
        },
        "http": {
            "method": method,
            "path": path,
            "status_code": status_code,
            "latency_ms": round(latency_ms, 2),
            "client_ip": client_ip,
            "user_agent": user_agent,
        },
        "message": f"{method} {path} {status_code} ({latency_ms:.2f}ms)",
    }
    try:
        _write_jsonl(_ACCESS_LOG_PATH, record)
    except Exception:
        pass


def _build_query_performance_dict(
    profile: Dict[str, Any], total_ms: float, candidates_eval: int
) -> Dict[str, Any]:
    throughput = (
        round(candidates_eval / (total_ms / 1000.0), 1) if total_ms > 0 else 0.0
    )
    return {
        "total_ms": total_ms,
        "tokenize_ms": profile.get("tokenize_ms", 0.0),
        "candidate_pruning_ms": profile.get("candidate_pruning_ms", 0.0),
        "scoring_ms": profile.get("scoring_ms", 0.0),
        "candidates_evaluated": candidates_eval,
        "total_documents": profile.get("total_documents", 0),
        "throughput_docs_per_sec": throughput,
        "cached": profile.get("cached", False),
        "intent": profile.get("intent", "general"),
        "clauses_parsed": profile.get("clauses_parsed", 0),
        "cpu_ms": profile.get("cpu_ms", 0.0),
        "peak_memory_kb": profile.get("peak_memory_kb", 0.0),
        "memory_delta_kb": profile.get("memory_delta_kb", 0.0),
    }


def log_query(
    query: str,
    top_k: int,
    category: Optional[str],
    result_count: int,
    profile: Dict[str, Any],
    remote_addr: str = "-",
) -> None:
    """Appends one structured JSONL record to the query log and outputs metrics."""
    masked_query = mask_text(query)
    total_ms = profile.get("total_ms", 0.0)
    candidates_eval = profile.get("candidates_evaluated", 0)
    perf_dict = _build_query_performance_dict(profile, total_ms, candidates_eval)
    tid = get_current_trace_id()

    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": "INFO",
        "service": "search.engine",
        "trace_id": tid,
        "event": {"category": "search", "action": "query", "outcome": "success"},
        "query": masked_query,
        "top_k": top_k,
        "category": category,
        "result_count": result_count,
        "performance": perf_dict,
        "remote_addr": remote_addr,
        "message": f"Query {masked_query!r} completed with {result_count} hits in {total_ms:.2f}ms",
    }

    try:
        _write_jsonl(_QUERY_LOG_PATH, record)
    except Exception:
        pass


__all__ = [
    "get_workspace_dir",
    "WORKSPACE_DIR",
    "log_query",
    "log_http_access",
]
