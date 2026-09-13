#!/usr/bin/env python3
"""Comprehensive test suite for Packrat PEG W3C Turtle 1.1 Parser."""

import pytest

from ontology.turtle_parser import (
    RDF_TYPE_IRI,
    TurtleDocument,
    TurtlePEGParser,
    TurtleTerm,
    TurtleTriple,
    parse_turtle,
)


def test_basic_triple_and_prefixes() -> None:
    ttl = """
    @prefix sec: <https://w3id.org/security#> .
    @prefix cti: <https://w3id.org/cti#> .

    sec:Paper123 cti:analyzes sec:Malware456 .
    """
    parser = TurtlePEGParser()
    doc = parser.parse(ttl)
    assert isinstance(doc, TurtleDocument)
    assert doc.prefixes["sec"] == "https://w3id.org/security#"
    assert doc.prefixes["cti"] == "https://w3id.org/cti#"
    assert len(doc.triples) == 1

    t = doc.triples[0]
    assert isinstance(t, TurtleTriple)
    assert t.subject == "sec:Paper123"
    assert t.predicate == "cti:analyzes"
    assert t.object == "sec:Malware456"
    assert t.term is not None and isinstance(t.term, TurtleTerm)

    # IRI Resolution
    assert doc.resolve_iri(t.subject) == "https://w3id.org/security#Paper123"
    assert doc.resolve_iri(t.predicate) == "https://w3id.org/cti#analyzes"
    assert doc.resolve_iri(t.object) == "https://w3id.org/security#Malware456"


def test_sparql_style_prefix_and_base() -> None:
    ttl = """
    PREFIX ex: <http://example.org/>
    BASE <http://example.org/base/>

    <relative1> ex:prop <relative2> .
    """
    doc = parse_turtle(ttl)
    assert doc.prefixes["ex"] == "http://example.org/"
    assert doc.base_uri == "http://example.org/base/"

    assert len(doc.triples) == 1
    t = doc.triples[0]
    assert doc.resolve_iri(t.subject) == "http://example.org/base/relative1"
    assert doc.resolve_iri(t.predicate) == "http://example.org/prop"
    assert doc.resolve_iri(t.object) == "http://example.org/base/relative2"


def test_rdf_type_a_keyword() -> None:
    ttl = """
    @prefix sec: <https://w3id.org/security#> .
    sec:CVE-2024-1234 a sec:Vulnerability .
    """
    doc = parse_turtle(ttl)
    assert len(doc.triples) == 1
    t = doc.triples[0]
    assert t.predicate == RDF_TYPE_IRI
    assert doc.resolve_iri("a") == RDF_TYPE_IRI


def test_predicate_semicolon_and_comma_expansion() -> None:
    ttl = """
    @prefix sec: <https://w3id.org/security#> .
    @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

    sec:APT29 a sec:ThreatActor ;
              rdfs:label "APT29", "Cozy Bear" ;
              sec:uses sec:Malware1, sec:Malware2 ;
              sec:origin "Russia" ;
              .
    """
    doc = parse_turtle(ttl)
    # Expected triples:
    # 1: APT29 a ThreatActor
    # 2: APT29 label "APT29"
    # 3: APT29 label "Cozy Bear"
    # 4: APT29 uses Malware1
    # 5: APT29 uses Malware2
    # 6: APT29 origin "Russia"
    assert len(doc.triples) == 6

    labels = [t.object for t in doc.triples if t.predicate == "rdfs:label"]
    assert set(labels) == {"APT29", "Cozy Bear"}

    uses = [t.object for t in doc.triples if t.predicate == "sec:uses"]
    assert set(uses) == {"sec:Malware1", "sec:Malware2"}


def test_literals_datatypes_and_lang() -> None:
    ttl = """
    @prefix ex: <http://example.org/> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

    ex:item1 ex:title "Security Analysis"@en ;
             ex:desc "日本語解説"@ja ;
             ex:count 42 ;
             ex:ratio 3.1415 ;
             ex:active true ;
             ex:date "2026-09-14"^^xsd:date .
    """
    doc = parse_turtle(ttl)
    assert len(doc.triples) == 6

    term_map = {t.predicate: t.term for t in doc.triples}
    for term in term_map.values():
        assert term is not None

    title_term = term_map["ex:title"]
    desc_term = term_map["ex:desc"]
    count_term = term_map["ex:count"]
    ratio_term = term_map["ex:ratio"]
    active_term = term_map["ex:active"]
    date_term = term_map["ex:date"]

    assert title_term is not None and title_term.language == "en"
    assert title_term.value == "Security Analysis"
    assert desc_term is not None and desc_term.language == "ja"

    assert count_term is not None and count_term.value == 42
    assert count_term.datatype == "http://www.w3.org/2001/XMLSchema#integer"
    assert ratio_term is not None and abs(float(ratio_term.value) - 3.1415) < 1e-6

    assert active_term is not None and active_term.value is True

    assert date_term is not None and date_term.datatype == "xsd:date"
    assert date_term.value == "2026-09-14"


def test_blank_nodes_and_comments() -> None:
    ttl = """
    # Leading comment
    @prefix sec: <https://w3id.org/security#> . # Inline comment

    # Triple with named blank node
    _:b1 sec:target sec:AssetA .

    # Triple with anonymous blank node
    [] sec:target sec:AssetB .
    """
    doc = parse_turtle(ttl)
    assert len(doc.triples) == 2
    assert doc.triples[0].subject == "_:b1"
    assert doc.triples[1].subject == "_:bnode_anon"


def test_to_triples_export() -> None:
    ttl = """
    <http://s> <http://p> "o" .
    """
    doc = parse_turtle(ttl)
    tuples = doc.to_triples()
    assert tuples == [("http://s", "http://p", "o")]


def test_syntax_error_handling() -> None:
    invalid_ttl = "sec:Paper without predicate or dot"
    with pytest.raises(ValueError) as excinfo:
        parse_turtle(invalid_ttl)
    assert "Turtle syntax error" in str(excinfo.value)
