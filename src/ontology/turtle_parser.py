#!/usr/bin/env python3
"""Pure-Python W3C RDF 1.1 Turtle (.ttl) Ingest Parser using Packrat PEG.

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

from core.structures.peg import (
    Choice,
    Lit,
    Opt,
    Parser,
    PEGSyntaxError,
    Reg,
    Seq,
    ZeroOrMore,
)

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


def _tok(parser: Parser[Any]) -> Parser[Any]:
    """Wraps a parser to skip trailing whitespace and comments."""
    ws = Reg(r"(\s+|#[^\r\n]*)*")

    def _extract_first(r: List[Any]) -> Any:
        return r[0]

    return Seq(parser, ws).map(_extract_first)


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


def _make_str_literal(vals: List[Any]) -> TurtleTerm:
    raw_text = _unescape_turtle_str(str(vals[0])[1:-1])
    suffix = vals[1]
    if not suffix:
        return TurtleTerm(raw_text, "literal")
    tag, val = suffix
    if tag == "@":
        return TurtleTerm(raw_text, "literal", language=str(val))
    if tag == "^^":
        return TurtleTerm(raw_text, "literal", datatype=_extract_datatype_uri(val))
    return TurtleTerm(raw_text, "literal")


def _build_literal_parsers() -> Parser[TurtleTerm]:
    """Constructs Turtle literal parsers (strings, numbers, booleans)."""
    str_token = Reg(r'"([^"\\]|\\.)*"')
    lang_tag = Seq(Lit("@"), Reg(r"[a-zA-Z]+(-[a-zA-Z0-9]+)*")).map(
        lambda r: ("@", str(r[1]))
    )
    dt_type = Seq(
        Lit("^^"),
        Choice(
            Reg(r"<([^>]*)>"),
            Reg(r"([a-zA-Z0-9_.-]*):([a-zA-Z0-9_.-]+)"),
        ),
    ).map(lambda r: ("^^", str(r[1])))

    full_str_lit = _tok(
        Seq(
            str_token,
            Opt(Choice(lang_tag, dt_type)),
        )
    ).map(_make_str_literal)

    bool_lit = Choice(_tok(Lit("true")), _tok(Lit("false"))).map(
        lambda r: TurtleTerm(
            r == "true",
            "literal",
            datatype="http://www.w3.org/2001/XMLSchema#boolean",
        )
    )

    float_lit = _tok(Reg(r"[+-]?[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?")).map(
        lambda r: TurtleTerm(
            float(r),
            "literal",
            datatype="http://www.w3.org/2001/XMLSchema#decimal",
        )
    )
    int_lit = _tok(Reg(r"[+-]?[0-9]+")).map(
        lambda r: TurtleTerm(
            int(r),
            "literal",
            datatype="http://www.w3.org/2001/XMLSchema#integer",
        )
    )

    return Choice(full_str_lit, bool_lit, float_lit, int_lit)


def _build_iri_parsers() -> Parser[TurtleTerm]:
    """Constructs IRI and Prefixed Name parsers."""
    full_iri = _tok(Reg(r"<([^>]*)>")).map(lambda r: TurtleTerm(str(r)[1:-1], "iri"))
    prefixed_name = _tok(Reg(r"([a-zA-Z0-9_-]*):([a-zA-Z0-9_.\-%]+)")).map(
        lambda r: TurtleTerm(str(r), "iri")
    )
    a_kw = _tok(Lit("a")).map(lambda _: TurtleTerm(RDF_TYPE_IRI, "iri"))
    return Choice(full_iri, prefixed_name, a_kw)


def _build_bnode_parsers() -> Parser[TurtleTerm]:
    """Constructs blank node parsers."""
    named_bnode = _tok(Reg(r"_:[a-zA-Z0-9_.-]+")).map(
        lambda r: TurtleTerm(str(r), "bnode")
    )
    empty_bnode = Seq(_tok(Lit("[")), _tok(Lit("]"))).map(
        lambda _: TurtleTerm("_:bnode_anon", "bnode")
    )
    return Choice(named_bnode, empty_bnode)


def _build_directive_parsers() -> Parser[Tuple[str, str, str]]:
    """Constructs @prefix, PREFIX, @base, BASE directive parsers."""
    p_id = Reg(r"([a-zA-Z0-9_-]*):")
    iri_val = _tok(Reg(r"<([^>]*)>")).map(lambda r: str(r)[1:-1])

    at_prefix = Seq(
        _tok(Lit("@prefix")),
        _tok(p_id),
        iri_val,
        _tok(Lit(".")),
    ).map(lambda r: ("prefix", str(r[1])[:-1], str(r[2])))

    sparql_prefix = Seq(
        _tok(Lit("PREFIX")),
        _tok(p_id),
        iri_val,
        Opt(_tok(Lit("."))),
    ).map(lambda r: ("prefix", str(r[1])[:-1], str(r[2])))

    at_base = Seq(
        _tok(Lit("@base")),
        iri_val,
        _tok(Lit(".")),
    ).map(lambda r: ("base", "", str(r[1])))

    sparql_base = Seq(
        _tok(Lit("BASE")),
        iri_val,
        Opt(_tok(Lit("."))),
    ).map(lambda r: ("base", "", str(r[1])))

    return Choice(at_prefix, sparql_prefix, at_base, sparql_base)


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


def _fold_obj_list(r: List[Any]) -> List[TurtleTerm]:
    first = cast(TurtleTerm, r[0])
    rest = [cast(TurtleTerm, item[1]) for item in cast(List[Any], r[1])]
    return [first] + rest


def _fold_po_list(r: List[Any]) -> List[Tuple[str, List[TurtleTerm]]]:
    first = cast(Tuple[str, List[TurtleTerm]], r[0])
    rest = [
        cast(Tuple[str, List[TurtleTerm]], item[1]) for item in cast(List[Any], r[1])
    ]
    return [first] + rest


class TurtlePEGParser:
    """Packrat PEG Parser for W3C Turtle 1.1 documents."""

    def __init__(self) -> None:
        self._grammar: Parser[Any] = self._build_grammar()

    def _build_grammar(self) -> Parser[Any]:
        """Assembles grammar rules into document parser."""
        directive = _build_directive_parsers()
        iri_term = _build_iri_parsers()
        bnode_term = _build_bnode_parsers()
        lit_term = _build_literal_parsers()

        subject = Choice(iri_term, bnode_term)
        predicate = iri_term
        obj = Choice(iri_term, bnode_term, lit_term)

        obj_list = Seq(obj, ZeroOrMore(Seq(_tok(Lit(",")), obj))).map(_fold_obj_list)
        po_pair = Seq(predicate, obj_list).map(
            lambda r: (str(r[0].value), cast(List[TurtleTerm], r[1]))
        )
        po_list = Seq(
            po_pair, ZeroOrMore(Seq(_tok(Lit(";")), po_pair)), Opt(_tok(Lit(";")))
        ).map(_fold_po_list)

        triple_stmt = Seq(subject, po_list, _tok(Lit("."))).map(
            lambda r: ("triples", str(r[0].value), r[1])
        )

        statement = Choice(directive, triple_stmt)
        leading_ws = Reg(r"(\s+|#[^\r\n]*)*")
        return Seq(leading_ws, ZeroOrMore(statement), leading_ws).map(lambda r: r[1])

    def parse(self, text: str) -> TurtleDocument:
        """Parses Turtle document text into TurtleDocument AST."""
        try:
            statements = cast(List[Any], self._grammar.parse(text))
        except PEGSyntaxError as exc:
            raise ValueError(
                f"Turtle syntax error at line {exc.line}, col {exc.col}: {exc.message}"
            ) from exc

        doc = TurtleDocument()
        for stmt in statements or []:
            self._apply_statement(doc, cast(Tuple[Any, ...], stmt))
        return doc

    def _apply_statement(self, doc: TurtleDocument, stmt: Tuple[Any, ...]) -> None:
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


def parse_turtle(text: str) -> TurtleDocument:
    """Convenience helper to parse W3C Turtle document text."""
    parser = TurtlePEGParser()
    return parser.parse(text)
