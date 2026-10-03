#!/usr/bin/env python3
"""Backward-compatibility shim. Use core.peg.compiler.generated_meta_parser instead."""

from __future__ import annotations

from core.peg.compiler.generated_meta_parser import MetaGrammarParser

__all__ = ["MetaGrammarParser"]
