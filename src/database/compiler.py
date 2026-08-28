#!/usr/bin/env python3
"""Backward-compatibility shim for database.vdbe.compiler."""

from .vdbe.compiler import SQLCompiler

__all__ = ["SQLCompiler"]
