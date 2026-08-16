#!/usr/bin/env python3
"""
Backward-compatible shim for SynonymExpander.
Re-exports from the modular `search` package.
"""

from search import SynonymExpander

__all__ = ["SynonymExpander"]
