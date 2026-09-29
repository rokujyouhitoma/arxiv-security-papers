#!/usr/bin/env python3
"""NLP Keyword & Keyphrase Extractor Module.

Delegates to `src/nlp/extraction/` while maintaining backward compatibility.
Zero external dependencies.
"""

from typing import Set

from nlp.extraction import extract_keyphrases
from nlp.extraction.cvalue import CValueExtractor as _BaseCValueExtractor
from nlp.extraction.textrank import TextRankKeywordExtractor as _BaseTextRankExtractor
from nlp.lexicon.stop_words import STOPWORDS

DEFAULT_STOPWORDS: Set[str] = set(STOPWORDS)


class TextRankKeywordExtractor(_BaseTextRankExtractor):
    """Backward-compatible TextRank keyword extractor."""

    pass


class CValueExtractor(_BaseCValueExtractor):
    """Backward-compatible C-Value compound term extractor."""

    pass


__all__ = [
    "DEFAULT_STOPWORDS",
    "TextRankKeywordExtractor",
    "CValueExtractor",
    "extract_keyphrases",
]
