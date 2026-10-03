"""Backward compatibility shim for pdf_engine.bibtex_helpers.

This module re-exports symbols from the modularized pdf_engine.bibtex.helpers.
New code should import from pdf_engine.bibtex.helpers directly.
"""

from pdf_engine.bibtex.helpers import (
    BibTeXEntry,
    _build_bibtex_entry,
    _clean_field_value,
    _collect_bibtex_entries,
    _normalize_latex_special_chars,
)

__all__ = [
    "BibTeXEntry",
    "_normalize_latex_special_chars",
    "_clean_field_value",
    "_build_bibtex_entry",
    "_collect_bibtex_entries",
]
