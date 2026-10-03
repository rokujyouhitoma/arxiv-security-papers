#!/usr/bin/env python3
"""
Abstract Base Code Generator for PEG Ahead-of-Time Compiler.
Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.
Zero external dependencies.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from core.peg.compiler.ast_nodes import GrammarDef


class BaseCodeGenerator(ABC):
    """Abstract base class for all PEG code generators."""

    def __init__(self, grammar: GrammarDef) -> None:
        self.grammar = grammar

    @abstractmethod
    def generate(self) -> str:
        """Emits target code string from grammar AST."""
        raise NotImplementedError
