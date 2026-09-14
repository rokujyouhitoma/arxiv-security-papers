#!/usr/bin/env python3
"""Pure-Python W3C RDF 1.1 Turtle (.ttl) Ingest Parser.

Powered by DSN-25 Ahead-of-Time (AOT) Packrat PEG Compiler (grammars/turtle.peg).
Conforms to W3C Turtle 1.1 grammar specification:
- Directives: @prefix, PREFIX, @base, BASE
- Subjects / Predicates / Objects: IRIs, Prefixed Names (CURIEs), Blank Nodes,
  Literals (Strings, Language-tagged, Typed Literals, Numbers, Booleans),
  Keyword 'a' (rdf:type).
- Abbreviated syntax: Semicolon (;) predicate lists and comma (,) object lists.
- Anonymous blank node property lists [ ... ].
- Comments: # comments to end-of-line.

Zero external dependencies.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple, cast

from core.structures.peg import PEGSyntaxError

RDF_TYPE_IRI: str = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"


def _format_turtle_term(term: "TurtleTerm") -> str:
    if term.term_type == "iri":
        return f"<{term.value}>"
    if term.term_type == "bnode":
        return str(term.value)
    if term.language:
        return f'"{term.value}"@{term.language}'
    if term.datatype:
        return f'"{term.value}"^^<{term.datatype}>'
    return f'"{term.value}"'


@dataclass(frozen=True)
class TurtleTerm:
    """Represents an RDF Term extracted from Turtle."""

    value: Any
    term_type: str  # "iri", "bnode", "literal"
    datatype: Optional[str] = None
    language: Optional[str] = None

    def __repr__(self) -> str:
        return _format_turtle_term(self)


@dataclass(frozen=True)
class TurtleTriple:
    """Represents an RDF Triple (subject, predicate, object)."""

    subject: str
    predicate: str
    object: Any
    term: Optional[TurtleTerm] = None

    def to_tuple(self) -> Tuple[str, str, Any]:
        return (self.subject, self.predicate, self.object)


def _resolve_relative_or_base(term: str, base_uri: Optional[str]) -> str:
    if base_uri and not term.startswith(("http://", "https://", "urn:")):
        return f"{base_uri.rstrip('/')}/{term.lstrip('/')}"
    return term


def _resolve_prefixed_iri(term: str, prefixes: Dict[str, str]) -> str:
    if ":" not in term or term.startswith("_:"):
        return term
    prefix, local = term.split(":", 1)
    if prefix in prefixes:
        return f"{prefixes[prefix]}{local}"
    return term


@dataclass
class TurtleDocument:
    """Represents a parsed Turtle document containing prefixes and triples."""

    prefixes: Dict[str, str] = field(default_factory=dict)
    base_uri: Optional[str] = None
    triples: List[TurtleTriple] = field(default_factory=list)

    def resolve_iri(self, term: str) -> str:
        """Resolves a prefixed name or relative IRI against document prefixes."""
        if term == "a":
            return RDF_TYPE_IRI
        clean = term[1:-1] if term.startswith("<") and term.endswith(">") else term
        prefixed = _resolve_prefixed_iri(clean, self.prefixes)
        if prefixed != clean:
            return prefixed
        return _resolve_relative_or_base(clean, self.base_uri)

    def to_triples(self) -> List[Tuple[str, str, Any]]:
        """Returns triples as a list of 3-tuples (s, p, o)."""
        return [t.to_tuple() for t in self.triples]


def _unescape_turtle_str(s: str) -> str:
    """Unescapes standard Turtle escape sequences."""
    replacements = (
        (r"\t", "\t"),
        (r"\n", "\n"),
        (r"\r", "\r"),
        (r"\"", '"'),
        (r"\'", "'"),
        (r"\\", "\\"),
    )
    for old, new in replacements:
        s = s.replace(old, new)
    return s


def _extract_datatype_uri(val: Any) -> str:
    s_val = str(val)
    if s_val.startswith("<") and s_val.endswith(">"):
        return s_val[1:-1]
    return s_val


def _flatten_po_list(
    subject: str,
    po_list: List[Tuple[str, List[TurtleTerm]]],
) -> List[TurtleTriple]:
    """Flattens predicate-object pairs into individual TurtleTriple instances."""
    triples: List[TurtleTriple] = []
    for pred, obj_terms in po_list:
        for term in obj_terms:
            triples.append(
                TurtleTriple(
                    subject=subject,
                    predicate=pred,
                    object=term.value,
                    term=term,
                )
            )
    return triples


def _apply_turtle_statement(doc: TurtleDocument, stmt: Tuple[Any, ...]) -> None:
    """Applies a parsed directive or triple statement to the document."""
    kind = stmt[0]
    if kind == "prefix":
        doc.prefixes[str(stmt[1])] = str(stmt[2])
    elif kind == "base":
        doc.base_uri = str(stmt[2])
    elif kind == "triples":
        subj = str(stmt[1])
        po_list = cast(List[Tuple[str, List[TurtleTerm]]], stmt[2])
        doc.triples.extend(_flatten_po_list(subj, po_list))


class TurtlePEGParser:
    """Packrat PEG Parser for W3C Turtle 1.1 documents using AOT-compiled grammar."""

    def __init__(self) -> None:
        from ontology.generated_turtle_parser import TurtleParser

        self._parser = TurtleParser()

    def parse(self, text: str) -> TurtleDocument:
        """Parses Turtle document text into TurtleDocument AST."""
        try:
            res = self._parser.parse(text)
            if isinstance(res, TurtleDocument):
                return res
            return TurtleDocument()
        except PEGSyntaxError as exc:
            raise ValueError(
                f"Turtle syntax error at line {exc.line}, col {exc.col}: {exc.message}"
            ) from exc


def parse_turtle(text: str) -> TurtleDocument:
    """Convenience helper to parse W3C Turtle document text."""
    parser = TurtlePEGParser()
    return parser.parse(text)
