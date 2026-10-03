#!/usr/bin/env python3
"""Backward-compatibility shim. Use core.peg.compiler.backend.javascript instead."""

from __future__ import annotations

from core.peg.compiler.backend.javascript import JSCodeGenerator

__all__ = ["JSCodeGenerator"]
