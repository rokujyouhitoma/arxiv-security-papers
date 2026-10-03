"""Backward compatibility shim for pdf_engine.generated_bibtex_parser.

This module re-exports symbols from the modularized pdf_engine.bibtex.generated_parser.
New code should import from pdf_engine.bibtex.generated_parser directly.
"""

from pdf_engine.bibtex.generated_parser import BibTeXParser

__all__ = [
    "BibTeXParser",
]
