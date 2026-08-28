#!/usr/bin/env python3
"""Backward-compatibility shim for database.vdbe.codegen."""

from .vdbe.codegen import CodeGenerator

__all__ = ["CodeGenerator"]
