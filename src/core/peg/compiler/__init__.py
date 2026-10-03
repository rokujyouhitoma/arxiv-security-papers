#!/usr/bin/env python3
"""
DSN-25 Ahead-of-Time Packrat PEG Compiler package.
Provides grammar specification parsing, AST representations, optimizer, backend code generators, and CLI tools.
Zero external dependencies.
"""

from __future__ import annotations

from core.peg.compiler.ast_nodes import (
    ActionExpr,
    AnyCharExpr,
    CharClassExpr,
    ChoiceExpr,
    CutExpr,
    Expression,
    GrammarDef,
    LitExpr,
    NamedExpr,
    OptExpr,
    PredExpr,
    RegexExpr,
    RepeatExpr,
    RuleDef,
    RuleRefExpr,
    SeqExpr,
)
from core.peg.compiler.backend import BaseCodeGenerator, CodeGenerator, JSCodeGenerator
from core.peg.compiler.cli import (
    compile_grammar_to_code,
    compile_runtime_to_code,
    run_cli,
)
from core.peg.compiler.optimizer import GrammarOptimizer
from core.peg.compiler.parser import MetaGrammarParser

__all__ = [
    "Expression",
    "LitExpr",
    "RegexExpr",
    "CharClassExpr",
    "AnyCharExpr",
    "CutExpr",
    "RuleRefExpr",
    "SeqExpr",
    "ChoiceExpr",
    "RepeatExpr",
    "OptExpr",
    "PredExpr",
    "NamedExpr",
    "ActionExpr",
    "RuleDef",
    "GrammarDef",
    "MetaGrammarParser",
    "GrammarOptimizer",
    "BaseCodeGenerator",
    "CodeGenerator",
    "JSCodeGenerator",
    "compile_grammar_to_code",
    "compile_runtime_to_code",
    "run_cli",
]
