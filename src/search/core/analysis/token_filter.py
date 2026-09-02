#!/usr/bin/env python3
"""
Lucene-style TokenFilter pipeline.
Applies transformations, stop words, lowercasing, and synonym expansions on token streams.
"""

from typing import Any, List, Optional, Set

from .tokenizer import Token


class TokenFilter:
    """Base class for Token Filters."""

    def filter_tokens(self, tokens: List[Token]) -> List[Token]:
        raise NotImplementedError


class LowerCaseFilter(TokenFilter):
    """Converts token text to lowercase."""

    def filter_tokens(self, tokens: List[Token]) -> List[Token]:
        return [
            Token(t.text.lower(), t.start_offset, t.end_offset, t.pos_incr)
            for t in tokens
        ]


class StopWordFilter(TokenFilter):
    """Removes common stop words from token stream."""

    DEFAULT_STOP_WORDS: Set[str] = {
        "a",
        "an",
        "and",
        "are",
        "as",
        "at",
        "be",
        "but",
        "by",
        "for",
        "if",
        "in",
        "into",
        "is",
        "it",
        "no",
        "not",
        "of",
        "on",
        "or",
        "such",
        "that",
        "the",
        "their",
        "then",
        "there",
        "these",
        "they",
        "this",
        "to",
        "was",
        "will",
        "with",
        "て",
        "に",
        "を",
        "は",
        "が",
        "の",
        "と",
    }

    def __init__(self, stop_words: Optional[Set[str]] = None) -> None:
        self.stop_words = (
            stop_words if stop_words is not None else self.DEFAULT_STOP_WORDS
        )

    def filter_tokens(self, tokens: List[Token]) -> List[Token]:
        return [t for t in tokens if t.text.lower() not in self.stop_words]


class Analyzer:
    """
    Complete analysis pipeline composing CharFilters, Tokenizer, and TokenFilters.
    """

    def __init__(
        self,
        char_filters: Optional[List[Any]] = None,
        tokenizer: Optional[Any] = None,
        token_filters: Optional[List[TokenFilter]] = None,
    ) -> None:
        self.char_filters = char_filters or []
        self.tokenizer = tokenizer
        self.token_filters = token_filters or []

    def _apply_char_filters(self, text: str) -> str:
        processed = text
        for cf in self.char_filters:
            if hasattr(cf, "filter"):
                processed = cf.filter(processed)
        return processed

    def _get_tokenizer(self) -> Any:
        if self.tokenizer is not None:
            return self.tokenizer
        from .tokenizer import StandardTokenizer

        return StandardTokenizer()

    def analyze(self, text: str) -> List[Token]:
        """Runs full analysis chain on input text."""
        if not text:
            return []

        processed = self._apply_char_filters(text)
        tokenizer = self._get_tokenizer()
        tokens: List[Token] = tokenizer.tokenize(processed)

        for tf in self.token_filters:
            tokens = tf.filter_tokens(tokens)

        return tokens
