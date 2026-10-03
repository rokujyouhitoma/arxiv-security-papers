#!/usr/bin/env python3
"""
Packrat PEG (Parsing Expression Grammar) framework for arxiv-security-papers.
Provides linear-time parsing engine, AST combinators, and Ahead-of-Time (AOT) multi-target compiler.
Conforms to DSN-25 specification.
Zero external dependencies.
"""

from __future__ import annotations

from core.peg.runtime import (
    AndPred,
    AnyChar,
    CharClass,
    Choice,
    Class,
    Cut,
    CutOp,
    Dot,
    Empty,
    Lit,
    Literal,
    MappedParser,
    NotPred,
    OneOrMore,
    Opt,
    OptionalParser,
    ParseContext,
    Parser,
    ParseResult,
    PEGSyntaxError,
    Predicate,
    Reg,
    Regex,
    Repetition,
    RuleRef,
    Seq,
    Sequence,
    ZeroOrMore,
)

__all__ = [
    "AndPred",
    "AnyChar",
    "CharClass",
    "Choice",
    "Class",
    "Cut",
    "CutOp",
    "Dot",
    "Empty",
    "Lit",
    "Literal",
    "MappedParser",
    "NotPred",
    "OneOrMore",
    "Opt",
    "OptionalParser",
    "ParseContext",
    "Parser",
    "ParseResult",
    "PEGSyntaxError",
    "Predicate",
    "Reg",
    "Regex",
    "Repetition",
    "RuleRef",
    "Seq",
    "Sequence",
    "ZeroOrMore",
]
