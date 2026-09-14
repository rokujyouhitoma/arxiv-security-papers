#!/usr/bin/env python3
"""
DSN-25 Ahead-of-Time Packrat PEG Compiler package.
Provides grammar specification parsing, AST representations, code generation, and CLI tools.
Zero external dependencies.
"""

from __future__ import annotations

from core.structures.peg_compiler.ast_nodes import (
    ActionExpr,
    ChoiceExpr,
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
from core.structures.peg_compiler.cli import compile_grammar_to_code, run_cli
from core.structures.peg_compiler.codegen import CodeGenerator
from core.structures.peg_compiler.meta_grammar import MetaGrammarParser

__all__ = [
    "Expression",
    "LitExpr",
    "RegexExpr",
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
    "CodeGenerator",
    "compile_grammar_to_code",
    "run_cli",
]
