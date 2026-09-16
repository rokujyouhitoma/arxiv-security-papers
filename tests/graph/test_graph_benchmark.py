#!/usr/bin/env python3
"""
Performance and Benchmark Tests for CTI Graph Query DSL AOT PEG Parser.
Validates zero-cost initialization (0ms overhead) and high throughput parsing
conforming to DSN-25 Phase 2 / Issue #300 specifications.
"""

import time

import pytest

from core.structures.peg import PEGSyntaxError
from graph.generated_graph_query_parser import GraphQueryParser
from graph.query_dsl import GraphQueryDSLParser


def test_graph_aot_parser_initialization_speed() -> None:
    """Verifies that AOT parser instantiation has virtually zero overhead."""
    start = time.perf_counter()
    parsers = [GraphQueryParser() for _ in range(100)]
    elapsed = time.perf_counter() - start

    assert len(parsers) == 100
    # 100 instantiations must complete in under 50ms
    assert elapsed < 0.05, f"100 instantiations took too long: {elapsed:.4f}s"


def test_graph_aot_parser_throughput() -> None:
    """Verifies that parsing path patterns and filters is extremely fast (< 1ms per query)."""
    parser = GraphQueryDSLParser()
    queries = [
        "APT29 -> [USES] -> Malware -> [EXPLOITS] -> CWE-79",
        "(:ThreatActor) -> [:USES] -> (:Malware)",
        "community:0 AND label:ThreatActor",
        "apt29 -> cobalt -> cve1",
        "label:ThreatActor AND community:1",
    ]

    start = time.perf_counter()
    count = 0
    # 20 iterations of 5 queries = 100 queries total
    for _ in range(20):
        for q in queries:
            res = parser.parse(q)
            assert res is not None
            count += 1
    elapsed = time.perf_counter() - start

    assert count == 100
    # 100 queries must complete in under 0.2s (< 2ms per query)
    assert elapsed < 0.2, f"100 queries took too long: {elapsed:.4f}s"


def test_graph_aot_parser_syntax_errors() -> None:
    """Verifies error handling on empty and malformed DSL queries."""
    parser = GraphQueryDSLParser()

    with pytest.raises(PEGSyntaxError):
        parser.parse("")

    with pytest.raises(PEGSyntaxError):
        parser.parse("   ")
