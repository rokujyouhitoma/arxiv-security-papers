"""Backward compatibility shim for pdf_engine.generated_cmap_parser.

This module re-exports symbols from the modularized pdf_engine.cmap.generated_parser.
New code should import from pdf_engine.cmap.generated_parser directly.
"""

from pdf_engine.cmap.generated_parser import PDFCMapParser

__all__ = [
    "PDFCMapParser",
]
