#!/usr/bin/env python3
"""
Thread-safe Query Logging for API Gateway.
Appends analytics logs to outputs/logs/query_log.jsonl.
"""

import json
import os
import threading
from datetime import datetime, timezone
from typing import Any, Dict, Optional

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
_QUERY_LOG_PATH = os.path.join(WORKSPACE_DIR, "outputs", "logs", "query_log.jsonl")


def _ensure_log_dir() -> None:
    os.makedirs(os.path.dirname(_QUERY_LOG_PATH), exist_ok=True)


def log_query(
    query: str,
    top_k: int,
    category: Optional[str],
    result_count: int,
    profile: Dict[str, Any],
    remote_addr: str = "-",
) -> None:
    """Appends one JSONL record to the query log and prints performance metrics. Thread-safe."""
    total_ms = profile.get("total_ms", 0.0)
    tokenize_ms = profile.get("tokenize_ms", 0.0)
    pruning_ms = profile.get("candidate_pruning_ms", 0.0)
    scoring_ms = profile.get("scoring_ms", 0.0)
    candidates_eval = profile.get("candidates_evaluated", 0)
    total_docs = profile.get("total_documents", 0)
    cached = profile.get("cached", False)
    intent = profile.get("intent", "general")
    clauses_parsed = profile.get("clauses_parsed", 0)

    cpu_ms = profile.get("cpu_ms", 0.0)
    peak_memory_kb = profile.get("peak_memory_kb", 0.0)
    memory_delta_kb = profile.get("memory_delta_kb", 0.0)

    throughput = (
        round(candidates_eval / (total_ms / 1000.0), 1) if total_ms > 0 else 0.0
    )

    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "query": query,
        "top_k": top_k,
        "category": category,
        "result_count": result_count,
        "performance": {
            "total_ms": total_ms,
            "tokenize_ms": tokenize_ms,
            "candidate_pruning_ms": pruning_ms,
            "scoring_ms": scoring_ms,
            "candidates_evaluated": candidates_eval,
            "total_documents": total_docs,
            "throughput_docs_per_sec": throughput,
            "cached": cached,
            "intent": intent,
            "clauses_parsed": clauses_parsed,
            "cpu_ms": cpu_ms,
            "peak_memory_kb": peak_memory_kb,
            "memory_delta_kb": memory_delta_kb,
        },
        "remote_addr": remote_addr,
    }

    try:
        _ensure_log_dir()
        with _LOG_LOCK:
            with open(_QUERY_LOG_PATH, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception as e:
        print(f"[QueryLogger] Warning: failed to write query log: {e}")

    cache_flag = " [CACHE HIT]" if cached else ""
    print(
        f"[QueryLogger]{cache_flag} query={query!r} intent={intent} clauses={clauses_parsed} "
        f"results={result_count}/{total_docs} time={total_ms:.2f}ms "
        f"(cpu={cpu_ms:.2f}ms, mem_peak={peak_memory_kb:.1f}KB, delta={memory_delta_kb:.1f}KB) "
        f"throughput={throughput} docs/s ip={remote_addr}"
    )
