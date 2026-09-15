#!/usr/bin/env python3
"""
Unit tests for DSN-25 Phase 2 Ahead-of-Time Packrat PEG Compiler.
Tests meta-grammar parsing, AST representation, code generator, and generated parser execution.
"""

import tempfile
from pathlib import Path
from typing import Any, Dict

import pytest

from core.structures.peg import PEGSyntaxError
from core.structures.peg_compiler import (
    ChoiceExpr,
    GrammarDef,
    MetaGrammarParser,
    OptExpr,
    PredExpr,
    RepeatExpr,
    RuleRefExpr,
    SeqExpr,
    compile_grammar_to_code,
    run_cli,
)


def test_meta_grammar_ast_construction() -> None:
    """Verifies that MetaGrammarParser produces the expected AST hierarchy."""
    grammar_text = """
    grammar Minimal
    start = head:token rest:token* { return [head] + rest }
    token = /[a-z]+/
    """
    parser = MetaGrammarParser()
    ast = parser.parse(grammar_text)

    assert isinstance(ast, GrammarDef)
    assert ast.name == "Minimal"
    assert len(ast.rules) == 2
    assert ast.rules[0].name == "start"
    assert ast.rules[1].name == "token"


def test_meta_grammar_operator_precedence() -> None:
    """Verifies choice, sequence, repetition, and predicate parsing precedence."""
    grammar_text = """
    grammar Operators
    rule = &"prefix" a (b / c)+ !d?
    a = "A"
    b = "B"
    c = "C"
    d = "D"
    """
    parser = MetaGrammarParser()
    ast = parser.parse(grammar_text)

    assert len(ast.rules) == 5
    rule = ast.rules[0]
    assert isinstance(rule.expr, SeqExpr)
    elems = rule.expr.elements
    # &"prefix"
    assert isinstance(elems[0], PredExpr)
    assert elems[0].is_positive is True
    # a
    assert isinstance(elems[1], RuleRefExpr)
    # (b / c)+
    assert isinstance(elems[2], RepeatExpr)
    assert elems[2].min_count == 1
    assert isinstance(elems[2].expr, ChoiceExpr)
    # !d?
    assert isinstance(elems[3], PredExpr)
    assert elems[3].is_positive is False
    assert isinstance(elems[3].expr, OptExpr)


def test_meta_grammar_nested_action_block() -> None:
    """Verifies that ActionBlockParser handles strings containing braces and dict literals."""
    grammar_text = """
    grammar DictBuilder
    rule = word:/[a-z]+/ {
        # comment with { and }
        s = "literal with } and {"
        return {"key": word, "flag": True}
    }
    """
    parser = MetaGrammarParser()
    ast = parser.parse(grammar_text)

    assert len(ast.rules) == 1
    code = compile_grammar_to_code(grammar_text)
    assert "DictBuilderParser" in code
    assert '"key": word' in code


def test_calc_grammar_execution() -> None:
    """Compiles and executes arithmetic calculator grammar."""
    calc_path = Path(__file__).resolve().parent.parent.parent / "grammars" / "calc.peg"
    assert calc_path.exists()

    code = compile_grammar_to_code(calc_path.read_text(encoding="utf-8"))
    scope: Dict[str, Any] = {}
    exec(code, scope)

    CalcParser = scope["CalcParser"]
    parser = CalcParser()

    assert parser.parse("42") == 42
    assert parser.parse("2+3") == 5
    assert parser.parse("2*3+4") == 10
    assert parser.parse("2+3*4") == 14
    assert parser.parse("(2+3)*4") == 20
    assert parser.parse("100/2/5") == 10


def test_search_query_grammar_execution() -> None:
    """Compiles and executes search query grammar."""
    query_path = (
        Path(__file__).resolve().parent.parent.parent / "grammars" / "search_query.peg"
    )
    assert query_path.exists()

    code = compile_grammar_to_code(query_path.read_text(encoding="utf-8"))
    scope: Dict[str, Any] = {}
    exec(code, scope)

    SearchQueryParser = scope["SearchQueryParser"]
    parser = SearchQueryParser()

    res = parser.parse('title:ransomware AND (malware OR "zero day")')
    assert len(res) >= 1
    flat = []
    for c in res:
        flat.extend(c.flatten())
    terms = {c.term for c in flat}
    assert "ransomware" in terms
    assert "malware" in terms
    assert "zero day" in terms


def test_meta_grammar_syntax_error() -> None:
    """Verifies that invalid PEG syntax raises PEGSyntaxError."""
    invalid_peg = "rule = = invalid"
    parser = MetaGrammarParser()
    with pytest.raises(PEGSyntaxError) as exc_info:
        parser.parse(invalid_peg)
    assert "Syntax error" in str(exc_info.value)


def test_cli_output_file_and_override() -> None:
    """Tests compile_peg CLI with file output and class name override."""
    calc_path = Path(__file__).resolve().parent.parent.parent / "grammars" / "calc.peg"
    with tempfile.TemporaryDirectory() as tmpdir:
        out_file = Path(tmpdir) / "custom_calc.py"
        ret = run_cli(
            [
                str(calc_path),
                "-o",
                str(out_file),
                "--class-name",
                "AdvancedCalc",
            ]
        )
        assert ret == 0
        assert out_file.exists()
        content = out_file.read_text(encoding="utf-8")
        assert "class AdvancedCalcParser" in content
