#!/usr/bin/env python3
"""Benchmark and performance verification for AOT-compiled Search Query Parser."""

import time

from search.query.generated_search_query_parser import SearchQueryParser
from search.query.query_parser import EnterpriseQueryParser


def test_query_aot_parser_initialization_speed() -> None:
    """Verifies that AOT parser initializes rapidly without dynamic combinator build overhead."""
    start = time.perf_counter()
    parsers = [SearchQueryParser() for _ in range(100)]
    elapsed = time.perf_counter() - start

    assert len(parsers) == 100
    # 100 parser instantiations should take well under 0.25 seconds
    assert elapsed < 0.25


def test_query_aot_parser_throughput() -> None:
    """Verifies high-throughput parsing of complex nested boolean search queries."""
    complex_query = (
        '(title:"ransomware attack"~2 OR tag:malware) '
        "AND +(author:Nakatani OR author:Alice) "
        "-content:deprecated NOT crypto"
    )
    parser = EnterpriseQueryParser()

    start = time.perf_counter()
    for _ in range(100):
        clauses = parser.parse(complex_query)
        assert len(clauses) > 0
    elapsed = time.perf_counter() - start

    # 100 parse runs should take well under 1.0 second (< 10ms per parse)
    assert elapsed < 1.0


def test_query_aot_parser_delegation() -> None:
    """Verifies that EnterpriseQueryParser correctly delegates to AOT SearchQueryParser."""
    raw_query = 'title:malware* "zero day"~1 +author:smith'
    qp = EnterpriseQueryParser()
    clauses = qp.parse(raw_query)

    assert len(clauses) == 3
    assert clauses[0].field == "title"
    assert clauses[0].term == "malware"
    assert clauses[0].is_prefix

    assert clauses[1].is_phrase
    assert clauses[1].term == "zero day"
    assert clauses[1].phrase_slop == 1

    assert clauses[2].is_required
    assert clauses[2].field == "author"
    assert clauses[2].term == "smith"
