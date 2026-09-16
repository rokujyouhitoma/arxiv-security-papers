"""Helper functions and data structures for Pure PEG BibTeX/LaTeX parsing."""

import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Tuple


@dataclass(frozen=True)
class BibTeXEntry:
    """Represents a structured BibTeX citation entry."""

    entry_type: str
    cite_key: str
    fields: Dict[str, str] = field(default_factory=dict)
    raw_text: str = ""


def _normalize_latex_special_chars(text: str) -> str:
    """Normalizes LaTeX accents, quotes, and dashes to standard Unicode."""
    # LaTeX accents
    text = re.sub(r'\\"[aA]', "ä", text)
    text = re.sub(r'\\"[oO]', "ö", text)
    text = re.sub(r'\\"[uU]', "ü", text)
    text = re.sub(r"\\'[eE]", "é", text)
    text = re.sub(r"\\'[aA]", "á", text)
    text = re.sub(r"\\`[aA]", "à", text)
    text = re.sub(r"\\`[eE]", "è", text)
    text = re.sub(r"\\c\{c\}", "ç", text)
    # Dashes and symbols
    text = text.replace("---", "—").replace("--", "–")
    text = text.replace("``", "“").replace("''", "”")
    text = text.replace(r"\%", "%").replace(r"\&", "&").replace(r"\_", "_")
    return text.strip()


def _clean_field_value(raw: str) -> str:
    """Strips outer braces/quotes and normalizes LaTeX escapes."""
    stripped = raw.strip()
    if (stripped.startswith("{") and stripped.endswith("}")) or (
        stripped.startswith('"') and stripped.endswith('"')
    ):
        stripped = stripped[1:-1]
    return _normalize_latex_special_chars(stripped)


def _build_bibtex_entry(
    entry_type: str,
    cite_key: str,
    field_tuples: List[Tuple[str, str]],
) -> BibTeXEntry:
    """Constructs a BibTeXEntry object from parsed field tuples."""
    field_dict: Dict[str, str] = {}
    for k, v in field_tuples:
        field_dict[k.lower()] = _clean_field_value(v)
    return BibTeXEntry(
        entry_type=entry_type.lower(),
        cite_key=cite_key.strip(),
        fields=field_dict,
    )


def _collect_bibtex_entries(raw_items: List[Any]) -> List[BibTeXEntry]:
    """Filters and returns a list of valid BibTeXEntry instances."""
    return [item for item in raw_items if isinstance(item, BibTeXEntry)]
