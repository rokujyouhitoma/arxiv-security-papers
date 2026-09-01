#!/usr/bin/env python3
"""
Multi-Stage Analyzer Pipeline for Enterprise Search Engine.
Provides Tokenization, Unicode/Case Normalization, Japanese Morph/NGram, Edge-N-Gram, and Synonym Expansion.
"""

import re
from typing import List

from ..query.synonym_expander import SynonymExpander


class TokenOffset:
    """Represents a token with text and start/end character offsets."""

    def __init__(self, text: str, start: int, end: int) -> None:
        self.text = text
        self.start = start
        self.end = end

    def __repr__(self) -> str:
        return f"Token({self.text}, [{self.start}:{self.end}])"


class SearchAnalyzer:
    """
    Enterprise Text Analyzer with multi-stage filter pipeline.
    """

    def __init__(self) -> None:
        self.expander = SynonymExpander()

    def _extract_ja_ngrams(self, ja_w: str, tokens: List[str]) -> None:
        ja_lower = ja_w.lower()
        tokens.append(ja_lower)
        if len(ja_w) >= 2:
            for i in range(len(ja_w) - 1):
                tokens.append(ja_lower[i : i + 2])
        if len(ja_w) >= 3:
            for i in range(len(ja_w) - 2):
                tokens.append(ja_lower[i : i + 3])

    def tokenize(self, text: str) -> List[str]:
        """
        Tokenizes text into normalized words, Japanese n-grams, and sub-tokens.
        """
        if not text:
            return []

        tokens: List[str] = []
        text_lower = text.lower()
        words = re.findall(r"[a-zA-Z0-9_\-]+", text_lower)
        tokens.extend(words)

        ja_words = re.findall(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]+", text)
        for ja_w in ja_words:
            self._extract_ja_ngrams(ja_w, tokens)

        return tokens

    def _extract_ja_offsets(self, m: re.Match[str], token_offsets: List[TokenOffset]) -> None:
        ja_str = m.group(0)
        base_start = m.start()
        token_offsets.append(TokenOffset(ja_str.lower(), base_start, m.end()))
        if len(ja_str) >= 2:
            for i in range(len(ja_str) - 1):
                token_offsets.append(
                    TokenOffset(
                        ja_str[i : i + 2].lower(),
                        base_start + i,
                        base_start + i + 2,
                    )
                )

    def tokenize_with_offsets(self, text: str) -> List[TokenOffset]:
        """
        Tokenizes text and records character offsets for precise highlighting.
        """
        if not text:
            return []

        token_offsets: List[TokenOffset] = []
        for m in re.finditer(r"[a-zA-Z0-9_\-]+", text):
            token_offsets.append(TokenOffset(m.group(0).lower(), m.start(), m.end()))

        for m in re.finditer(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]+", text):
            self._extract_ja_offsets(m, token_offsets)

        return token_offsets

    def expand_synonyms(self, query: str) -> List[str]:
        """Expands query terms with security domain synonyms."""
        return self.expander.expand_query(query)
