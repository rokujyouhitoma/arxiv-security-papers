"""Pure Python Packrat PEG BibTeX and LaTeX Citation Extraction Engine.

Provides zero-dependency structured extraction of academic citations,
BibTeX records, and arXiv cross-references from paper text.
"""

import re
import threading
from typing import List, Optional

from core.structures.peg import PEGSyntaxError
from pdf_engine.bibtex_helpers import BibTeXEntry
from pdf_engine.generated_bibtex_parser import BibTeXParser

_parser_lock = threading.Lock()
_global_bibtex_parser: Optional[BibTeXParser] = None

_ARXIV_ID_PATTERN = re.compile(
    r"(?:arXiv:\s*|arxiv\.org/(?:abs|pdf)/)?(\d{4}\.\d{4,5}(?:v\d+)?)",
    re.IGNORECASE,
)
_CITE_CMD_PATTERN = re.compile(r"\\cite[pt]?\{([^}]+)\}")


def _get_bibtex_parser() -> BibTeXParser:
    """Thread-safe singleton getter for BibTeXParser."""
    global _global_bibtex_parser
    if _global_bibtex_parser is None:
        with _parser_lock:
            if _global_bibtex_parser is None:
                _global_bibtex_parser = BibTeXParser()
    return _global_bibtex_parser


def extract_bibtex_entries(text: str) -> List[BibTeXEntry]:
    """Parses all BibTeX entries embedded within raw or structured paper text."""
    if "@" not in text:
        return []
    parser = _get_bibtex_parser()
    try:
        results = parser.parse(text)
        return results if isinstance(results, list) else []
    except PEGSyntaxError:
        return []


def extract_latex_citations(text: str) -> List[str]:
    """Extracts citation keys referenced via LaTeX \\cite commands."""
    keys: List[str] = []
    for match in _CITE_CMD_PATTERN.finditer(text):
        raw_keys = match.group(1).split(",")
        for k in raw_keys:
            cleaned = k.strip()
            if cleaned and cleaned not in keys:
                keys.append(cleaned)
    return keys


def extract_arxiv_references(text: str) -> List[str]:
    """Extracts distinct arXiv paper identifiers cited within the text."""
    ids: List[str] = []
    for match in _ARXIV_ID_PATTERN.finditer(text):
        clean_id = match.group(1).split("v")[0]
        if clean_id not in ids:
            ids.append(clean_id)
    return ids
