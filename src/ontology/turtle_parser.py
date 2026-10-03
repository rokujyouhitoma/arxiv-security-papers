#!/usr/bin/env python3
"""
Backward compatibility shim for ontology.turtle.parser.
Canonical location: src/ontology/turtle/parser.py
"""

from ontology.turtle.parser import (
    RDF_TYPE_IRI,
    TurtleDocument,
    TurtlePEGParser,
    TurtleTerm,
    TurtleTriple,
    _apply_turtle_statement,
    _extract_datatype_uri,
    _flatten_po_list,
    _format_turtle_term,
    _resolve_prefixed_iri,
    _resolve_relative_or_base,
    _unescape_turtle_str,
    parse_turtle,
)

__all__ = [
    "RDF_TYPE_IRI",
    "TurtleDocument",
    "TurtlePEGParser",
    "TurtleTerm",
    "TurtleTriple",
    "_apply_turtle_statement",
    "_extract_datatype_uri",
    "_flatten_po_list",
    "_format_turtle_term",
    "_resolve_prefixed_iri",
    "_resolve_relative_or_base",
    "_unescape_turtle_str",
    "parse_turtle",
]
