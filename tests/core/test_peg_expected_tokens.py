"""
Comprehensive test suite for PEG expected tokens tracking and typo diagnostics.
Verifies PEGSyntaxError.expected tuple and Levenshtein-based suggestion hints.
"""

import pytest

from core.structures.peg import (
    Choice,
    PEGSyntaxError,
    Regex,
    _diagnose_syntax_anomaly,
    _humanize_token,
    _levenshtein,
)


def test_humanize_token() -> None:
    assert _humanize_token(r"(?i)\bSELECT\b") == "SELECT"
    assert _humanize_token(r"(?i)\binsert\b") == "INSERT"
    assert _humanize_token("foobar") == "foobar"


def test_levenshtein_distance() -> None:
    assert _levenshtein("", "") == 0
    assert _levenshtein("a", "") == 1
    assert _levenshtein("kitten", "sitting") == 3
    assert _levenshtein("SELECT", "SELCT") == 1
    assert _levenshtein("commit", "comit") == 1
    assert _levenshtein("ROLLBACK", "ROLBACk") == 1


def test_peg_expected_tokens_tracking() -> None:
    # A simple choice parser: 'SELECT' or 'INSERT' or 'UPDATE'
    parser = Choice(
        Regex(r"(?i)\bSELECT\b"),
        Regex(r"(?i)\bINSERT\b"),
        Regex(r"(?i)\bUPDATE\b"),
    )

    with pytest.raises(PEGSyntaxError) as exc_info:
        parser.parse("DELETE")

    err = exc_info.value
    # Check expected attribute
    assert isinstance(err.expected, tuple)
    assert "SELECT" in err.expected
    assert "INSERT" in err.expected
    assert "UPDATE" in err.expected


def test_peg_typo_suggestion_in_error() -> None:
    parser = Choice(
        Regex(r"(?i)\bSELECT\b"),
        Regex(r"(?i)\bINSERT\b"),
    )

    with pytest.raises(PEGSyntaxError) as exc_info:
        parser.parse("SELCT * FROM table")

    err = exc_info.value
    assert err.hint is not None
    assert "Did you mean 'SELECT' instead of 'SELCT'?" in err.hint
    assert "Diagnosis: Did you mean 'SELECT' instead of 'SELCT'?" in str(err)


def test_peg_diagnose_precedence_quotes_and_brackets() -> None:
    # Unclosed quote takes precedence
    text = "SELECT 'hello from table"
    hint = _diagnose_syntax_anomaly(text, 0, {"SELECT"})
    assert hint is not None
    assert "unclosed string literal" in hint

    # Unmatched bracket
    text_bracket = "SELECT (id, name from table"
    hint_bracket = _diagnose_syntax_anomaly(text_bracket, 0, {"SELECT"})
    assert hint_bracket is not None
    assert "unclosed bracket" in hint_bracket.lower()
