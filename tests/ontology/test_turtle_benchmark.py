#!/usr/bin/env python3
"""Benchmark and performance verification for AOT-compiled W3C Turtle 1.1 Parser."""

import time

from ontology.generated_turtle_parser import TurtleParser
from ontology.turtle_parser import TurtleDocument, TurtlePEGParser, parse_turtle


def test_turtle_aot_parser_initialization_speed() -> None:
    """Verifies that AOT parser initializes rapidly without dynamic combinator build overhead."""
    start = time.perf_counter()
    parsers = [TurtleParser() for _ in range(50)]
    elapsed = time.perf_counter() - start

    assert len(parsers) == 50
    # 50 parser instantiations should take well under 0.25 seconds
    assert elapsed < 0.25


def test_turtle_aot_parser_throughput() -> None:
    """Verifies high throughput parsing of multi-triple Turtle documents."""
    ttl_triples = "\n".join(
        f"sec:Paper{i} cti:analyzes sec:Malware{i} ; cti:published '2026-09-{i:02d}'^^xsd:date ."
        for i in range(1, 101)
    )
    ttl_doc = f"""
    @prefix sec: <https://w3id.org/security#> .
    @prefix cti: <https://w3id.org/cti#> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

    {ttl_triples}
    """

    parser = TurtlePEGParser()
    start = time.perf_counter()
    doc = parser.parse(ttl_doc)
    elapsed = time.perf_counter() - start

    assert isinstance(doc, TurtleDocument)
    assert len(doc.prefixes) == 3
    # 100 statements * 2 triples per statement = 200 triples
    assert len(doc.triples) == 200
    assert elapsed < 1.0  # Must parse 200 triples in less than 1.0 second


def test_turtle_aot_parser_convenience_function() -> None:
    """Verifies that top-level parse_turtle function delegates seamlessly to AOT parser."""
    raw = """
    PREFIX sec: <https://w3id.org/security#>
    BASE <http://example.org/>

    <node1> a sec:Vulnerability ;
            sec:severity "CRITICAL"@en .
    """
    doc = parse_turtle(raw)
    assert doc.base_uri == "http://example.org/"
    assert len(doc.triples) == 2
    assert (
        doc.resolve_iri(doc.triples[0].predicate)
        == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    )
