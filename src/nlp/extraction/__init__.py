"""Keyphrase and Compound Term Extraction Subsystem.

Provides graph-based TextRank and C-Value extraction algorithms.
Zero external dependencies.
"""

from typing import AbstractSet, List, Optional

from nlp.extraction.cvalue import CValueExtractor
from nlp.extraction.textrank import TextRankKeywordExtractor


def _append_unique_phrase(results: List[str], seen: set[str], phrase: str) -> None:
    """Append normalized phrase to results if not previously observed."""
    norm = phrase.lower()
    if norm not in seen:
        results.append(phrase)
        seen.add(norm)


def _merge_extracted_phrases(
    compounds: List[str],
    ranked: List[tuple[str, float]],
    top_k: int,
) -> List[str]:
    """Combine compound phrases and single-word TextRank results up to top_k."""
    results: List[str] = []
    seen: set[str] = set()

    for comp in compounds:
        _append_unique_phrase(results, seen, comp)

    for word, _score in ranked:
        if len(results) >= top_k:
            break
        _append_unique_phrase(results, seen, word)

    return results[:top_k]


def extract_keyphrases(
    text: str,
    top_k: int = 5,
    include_compounds: bool = True,
    stopwords: Optional[AbstractSet[str]] = None,
) -> List[str]:
    """High-level API to extract top technical keyphrases and compounds from text."""
    if not text or not text.strip():
        return []

    compounds = (
        CValueExtractor(stopwords=stopwords).extract_compounds(text, top_k=top_k)
        if include_compounds
        else []
    )
    ranked = TextRankKeywordExtractor(stopwords=stopwords).extract_keyphrases(
        text, top_k=top_k * 2
    )

    return _merge_extracted_phrases(compounds, ranked, top_k)


__all__ = [
    "TextRankKeywordExtractor",
    "CValueExtractor",
    "extract_keyphrases",
]
