#!/usr/bin/env python3
"""Backward-compatibility shim. Use core.peg.compiler.cli instead."""

from __future__ import annotations

from core.peg.compiler.cli import (
    compile_grammar_to_code,
    compile_runtime_to_code,
    run_cli,
)

__all__ = [
    "compile_grammar_to_code",
    "compile_runtime_to_code",
    "run_cli",
]
