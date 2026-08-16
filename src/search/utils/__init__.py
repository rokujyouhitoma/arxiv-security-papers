#!/usr/bin/env python3
"""
Search Utilities Subpackage (Observability, Profiling, and Document Parsing).
"""

import re

from .profiler import (
    ExecutionMetrics,
    ExecutionProfiler,
    analyze_bytecode,
    benchmark_function,
    profile_function,
)


def extract_abstract_from_okf(content: str) -> str:
    """Extracts raw abstract text from OKF markdown content."""
    m = re.search(r"###\s*Abstract[^\n]*\n+((?:>[^\n]*\n*)+)", content, re.IGNORECASE)
    if m:
        lines = [
            line.lstrip(">").strip() for line in m.group(1).splitlines() if line.strip()
        ]
        return " ".join(lines).strip()

    quotes = re.findall(r"^>\s*(.+)$", content, flags=re.MULTILINE)
    if quotes:
        return " ".join(quotes).strip()

    return ""


__all__ = [
    "ExecutionMetrics",
    "ExecutionProfiler",
    "analyze_bytecode",
    "benchmark_function",
    "extract_abstract_from_okf",
    "profile_function",
]
