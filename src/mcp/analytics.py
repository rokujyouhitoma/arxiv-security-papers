#!/usr/bin/env python3
"""
MCP Usage Analytics and Aggregation Engine.
Parses JSONL performance and activity logs, computes multi-dimensional metrics,
and renders structured console tables and Markdown reports.
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from mcp.base import _MCP_PERF_LOG_PATH, WORKSPACE_DIR


def load_mcp_logs(
    log_path: Optional[str] = None,
    server_filter: Optional[str] = None,
    since_iso: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Loads and filters raw MCP log entries from JSONL."""
    target_path = log_path or _MCP_PERF_LOG_PATH
    if not os.path.exists(target_path):
        return []

    records: List[Dict[str, Any]] = []
    with open(target_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
                if server_filter and rec.get("server") != server_filter:
                    continue
                if since_iso and rec.get("timestamp", "") < since_iso:
                    continue
                records.append(rec)
            except Exception:
                continue
    return records


def _init_stats() -> Dict[str, Any]:
    return {
        "total_requests": 0,
        "success_count": 0,
        "error_count": 0,
        "total_execution_ms": 0.0,
        "by_server": defaultdict(int),
        "by_method": defaultdict(int),
        "by_status": defaultdict(int),
        "tool_stats": defaultdict(
            lambda: {
                "calls": 0,
                "success": 0,
                "error": 0,
                "total_ms": 0.0,
                "min_ms": float("inf"),
                "max_ms": 0.0,
                "total_mem_kb": 0.0,
                "max_mem_kb": 0.0,
            }
        ),
        "hourly_distribution": defaultdict(int),
        "recent_errors": [],
    }


def _process_single_record(rec: Dict[str, Any], stats: Dict[str, Any]) -> None:
    stats["total_requests"] += 1
    status = rec.get("status", "unknown")
    stats["by_status"][status] += 1
    if status == "success":
        stats["success_count"] += 1
    else:
        stats["error_count"] += 1
        if len(stats["recent_errors"]) < 20:
            stats["recent_errors"].append(
                {
                    "timestamp": rec.get("timestamp", ""),
                    "server": rec.get("server", ""),
                    "name": rec.get("name", ""),
                    "error": rec.get("error", "Unknown error"),
                }
            )

    server = rec.get("server", "unknown")
    method = rec.get("method", "unknown")
    stats["by_server"][server] += 1
    stats["by_method"][method] += 1

    exec_ms = float(rec.get("execution_ms", 0.0))
    peak_kb = float(rec.get("peak_memory_kb", 0.0))
    stats["total_execution_ms"] += exec_ms

    name = rec.get("name", "unknown")
    t_stat = stats["tool_stats"][name]
    t_stat["calls"] += 1
    if status == "success":
        t_stat["success"] += 1
    else:
        t_stat["error"] += 1
    t_stat["total_ms"] += exec_ms
    t_stat["min_ms"] = min(t_stat["min_ms"], exec_ms)
    t_stat["max_ms"] = max(t_stat["max_ms"], exec_ms)
    t_stat["total_mem_kb"] += peak_kb
    t_stat["max_mem_kb"] = max(t_stat["max_mem_kb"], peak_kb)

    ts = rec.get("timestamp", "")
    if len(ts) >= 13:
        hour_key = ts[:13] + ":00"
        stats["hourly_distribution"][hour_key] += 1


def _finalize_tool_metrics(
    raw_tool_stats: Dict[str, Dict[str, Any]],
) -> Dict[str, Dict[str, Any]]:
    finalized: Dict[str, Dict[str, Any]] = {}
    for name, data in raw_tool_stats.items():
        calls = data["calls"]
        avg_ms = data["total_ms"] / calls if calls > 0 else 0.0
        avg_mem = data["total_mem_kb"] / calls if calls > 0 else 0.0
        min_ms = data["min_ms"] if data["min_ms"] != float("inf") else 0.0
        success_rate = (data["success"] / calls * 100.0) if calls > 0 else 0.0

        finalized[name] = {
            "calls": calls,
            "success": data["success"],
            "error": data["error"],
            "success_rate": round(success_rate, 2),
            "avg_ms": round(avg_ms, 2),
            "min_ms": round(min_ms, 2),
            "max_ms": round(data["max_ms"], 2),
            "avg_mem_kb": round(avg_mem, 2),
            "max_mem_kb": round(data["max_mem_kb"], 2),
        }
    return finalized


def compute_mcp_metrics(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Computes high-level and granular usage metrics across records."""
    stats = _init_stats()
    for rec in records:
        _process_single_record(rec, stats)

    total = stats["total_requests"]
    avg_latency = stats["total_execution_ms"] / total if total > 0 else 0.0
    succ_rate = (stats["success_count"] / total * 100.0) if total > 0 else 0.0

    finalized_tools = _finalize_tool_metrics(stats["tool_stats"])

    return {
        "total_requests": total,
        "success_count": stats["success_count"],
        "error_count": stats["error_count"],
        "success_rate_pct": round(succ_rate, 2),
        "avg_execution_ms": round(avg_latency, 2),
        "servers": dict(stats["by_server"]),
        "methods": dict(stats["by_method"]),
        "tools": finalized_tools,
        "hourly": dict(stats["hourly_distribution"]),
        "recent_errors": stats["recent_errors"],
    }


def render_mcp_markdown_report(metrics: Dict[str, Any]) -> str:
    """Renders comprehensive, executive-ready Markdown summary of MCP metrics."""
    now_utc = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    total = metrics.get("total_requests", 0)
    succ_pct = metrics.get("success_rate_pct", 0.0)
    avg_lat = metrics.get("avg_execution_ms", 0.0)

    lines: List[str] = [
        "# 📊 Model Context Protocol (MCP) 利用状況・集計レポート",
        "",
        f"> **生成日時**: {now_utc}  ",
        f"> **総リクエスト数**: {total:,} 件 | **成功率**: {succ_pct}% | **平均応答時間**: {avg_lat} ms",
        "",
        "---",
        "",
        "## 📈 1. サーバー別・メソッド別サマリー",
        "",
        "| サーバー名 | リクエスト数 | 構成比 |",
        "| :--- | :---: | :---: |",
    ]

    servers = metrics.get("servers", {})
    for s_name, count in sorted(servers.items(), key=lambda x: x[1], reverse=True):
        pct = round(count / total * 100.0, 1) if total > 0 else 0.0
        lines.append(f"| `{s_name}` | {count:,} | {pct}% |")

    lines.extend(
        [
            "",
            "## 🛠️ 2. Tool / リソース別 呼び出しランキング & パフォーマンス",
            "",
            "| Tool / リソース名 | 呼出数 | 成功率 | 平均応答 (ms) | 最大応答 (ms) | 平均RAM (KB) |",
            "| :--- | :---: | :---: | :---: | :---: | :---: |",
        ]
    )

    tools = metrics.get("tools", {})
    sorted_tools = sorted(tools.items(), key=lambda x: x[1]["calls"], reverse=True)
    for t_name, data in sorted_tools:
        calls = data["calls"]
        s_rate = data["success_rate"]
        avg_ms = data["avg_ms"]
        max_ms = data["max_ms"]
        avg_ram = data["avg_mem_kb"]
        lines.append(
            f"| `{t_name}` | {calls:,} | {s_rate}% | {avg_ms} ms | {max_ms} ms | {avg_ram} KB |"
        )

    errors = metrics.get("recent_errors", [])
    if errors:
        lines.extend(
            [
                "",
                "## ⚠️ 3. 直近のエラーログ一覧 (最新 20 件)",
                "",
                "| 発生日時 (UTC) | サーバー | 対象 | エラー内容 |",
                "| :--- | :--- | :--- | :--- |",
            ]
        )
        for err in errors:
            ts = err.get("timestamp", "")
            srv = err.get("server", "")
            nm = err.get("name", "")
            msg = err.get("error", "").replace("\n", " ")[:80]
            lines.append(f"| `{ts}` | `{srv}` | `{nm}` | `{msg}` |")

    lines.append("")
    return "\n".join(lines)


def export_mcp_report_file(metrics: Dict[str, Any]) -> str:
    """Exports rendered Markdown report to outputs/evaluations/mcp_usage_report.md."""
    out_dir = os.path.join(WORKSPACE_DIR, "outputs", "evaluations")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "mcp_usage_report.md")
    content = render_mcp_markdown_report(metrics)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)
    return out_path


def main() -> None:
    """CLI entrypoint for MCP usage analytics."""
    parser = argparse.ArgumentParser(description="MCP Performance & Usage Analytics")
    parser.add_argument("--server", type=str, help="Filter by server name")
    parser.add_argument(
        "--json", action="store_true", help="Output raw metrics as JSON"
    )
    parser.add_argument(
        "--export",
        action="store_true",
        help="Export Markdown report to outputs/evaluations/",
    )
    args = parser.parse_args()

    records = load_mcp_logs(server_filter=args.server)
    metrics = compute_mcp_metrics(records)

    if args.json:
        print(json.dumps(metrics, ensure_ascii=False, indent=2))
        return

    report = render_mcp_markdown_report(metrics)
    print(report)

    if args.export or True:
        path = export_mcp_report_file(metrics)
        sys.stderr.write(f"[MCP-ANALYTICS] Exported report to {path}\n")


if __name__ == "__main__":
    main()
