#!/usr/bin/env python3
"""
Unit Tests for PEG-based EnterpriseQueryParser.
Validates plain terms, field targeting, phrases, modifiers, boolean operations,
nested parenthesis expressions, and fallback resilience.
Conforms to DSN-25 Phase 1 specification.
"""

import pytest

from search.query.query_parser import EnterpriseQueryParser, QueryContext


@pytest.fixture
def parser() -> EnterpriseQueryParser:
    return EnterpriseQueryParser()


def test_plain_terms_and_prefixes(parser: EnterpriseQueryParser) -> None:
    clauses = parser.parse("ransomware malware* APT~1")
    assert len(clauses) == 3
    assert clauses[0].term == "ransomware"
    assert not clauses[0].is_prefix
    assert not clauses[0].is_fuzzy

    assert clauses[1].term == "malware"
    assert clauses[1].is_prefix

    assert clauses[2].term == "APT"
    assert clauses[2].is_fuzzy
    assert clauses[2].fuzzy_distance == 1


def test_field_specific_targeting(parser: EnterpriseQueryParser) -> None:
    clauses = parser.parse("title:ransomware author:Nakatani tag:crypto")
    assert len(clauses) == 3
    assert clauses[0].field == "title"
    assert clauses[0].term == "ransomware"

    assert clauses[1].field == "author"
    assert clauses[1].term == "Nakatani"

    assert clauses[2].field == "tag"
    assert clauses[2].term == "crypto"


def test_phrase_and_slop(parser: EnterpriseQueryParser) -> None:
    clauses = parser.parse('"zero day exploit" "supply chain"~2')
    assert len(clauses) == 2
    assert clauses[0].is_phrase
    assert clauses[0].term == "zero day exploit"
    assert clauses[0].phrase_slop == 0

    assert clauses[1].is_phrase
    assert clauses[1].term == "supply chain"
    assert clauses[1].phrase_slop == 2


def test_modifiers_plus_minus_not(parser: EnterpriseQueryParser) -> None:
    clauses = parser.parse("+title:malware -author:eve NOT crypto")
    assert len(clauses) == 3
    assert clauses[0].is_required
    assert not clauses[0].is_prohibited

    assert not clauses[1].is_required
    assert clauses[1].is_prohibited

    assert not clauses[2].is_required
    assert clauses[2].is_prohibited
    assert clauses[2].term == "crypto"


def test_nested_parentheses_disjunction(parser: EnterpriseQueryParser) -> None:
    query = "(title:ransomware OR title:malware) AND -(tag:crypto OR author:smith)"
    clauses = parser.parse(query)
    assert len(clauses) >= 1

    # Flatten should retrieve all underlying terms
    flat = []
    for c in clauses:
        flat.extend(c.flatten())
    terms = {c.term for c in flat}
    assert "ransomware" in terms
    assert "malware" in terms
    assert "crypto" in terms
    assert "smith" in terms

    # Check prohibited status propagated
    prohibited = [c for c in flat if c.is_prohibited]
    assert len(prohibited) >= 2


def test_field_with_nested_parentheses(parser: EnterpriseQueryParser) -> None:
    query = "author:(Alice OR Bob)"
    clauses = parser.parse(query)
    flat = []
    for c in clauses:
        flat.extend(c.flatten())
    assert len(flat) == 2
    assert flat[0].field == "author"
    assert flat[1].field == "author"
    names = {flat[0].term, flat[1].term}
    assert names == {"Alice", "Bob"}


def test_deeply_nested_boolean_expression(parser: EnterpriseQueryParser) -> None:
    query = "((A OR B) AND (C OR D))"
    clauses = parser.parse(query)
    assert len(clauses) > 0
    flat = [fc for c in clauses for fc in c.flatten()]
    assert {c.term for c in flat} == {"A", "B", "C", "D"}


def test_unclosed_parenthesis_fallback(parser: EnterpriseQueryParser) -> None:
    # Malformed unclosed parenthesis should gracefully fall back to token scanning
    query = "title:malware (unclosed tag:crypto"
    clauses = parser.parse(query)
    assert len(clauses) >= 2
    fields = {c.field for c in clauses if c.field}
    assert "title" in fields
    assert "tag" in fields


def test_query_context_creation(parser: EnterpriseQueryParser) -> None:
    ctx: QueryContext = parser.create_context(
        "(title:ransomware OR title:malware) +author:Nakatani"
    )
    assert ctx.has_field_constraints
    assert "title" in ctx.target_fields
    assert "author" in ctx.target_fields
    assert "ransomware" in ctx.expanded_tokens
    assert "malware" in ctx.expanded_tokens
    assert "nakatani" in ctx.expanded_tokens
    assert len(ctx.required_clauses) > 0
