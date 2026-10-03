"""Backward compatibility shim for pdf_engine.bibtex_extractor.

This module re-exports symbols from the modularized pdf_engine.bibtex.extractor.
New code should import from pdf_engine.bibtex directly.
"""

from pdf_engine.bibtex.extractor import (
    _get_bibtex_parser,
    extract_arxiv_references,
    extract_bibtex_entries,
    extract_latex_citations,
)

__all__ = [
    "extract_bibtex_entries",
    "extract_latex_citations",
    "extract_arxiv_references",
    "_get_bibtex_parser",
]
