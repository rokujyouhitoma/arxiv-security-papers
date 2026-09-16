#!/usr/bin/env python3
"""Benchmark and performance verification for AOT-compiled Search Query Parser."""

import time

from search.query.generated_search_query_parser import SearchQueryParser
from search.query.query_parser import (
    EnterpriseQueryParser,
    QueryParser,
    clear_search_query_cache,
)


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


def test_query_lru_cache_cold_vs_warm_throughput() -> None:
    """Verifies that LRU cache provides dramatic speedup for repeated search query parsing."""
    query = (
        '(title:"ransomware attack"~2 OR tag:malware) '
        "AND +(author:Nakatani OR author:Alice) "
        "-content:deprecated NOT crypto"
    )

    clear_search_query_cache()
    parser = QueryParser()

    # Cold parse (first execution)
    t0 = time.perf_counter()
    cold_clauses = parser.parse(query)
    cold_elapsed = time.perf_counter() - t0
    assert len(cold_clauses) > 0

    # Warm parses (1,000 cached hits)
    t1 = time.perf_counter()
    for _ in range(1000):
        warm_clauses = parser.parse(query)
        assert len(warm_clauses) == len(cold_clauses)
    warm_elapsed = time.perf_counter() - t1

    # 1,000 warm hits should complete in less than 0.05 seconds (< 50 microseconds per hit)
    assert warm_elapsed < 0.05
    # Average warm parse should be significantly faster than cold parse
    avg_warm = warm_elapsed / 1000.0
    assert avg_warm < cold_elapsed


def test_query_parser_cache_clear_integrity() -> None:
    """Verifies that search query cache clearing safely purges entries and subsequent parsing succeeds."""
    q = 'title:"supply chain attack" +tag:cybersecurity'
    parser = QueryParser()
    c1 = parser.parse(q)
    assert len(c1) == 2

    clear_search_query_cache()

    c2 = parser.parse(q)
    assert len(c2) == 2
    assert c2[0].term == "supply chain attack"


def test_query_cache_mutation_defense() -> None:
    """Verifies that mutating the returned list does not corrupt cached entries."""
    q = "author:Alice +title:Security"
    parser = QueryParser()

    c1 = parser.parse(q)
    assert len(c1) == 2

    # Mutate returned list
    c1.clear()
    assert len(c1) == 0

    # Next call should return complete fresh list from cache
    c2 = parser.parse(q)
    assert len(c2) == 2
    assert c2[0].field == "author"
