#!/usr/bin/env python3
"""Backward-compatibility shim for database.compat.profiler."""

from .compat.profiler import DatabaseProfiler, ProfileResult

__all__ = ["DatabaseProfiler", "ProfileResult"]
