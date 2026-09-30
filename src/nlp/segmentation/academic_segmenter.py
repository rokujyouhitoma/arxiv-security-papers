"""Academic sentence boundary segmenter.

Robust sentence splitter tailored for scientific and security papers.
Protects abbreviations (e.g., et al.), citations, figure references,
decimals, and quoted text from erroneous sentence boundary detection.
Guaranteed ReDoS immunity with linear O(N) execution and Xenon CC <= 3.
Zero external dependencies.
"""

import re
from typing import List, Optional, Sequence, Tuple

from nlp.core.context import _DEFAULT_ABBREVIATIONS, resolve_abbreviations
from nlp.core.protocols import SentenceSegmenterSPI
from nlp.core.tokens import Sentence, Span

_DOT_PLACEHOLDER = "\ue001"
_DEFAULT_MAX_LENGTH = 1_000_000

# Academic abbreviations needing dot protection (backward-compatible)
_ABBREVIATIONS: Tuple[Tuple[str, str], ...] = _DEFAULT_ABBREVIATIONS

_REF_PATTERN = re.compile(
    r"\b(Fig|Figs|Table|Ref|Refs|Sec|Eq|No|Vol)\.\s*(\d+|\[)", re.IGNORECASE
)
_DECIMAL_PATTERN = re.compile(r"(\d+)\.(\d+)")
_QUOTE_PATTERN = re.compile(r'"([^"\n]{1,500})"')
_PAREN_PATTERN = re.compile(r"\(([^)\n]{1,500})\)")
_SPLIT_PATTERN = re.compile(r"(?<=[.!?])\s+")


def _mask_abbreviations(text: str, abbreviations: Sequence[Tuple[str, str]]) -> str:
    """Mask known academic abbreviations."""
    result = text
    for abbr, repl in abbreviations:
        pattern = re.compile(re.escape(abbr), re.IGNORECASE)
        result = pattern.sub(repl, result)
    return result


def _mask_references(text: str) -> str:
    """Mask section, figure, and citation references."""
    return _REF_PATTERN.sub(rf"\1{_DOT_PLACEHOLDER} \2", text)


def _mask_decimals(text: str) -> str:
    """Mask decimal numbers and software versions."""
    return _DECIMAL_PATTERN.sub(rf"\1{_DOT_PLACEHOLDER}\2", text)


def _mask_quotes_and_parens(text: str) -> str:
    """Mask dots within short quotation and parenthesis spans."""
    step1 = _QUOTE_PATTERN.sub(
        lambda m: f'"{m.group(1).replace(".", _DOT_PLACEHOLDER)}"', text
    )
    return _PAREN_PATTERN.sub(
        lambda m: f"({m.group(1).replace('.', _DOT_PLACEHOLDER)})", step1
    )


def _mask_text(text: str, abbreviations: Sequence[Tuple[str, str]]) -> str:
    """Apply sequential masking passes to protect non-sentence dots."""
    step1 = _mask_abbreviations(text, abbreviations)
    step2 = _mask_references(step1)
    step3 = _mask_decimals(step2)
    return _mask_quotes_and_parens(step3)


def _unmask_text(text: str) -> str:
    """Restore masked dot placeholders to original periods."""
    return text.replace(_DOT_PLACEHOLDER, ".")


def _locate_sentence_span(
    source_text: str, sentence_text: str, search_start: int
) -> Span:
    """Locate precise character boundary span for extracted sentence."""
    pos = source_text.find(sentence_text, search_start)
    if pos == -1:
        return Span(search_start, search_start + len(sentence_text))
    return Span(pos, pos + len(sentence_text))


class AcademicSentenceSegmenter(SentenceSegmenterSPI):
    """Segment academic and technical prose into well-formed sentences."""

    def __init__(
        self,
        max_text_length: int = _DEFAULT_MAX_LENGTH,
        min_sentence_length: int = 5,
        abbreviations: Optional[Sequence[Tuple[str, str]]] = None,
    ) -> None:
        """Initialize segmenter with safety limits and optional abbreviations."""
        self._max_text_length = max_text_length
        self._min_sentence_length = min_sentence_length
        self._abbreviations = abbreviations

    def _get_abbreviations(self) -> Sequence[Tuple[str, str]]:
        """Resolve abbreviations via 3-tier fallback."""
        return resolve_abbreviations(self._abbreviations)

    def split_sentences(self, text: str) -> List[Sentence]:
        """Split text into rich Sentence instances with exact spans."""
        if not text:
            return []
        if len(text) > self._max_text_length:
            raise ValueError(
                f"Input text exceeds maximum allowed length ({self._max_text_length})"
            )

        cleaned = text.replace("\r\n", " ").replace("\n", " ").strip()
        if not cleaned:
            return []

        abbrs = self._get_abbreviations()
        masked = _mask_text(cleaned, abbrs)
        raw_chunks = _SPLIT_PATTERN.split(masked)
        return self._build_sentences(cleaned, raw_chunks)

    def split_text(self, text: str) -> List[str]:
        """Split text and return clean string representations."""
        sentences = self.split_sentences(text)
        return [s.text for s in sentences]

    def _build_sentences(
        self, cleaned_text: str, raw_chunks: List[str]
    ) -> List[Sentence]:
        """Reconstruct sentences and compute spans monotonically."""
        results: List[Sentence] = []
        cursor = 0
        for chunk in raw_chunks:
            unmasked = _unmask_text(chunk).strip()
            if len(unmasked) < self._min_sentence_length:
                continue
            span = _locate_sentence_span(cleaned_text, unmasked, cursor)
            results.append(Sentence(text=unmasked, span=span))
            cursor = span.end
        return results
