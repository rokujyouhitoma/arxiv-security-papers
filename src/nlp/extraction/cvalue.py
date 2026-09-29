"""C-Value Technical Compound Phrase Extraction Module.

Extracts multi-word academic compounds and multi-token terminology
from academic papers and security specifications using length-frequency weighting.
Zero external dependencies.
"""

import math
import re
from collections import defaultdict
from typing import AbstractSet, Dict, List, Optional, Sequence, Tuple

from nlp.lexicon.stop_words import STOPWORDS


def _is_valid_word_list(words: Sequence[str], stopwords: AbstractSet[str]) -> bool:
    """Validate compound word sequence against length and stopword limits."""
    if len(words) < 2:
        return False
    return not any(w in stopwords for w in words)


def _is_valid_compound(term: str, stopwords: AbstractSet[str]) -> bool:
    """Check if compound phrase is valid and not dominated by stopwords."""
    words = term.lower().split()
    return _is_valid_word_list(words, stopwords)


def _collect_pattern_matches(text: str, pattern: str) -> List[str]:
    """Find all matches of a regex pattern in text."""
    return re.findall(pattern, text)


def _filter_raw_matches(
    matches: Sequence[str], stopwords: AbstractSet[str]
) -> List[str]:
    """Filter regex matches using compound validity rules."""
    candidates: List[str] = []
    for m in matches:
        clean = m.strip()
        if _is_valid_compound(clean, stopwords):
            candidates.append(clean)
    return candidates


def _extract_candidates(text: str, stopwords: AbstractSet[str]) -> List[str]:
    """Extract candidate multi-word technical terms matching patterns."""

    patterns = [
        r"\b[A-Z][a-z0-9]+(?:\s+[A-Z][a-z0-9]+)+\b",
        r"\b[a-zA-Z0-9]+-[a-zA-Z0-9]+(?:\s+[a-zA-Z0-9]+)?\b",
    ]
    candidates: List[str] = []
    for pat in patterns:
        matches = _collect_pattern_matches(text, pat)
        filtered = _filter_raw_matches(matches, stopwords)
        candidates.extend(filtered)
    return candidates


def _score_candidate(term: str, freq: int) -> float:
    """Calculate C-Value approximation score from term length and frequency."""
    length = len(term.split())
    return math.log2(length + 1) * freq


def _score_all_candidates(counts: Dict[str, int]) -> List[Tuple[str, float]]:
    """Compute and sort scores for all term counts."""
    scored: List[Tuple[str, float]] = []
    for term, freq in counts.items():
        score = _score_candidate(term, freq)
        scored.append((term, score))
    scored.sort(key=lambda x: x[1], reverse=True)
    return scored


def _is_empty_text(text: str) -> bool:
    """Check if text is empty or blank."""
    return not text or not text.strip()


def _count_candidates(candidates: Sequence[str]) -> Dict[str, int]:
    """Aggregate occurrences of candidate terms."""
    counts: Dict[str, int] = defaultdict(int)
    for c in candidates:
        counts[c] += 1
    return counts


class CValueExtractor:
    """Extracts compound multi-word technical phrases using C-Value heuristics."""

    def __init__(self, stopwords: Optional[AbstractSet[str]] = None) -> None:
        """Initialize CValue extractor."""
        self._stopwords: AbstractSet[str] = (
            stopwords if stopwords is not None else STOPWORDS
        )

    def extract_compounds(self, text: str, top_k: int = 5) -> List[str]:
        """Extract top compound technical phrases based on frequency and length."""
        if _is_empty_text(text):
            return []

        candidates = _extract_candidates(text, self._stopwords)
        if not candidates:
            return []

        counts = _count_candidates(candidates)
        scored = _score_all_candidates(counts)
        return [t[0] for t in scored[:top_k]]
