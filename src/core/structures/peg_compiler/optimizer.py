#!/usr/bin/env python3
"""Backward-compatibility shim. Use core.peg.compiler.optimizer instead."""

from __future__ import annotations

from core.peg.compiler.optimizer import GrammarOptimizer

__all__ = ["GrammarOptimizer"]
