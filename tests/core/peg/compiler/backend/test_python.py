#!/usr/bin/env python3
"""
Unit tests for PEG Python Code Generator (core.peg.compiler.backend.python).
Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.
Zero external dependencies.
"""

from __future__ import annotations

from core.peg.compiler.ast_nodes import GrammarDef, LitExpr, RuleDef
from core.peg.compiler.backend.base import BaseCodeGenerator
from core.peg.compiler.backend.python import CodeGenerator


def test_python_codegen_subclass() -> None:
    """Verifies that CodeGenerator inherits from BaseCodeGenerator."""
    assert issubclass(CodeGenerator, BaseCodeGenerator)


def test_python_codegen_basic_grammar() -> None:
    """Verifies Python code generation from GrammarDef AST."""
    grammar = GrammarDef(
        name="Hello",
        rules=[RuleDef(name="greeting", expr=LitExpr("hello"))],
    )
    generator = CodeGenerator(grammar)
    code = generator.generate()

    assert "from core.peg import (" in code
    assert "class HelloParser(Parser[Any]):" in code
    assert "Lit('hello')" in code

    namespace: dict = {}
    exec(code, namespace)
    parser = namespace["HelloParser"]()
    result = parser.parse("hello")
    assert result == "hello"
