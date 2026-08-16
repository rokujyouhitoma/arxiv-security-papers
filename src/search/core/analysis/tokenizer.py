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

    def tokenize(self, text: str) -> List[Token]:
        if not text:
            return []

        tokens: List[Token] = []
        # Match western words with character offsets
        for m in self.WORD_PATTERN.finditer(text):
            tok_text = m.group(0)
            if len(tok_text) > 0:
                tokens.append(Token(tok_text, m.start(), m.end(), 1))

        # Match Japanese/CJK phrases and generate character bigrams
        for m in self.CJK_PATTERN.finditer(text):
            cjk_text = m.group(0)
            cjk_start = m.start()
            # Whole word token
            tokens.append(Token(cjk_text, cjk_start, m.end(), 1))
            # Bigrams
            if len(cjk_text) > 1:
                for i in range(len(cjk_text) - 1):
                    bg = cjk_text[i : i + 2]
                    tokens.append(Token(bg, cjk_start + i, cjk_start + i + 2, 0))

        return tokens
