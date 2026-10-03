#!/usr/bin/env python3
"""Backward-compatibility shim. Use core.peg.compiler.backend.python instead."""

from __future__ import annotations

from core.peg.compiler.backend.python import CodeGenerator

__all__ = ["CodeGenerator"]
