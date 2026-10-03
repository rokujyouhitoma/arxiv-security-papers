#!/usr/bin/env python3
"""
Unit tests for Cut operator (^), Resilient / Tolerant parsing, and Intelligent syntax diagnostics.
Verifies:
1. Cut operator commits evaluation, pruning subsequent Choice alternatives.
2. Binary operator ^ automatically constructs Sequence(e1, Cut(), e2).
3. parse_resilient continues past syntax errors using panic mode synchronization.
4. Intelligent diagnostics identify unclosed quotes and bracket mismatches.
"""

import pytest

from core.structures.peg import Choice, Cut, Lit, PEGSyntaxError, Reg, Seq


def test_cut_operator_prunes_backtracking() -> None:
    """Verifies that reaching a Cut operator prevents Choice from trying later alternatives."""
    # Choice 1: "LET" ^ Identifier "=" Expression
    # Choice 2: "LET" Identifier (a different legacy syntax)
    let_stmt_cut = Seq(Lit("LET "), Cut(), Reg(r"[a-z]+"), Lit(" = "), Reg(r"\d+"))
    legacy_let = Seq(Lit("LET "), Reg(r"[a-z]+"))
    parser = Choice(let_stmt_cut, legacy_let)

    # Valid let statement with cut passes
    res = parser.parse("LET x = 42")
    assert res == ["LET ", "x", " = ", "42"]

    # Malformed let statement: starts with "LET " then reaches Cut.
    # Following tokens fail ("x +" instead of "x = 42").
    # Choice MUST NOT backtrack to legacy_let; it must fail at the cut branch!
    with pytest.raises(PEGSyntaxError):
        parser.parse("LET x + 10")


def test_cut_binary_operator_syntax() -> None:
    """Verifies that (p1 ^ p2) behaves as Sequence(p1, Cut(), p2)."""
    p = (Lit("CMD:") ^ Lit("RUN")) / Lit("CMD:FALLBACK")

    # Success case
    assert p.parse("CMD:RUN") == ["CMD:", "RUN"]

    # Fails after CMD: because of Cut; does not fall back to CMD:FALLBACK
    with pytest.raises(PEGSyntaxError):
        p.parse("CMD:STOP")

    # If CMD: does not match at all, other choice alternative works
    p2 = (Lit("FOO:") ^ Lit("BAR")) / Lit("BAZ")
    assert p2.parse("BAZ") == "BAZ"


def test_parse_resilient_recovers_after_errors() -> None:
    """Verifies parse_resilient skips broken segments to extract subsequent valid constructs."""
    num_parser = Reg(r"\d+").map(int)

    # Input contains syntax error on first segment, but valid segment after semicolon
    broken_text = "error_token; 12345"
    val, errors = num_parser.parse_resilient(broken_text, sync_tokens={";"})

    assert len(errors) == 1
    assert val == 12345


def test_intelligent_diagnostics_unclosed_quotes() -> None:
    """Verifies heuristic diagnostic detects unclosed string literals."""
    parser = Lit("key")
    text = "key 'unterminated string literal"

    with pytest.raises(PEGSyntaxError) as exc_info:
        parser.parse(text)

    msg = str(exc_info.value)
    assert "Diagnosis:" in msg
    assert "unclosed string literal" in msg


def test_intelligent_diagnostics_unclosed_bracket() -> None:
    """Verifies heuristic diagnostic detects unclosed bracket mismatch."""
    parser = Lit("func")
    text = "func (1 + 2"

    with pytest.raises(PEGSyntaxError) as exc_info:
        parser.parse(text)

    msg = str(exc_info.value)
    assert "Diagnosis:" in msg
    assert "Unclosed bracket '('" in msg


def test_intelligent_diagnostics_unmatched_closing_bracket() -> None:
    """Verifies heuristic diagnostic detects extra unmatched closing bracket."""
    parser = Lit("func")
    text = "func 1 + 2)"

    with pytest.raises(PEGSyntaxError) as exc_info:
        parser.parse(text)

    msg = str(exc_info.value)
    assert "Diagnosis:" in msg
    assert "Unmatched closing bracket ')'" in msg
