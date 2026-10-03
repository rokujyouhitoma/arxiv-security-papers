#!/usr/bin/env python3
"""
Unit tests for core.peg package architecture and backend code generators (Issue #437).
Verifies:
1. Public API exports from core.peg and core.peg.compiler.
2. BaseCodeGenerator abstraction and backend inheritance (Python & JavaScript).
3. Backward compatibility shims in core.structures.peg and core.structures.peg_compiler.
4. Python code generation emits core.peg imports and executes cleanly.
"""

from __future__ import annotations

import pytest

import core.peg as peg_root
from core.peg import Choice, Class, Cut, CutOp, Dot, Lit, Parser, PEGSyntaxError, Seq
from core.peg.compiler import (
    BaseCodeGenerator,
    CodeGenerator,
    Expression,
    GrammarDef,
    GrammarOptimizer,
    JSCodeGenerator,
    LitExpr,
    MetaGrammarParser,
    compile_grammar_to_code,
)
from core.peg.compiler.backend import BaseCodeGenerator as BackendBase
from core.peg.compiler.backend import CodeGenerator as PyBackend
from core.peg.compiler.backend import JSCodeGenerator as JsBackend


def test_core_peg_exports() -> None:
    """Verifies that core.peg exports all runtime combinators and classes."""
    assert issubclass(Choice, Parser)
    assert issubclass(Seq, Parser)
    assert issubclass(Lit, Parser)
    assert issubclass(PEGSyntaxError, Exception)
    assert Dot is not None
    assert Class is not None
    assert CutOp is Cut

    # Check that all symbols in __all__ are defined on core.peg
    for name in peg_root.__all__:
        assert hasattr(peg_root, name), f"Missing {name} in core.peg"


def test_core_peg_compiler_exports() -> None:
    """Verifies that core.peg.compiler exports IR nodes, optimizers, and backends."""
    assert issubclass(LitExpr, Expression)
    assert issubclass(GrammarOptimizer, object)
    assert issubclass(MetaGrammarParser, object)
    assert issubclass(CodeGenerator, BaseCodeGenerator)
    assert issubclass(JSCodeGenerator, BaseCodeGenerator)
    assert BackendBase is BaseCodeGenerator
    assert PyBackend is CodeGenerator
    assert JsBackend is JSCodeGenerator


def test_basecode_generator_abstraction() -> None:
    """Verifies BaseCodeGenerator abstract interface."""
    with pytest.raises(TypeError):
        BaseCodeGenerator(GrammarDef("TestGrammar", []))  # type: ignore[abstract]


def test_backward_compatibility_shims() -> None:
    """Verifies that legacy core.structures shims re-export symbols identically."""
    import core.structures.peg as legacy_peg
    import core.structures.peg_compiler as legacy_compiler

    assert legacy_peg.Choice is Choice
    assert legacy_peg.PEGSyntaxError is PEGSyntaxError
    assert legacy_compiler.CodeGenerator is CodeGenerator
    assert legacy_compiler.JSCodeGenerator is JSCodeGenerator
    assert legacy_compiler.MetaGrammarParser is MetaGrammarParser
    assert legacy_compiler.compile_grammar_to_code is compile_grammar_to_code


def test_python_codegen_emits_core_peg_import() -> None:
    """Verifies that Python code generator emits 'from core.peg import' statements."""
    grammar_text = """
    grammar MiniMath
    expr <- term ('+' term)*
    term <- [0-9]+
    """
    code = compile_grammar_to_code(grammar_text, target="python")
    assert "from core.peg import (" in code
    assert "class MiniMathParser(Parser[Any]):" in code

    namespace: dict = {}
    exec(code, namespace)
    assert "MiniMathParser" in namespace
    parser = namespace["MiniMathParser"]()
    result = parser.parse("12+34")
    assert result is not None
