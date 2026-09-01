#!/usr/bin/env python3
"""
Lucene-style Tokenizer pipeline.
Breaks character stream into discrete tokens with offset tracking.
"""

import re
from typing import List


class Token:
    """Represents a term token with position and character offsets."""

    def __init__(
        self, text: str, start_offset: int = 0, end_offset: int = 0, pos_incr: int = 1
    ) -> None:
        self.text = text
        self.start_offset = start_offset
        self.end_offset = end_offset
        self.pos_incr = pos_incr

    def __repr__(self) -> str:
        return f"Token('{self.text}', [{self.start_offset}:{self.end_offset}], pos={self.pos_incr})"


class Tokenizer:
    """Base class for Tokenizers."""

    def tokenize(self, text: str) -> List[Token]:
        raise NotImplementedError


class StandardTokenizer(Tokenizer):
    """
    Standard whitespace and punctuation tokenizer supporting alphanumeric words and CJK n-grams.
    """

    WORD_PATTERN = re.compile(r"[a-zA-Z0-9_\-]+", re.UNICODE)
    CJK_PATTERN = re.compile(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]+", re.UNICODE)

    def _extract_cjk_bigrams(self, cjk_text: str, cjk_start: int, tokens: List[Token]) -> None:
        tokens.append(Token(cjk_text, cjk_start, cjk_start + len(cjk_text), 1))
        if len(cjk_text) > 1:
            for i in range(len(cjk_text) - 1):
                bg = cjk_text[i : i + 2]
                tokens.append(Token(bg, cjk_start + i, cjk_start + i + 2, 0))

    def tokenize(self, text: str) -> List[Token]:
        if not text:
            return []

        tokens: List[Token] = [
            Token(m.group(0), m.start(), m.end(), 1)
            for m in self.WORD_PATTERN.finditer(text)
            if len(m.group(0)) > 0
        ]

        for m in self.CJK_PATTERN.finditer(text):
            self._extract_cjk_bigrams(m.group(0), m.start(), tokens)

        return tokens
