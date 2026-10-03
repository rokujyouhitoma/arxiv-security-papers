"""BibTeX and LaTeX Citation Extraction Engine.

Conforms to Bryan Ford POPL '04 Packrat PEG Architecture and DSN-25.
"""

from pdf_engine.bibtex.extractor import (
    _get_bibtex_parser,
    extract_arxiv_references,
    extract_bibtex_entries,
    extract_latex_citations,
)
from pdf_engine.bibtex.helpers import (
    BibTeXEntry,
    _build_bibtex_entry,
    _clean_field_value,
    _collect_bibtex_entries,
    _normalize_latex_special_chars,
)

__all__ = [
    "BibTeXEntry",
    "extract_bibtex_entries",
    "extract_latex_citations",
    "extract_arxiv_references",
    "_get_bibtex_parser",
    "_build_bibtex_entry",
    "_collect_bibtex_entries",
    "_clean_field_value",
    "_normalize_latex_special_chars",
]
