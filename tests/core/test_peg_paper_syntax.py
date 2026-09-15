"""
Unit and integration tests for Bryan Ford POPL '04 PEG Grammar Alignment (Issue #298, DSN-25).
Verifies:
- <- (LEFTARROW) rule definitions
- Native [...] and [^...] character classes
- . (DOT / AnyChar) combinator
- AOT compilation of paper-syntax grammars
- Backward compatibility of = rule definitions
- Arithmetic calculation and Boolean query execution with new syntax
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict

import pytest

from core.structures.peg import Class, Dot, PEGSyntaxError
from core.structures.peg_compiler.ast_nodes import AnyCharExpr, CharClassExpr, LitExpr
from core.structures.peg_compiler.cli import compile_grammar_to_code
from core.structures.peg_compiler.meta_grammar import MetaGrammarParser


def _get_grammars_dir() -> Path:
    return Path(__file__).resolve().parent.parent.parent / "grammars"


def test_any_char_combinator() -> None:
    """Verifies that AnyChar / Dot() matches any character and fails on EOF."""
    dot = Dot()
    assert dot.parse("a") == "a"
    assert dot.parse("9") == "9"
    assert dot.parse("@") == "@"
    assert dot.parse(" ") == " "
    assert dot.parse("\n") == "\n"

    with pytest.raises(PEGSyntaxError):
        dot.parse("")

    with pytest.raises(PEGSyntaxError):
        dot.parse("ab")  # unconsumed trailing character


def test_char_class_combinator_ranges_and_singles() -> None:
    """Verifies that CharClass / Class() correctly matches ranges, singles, and inverted classes."""
    digits = Class("0-9")
    assert digits.parse("0") == "0"
    assert digits.parse("5") == "5"
    assert digits.parse("9") == "9"

    with pytest.raises(PEGSyntaxError):
        digits.parse("a")

    with pytest.raises(PEGSyntaxError):
        digits.parse("-")

    ident_char = Class("a-zA-Z_")
    assert ident_char.parse("a") == "a"
    assert ident_char.parse("Z") == "Z"
    assert ident_char.parse("_") == "_"

    with pytest.raises(PEGSyntaxError):
        ident_char.parse("1")

    ops = Class("+-")
    assert ops.parse("+") == "+"
    assert ops.parse("-") == "-"

    with pytest.raises(PEGSyntaxError):
        ops.parse("*")


def test_char_class_inverted() -> None:
    """Verifies that inverted CharClass [^...] correctly matches non-members."""
    non_digit = Class("0-9", inverted=True)
    assert non_digit.parse("a") == "a"
    assert non_digit.parse("_") == "_"
    assert non_digit.parse("!") == "!"

    with pytest.raises(PEGSyntaxError):
        non_digit.parse("4")


def test_char_class_escapes() -> None:
    """Verifies that CharClass parses escape sequences correctly."""
    whitespaces = Class(r"\t\n\r ")
    assert whitespaces.parse("\t") == "\t"
    assert whitespaces.parse("\n") == "\n"
    assert whitespaces.parse("\r") == "\r"
    assert whitespaces.parse(" ") == " "

    with pytest.raises(PEGSyntaxError):
        whitespaces.parse("x")

    special = Class(r"\-\]")
    assert special.parse("-") == "-"
    assert special.parse("]") == "]"

    with pytest.raises(PEGSyntaxError):
        special.parse("a")


def test_meta_grammar_parses_leftarrow_and_paper_tokens() -> None:
    """Verifies that MetaGrammarParser parses <-, [...], [^...], and . into AST."""
    parser = MetaGrammarParser()
    grammar_src = """
    grammar FordSyntaxDemo

    entry <- digit / non_digit / any_token / literal
    digit <- [0-9]
    non_digit <- [^0-9]
    any_token <- .
    literal <- "hello"
    """
    g_def = parser.parse(grammar_src)
    assert g_def.name == "FordSyntaxDemo"
    assert len(g_def.rules) == 5

    rules_by_name = {r.name: r.expr for r in g_def.rules}

    digit_expr = rules_by_name["digit"]
    assert isinstance(digit_expr, CharClassExpr)
    assert digit_expr.raw_spec == "0-9"
    assert not digit_expr.inverted

    non_digit_expr = rules_by_name["non_digit"]
    assert isinstance(non_digit_expr, CharClassExpr)
    assert non_digit_expr.raw_spec == "0-9"
    assert non_digit_expr.inverted

    any_expr = rules_by_name["any_token"]
    assert isinstance(any_expr, AnyCharExpr)

    lit_expr = rules_by_name["literal"]
    assert isinstance(lit_expr, LitExpr)
    assert lit_expr.value == "hello"


def test_meta_grammar_backward_compatibility_equals_sign() -> None:
    """Verifies that MetaGrammarParser still accepts legacy = rule syntax."""
    parser = MetaGrammarParser()
    grammar_src = """
    grammar LegacyCompat
    rule1 = "abc"
    rule2 <- "def"
    """
    g_def = parser.parse(grammar_src)
    assert len(g_def.rules) == 2
    assert g_def.rules[0].name == "rule1"
    assert g_def.rules[1].name == "rule2"


def test_aot_compiled_paper_grammar_execution() -> None:
    """Compiles a grammar using Bryan Ford paper syntax and executes the resulting parser."""
    grammar_src = """
    grammar PaperRuntimeTest

    phrase <- w:token ws p:punct { return {"word": w, "punct": p} }
    token <- [a-z]+ { return "".join(val) }
    punct <- [.,;:!?]
    any_ch <- .
    ws <- [ \\t\\r\\n]*
    """
    code = compile_grammar_to_code(grammar_src)
    scope: Dict[str, Any] = {}
    exec(code, scope)
    parser_cls = scope["PaperRuntimeTestParser"]
    parser = parser_cls()

    res = parser.parse("hello!")
    assert res == {"word": "hello", "punct": "!"}


def test_calc_grammar_execution_with_paper_syntax() -> None:
    """Verifies that grammars/calc.peg compiles and correctly evaluates arithmetic expressions."""
    calc_path = _get_grammars_dir() / "calc.peg"
    assert calc_path.exists()
    content = calc_path.read_text(encoding="utf-8")

    code = compile_grammar_to_code(content)
    scope: Dict[str, Any] = {}
    exec(code, scope)
    calc_parser = scope["CalcParser"]()

    assert calc_parser.parse("42") == 42
    assert calc_parser.parse("1 + 2") == 3
    assert calc_parser.parse("2 * 3 + 4") == 10
    assert calc_parser.parse("2 * (3 + 4)") == 14
    assert calc_parser.parse("(100 - 20) / (2 * 4)") == 10


def test_boolean_query_grammar_execution_with_paper_syntax() -> None:
    """Verifies that grammars/boolean_query.peg compiles and parses boolean expressions."""
    bq_path = _get_grammars_dir() / "boolean_query.peg"
    assert bq_path.exists()
    content = bq_path.read_text(encoding="utf-8")

    code = compile_grammar_to_code(content)
    scope: Dict[str, Any] = {}
    exec(code, scope)
    bq_parser = scope["BooleanQueryParser"]()

    ast = bq_parser.parse("title:cve AND author:smith")
    assert ast["op"] == "AND"
    assert len(ast["clauses"]) == 2
    assert ast["clauses"][0] == {"field": "title", "value": {"term": "cve"}}
    assert ast["clauses"][1] == {"field": "author", "value": {"term": "smith"}}

    phrase_ast = bq_parser.parse('"zero trust architecture"')
    assert phrase_ast == {"phrase": "zero trust architecture"}
