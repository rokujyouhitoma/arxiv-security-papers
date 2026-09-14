#!/usr/bin/env python3
"""
Abstract Syntax Tree (AST) node definitions for PEG Grammar Specifications.
Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.
Zero external dependencies.
"""

from __future__ import annotations

from abc import ABC
from dataclasses import dataclass, field
from typing import List, Optional


class Expression(ABC):
    """Abstract base class for all PEG parsing expressions in grammar AST."""

    pass


@dataclass(frozen=True)
class LitExpr(Expression):
    """String literal match expression (e.g. 'SELECT', '+')."""

    value: str


@dataclass(frozen=True)
class RegexExpr(Expression):
    """Regular expression match expression (e.g. /[0-9]+/)."""

    pattern: str


@dataclass(frozen=True)
class RuleRefExpr(Expression):
    """Reference to another non-terminal grammar rule (e.g. expr, term)."""

    name: str


@dataclass(frozen=True)
class SeqExpr(Expression):
    """Sequence expression: matches e1 followed by e2, ..."""

    elements: List[Expression]


@dataclass(frozen=True)
class ChoiceExpr(Expression):
    """Ordered choice expression: tries alternatives in order."""

    alternatives: List[Expression]


@dataclass(frozen=True)
class RepeatExpr(Expression):
    """Repetition expression: 0 or more (*), 1 or more (+)."""

    expr: Expression
    min_count: int = 0
    max_count: Optional[int] = None


@dataclass(frozen=True)
class OptExpr(Expression):
    """Optional expression: 0 or 1 occurrence (?)."""

    expr: Expression


@dataclass(frozen=True)
class PredExpr(Expression):
    """Syntactic predicate: positive lookahead (&) or negative lookahead (!)."""

    expr: Expression
    is_positive: bool = True


@dataclass(frozen=True)
class NamedExpr(Expression):
    """Named expression binding a variable name to an inner expression (e.g. op:('+'))."""

    name: str
    expr: Expression


@dataclass(frozen=True)
class ActionExpr(Expression):
    """Semantic action hook attached to an expression { action_code }."""

    expr: Expression
    action_code: str


@dataclass(frozen=True)
class RuleDef:
    """Definition of a single PEG grammar rule (name = expr)."""

    name: str
    expr: Expression
    docstring: str = ""


@dataclass(frozen=True)
class GrammarDef:
    """Root AST node representing a complete PEG grammar specification."""

    name: str
    rules: List[RuleDef] = field(default_factory=list)
    header_code: str = ""
    start_rule: Optional[str] = None
