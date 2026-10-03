#!/usr/bin/env python3
"""
Backend code generators for PEG Ahead-of-Time Compiler.
Conforms to DSN-25 Phase 2 Ahead-of-Time PEG Compiler specification.
Zero external dependencies.
"""

from __future__ import annotations

from core.peg.compiler.backend.base import BaseCodeGenerator
from core.peg.compiler.backend.javascript import JSCodeGenerator
from core.peg.compiler.backend.python import CodeGenerator

__all__ = [
    "BaseCodeGenerator",
    "CodeGenerator",
    "JSCodeGenerator",
]
