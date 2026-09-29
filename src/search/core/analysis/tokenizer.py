#!/usr/bin/env python3
"""Lucene-style Tokenizer pipeline.

Breaks character stream into discrete tokens with offset tracking.
Supports standard alphanumeric, CJK n-grams, and pure-Python morphological analysis.
"""

import re
from typing import List, Optional

from nlp.morphology.viterbi_tokenizer import PureMorphTokenizer


class Token:
    """Represents a term token with position and character offsets."""

    def __init__(
        self, text: str, start_offset: int = 0, end_offset: int = 0, pos_incr: int = 1
    ) -> None:
        """Initialize term token."""
        self.text = text
        self.start_offset = start_offset
        self.end_offset = end_offset
        self.pos_incr = pos_incr

    def __repr__(self) -> str:
        """String representation of token."""
        return f"Token('{self.text}', [{self.start_offset}:{self.end_offset}], pos={self.pos_incr})"


class Tokenizer:
    """Base class for Tokenizers."""

    def tokenize(self, text: str) -> List[Token]:
        """Tokenize text into term tokens."""
        raise NotImplementedError


class MorphologyTokenizer(Tokenizer):
    """Tokenizer utilizing PureMorphTokenizer for semantic segmentation."""

    def __init__(self, pure_tokenizer: Optional[PureMorphTokenizer] = None) -> None:
        """Initialize with optional custom tokenizer."""
        self._tokenizer = pure_tokenizer or PureMorphTokenizer()

    def tokenize(self, text: str) -> List[Token]:
        """Segment input text into morphological tokens with offsets."""
        if not text:
            return []
        nlp_tokens = self._tokenizer.tokenize(text)
        return [
            Token(t.text, t.span.start, t.span.end, 1)
            for t in nlp_tokens
            if len(t.text.strip()) > 0
        ]


class StandardTokenizer(Tokenizer):
    """Standard whitespace and punctuation tokenizer supporting CJK analysis."""

    WORD_PATTERN = re.compile(r"[a-zA-Z0-9_\-]+", re.UNICODE)
    CJK_PATTERN = re.compile(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]+", re.UNICODE)

    def __init__(self, use_morphology: bool = False) -> None:
        """Initialize standard tokenizer with optional morphology mode."""
        self._use_morphology = use_morphology
        self._morph_tokenizer = PureMorphTokenizer() if use_morphology else None

    def _extract_cjk_bigrams(
        self, cjk_text: str, cjk_start: int, tokens: List[Token]
    ) -> None:
        """Extract full term and overlapping bigrams for CJK chunks."""
        tokens.append(Token(cjk_text, cjk_start, cjk_start + len(cjk_text), 1))
        if len(cjk_text) > 1:
            for i in range(len(cjk_text) - 1):
                bg = cjk_text[i : i + 2]
                tokens.append(Token(bg, cjk_start + i, cjk_start + i + 2, 0))

    def _extract_cjk_morphology(
        self, cjk_text: str, cjk_start: int, tokens: List[Token]
    ) -> None:
        """Extract morphological tokens for CJK chunks."""
        if self._morph_tokenizer is None:
            self._extract_cjk_bigrams(cjk_text, cjk_start, tokens)
            return
        m_tokens = self._morph_tokenizer.tokenize(cjk_text)
        for t in m_tokens:
            tokens.append(
                Token(
                    t.text,
                    cjk_start + t.span.start,
                    cjk_start + t.span.end,
                    1,
                )
            )

    def _extract_word_tokens(self, text: str) -> List[Token]:
        """Extract alphanumeric words from text."""
        return [
            Token(m.group(0), m.start(), m.end(), 1)
            for m in self.WORD_PATTERN.finditer(text)
        ]

    def _append_cjk_tokens(self, text: str, tokens: List[Token]) -> None:
        """Extract CJK tokens and append to tokens list."""
        extractor = (
            self._extract_cjk_morphology
            if self._use_morphology
            else self._extract_cjk_bigrams
        )
        for m in self.CJK_PATTERN.finditer(text):
            extractor(m.group(0), m.start(), tokens)

    def tokenize(self, text: str) -> List[Token]:
        """Tokenize source string into tokens."""
        if not text:
            return []
        tokens = self._extract_word_tokens(text)
        self._append_cjk_tokens(text, tokens)
        return tokens
