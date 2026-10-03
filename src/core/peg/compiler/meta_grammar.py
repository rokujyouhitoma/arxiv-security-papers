#!/usr/bin/env python3
"""
Meta-Grammar Parser alias for backward compatibility.
Use core.peg.compiler.parser instead.
"""

from __future__ import annotations

from core.peg.compiler.parser import MetaGrammarParser

__all__ = ["MetaGrammarParser"]
