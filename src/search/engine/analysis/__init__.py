#!/usr/bin/env python3
"""
Analysis Pipeline for Core Search Engine (Lucene Paradigm).
Provides CharFilter, Tokenizer, TokenFilter, and Analyzers (including CJK / Japanese Bigram support).
"""

import re
import unicodedata
from abc import ABC, abstractmethod
from typing import Dict, List, Optional, Set


class CharFilter(ABC):
    """Abstract base class for character filters."""

    @abstractmethod
    def filter(self, text: str) -> str:
        """Transforms the input text."""
        raise NotImplementedError


class HTMLStripCharFilter(CharFilter):
    """Strips HTML/XML tags and decodes common entities."""

    _TAG_RE = re.compile(r"<[^>]+>")

    def filter(self, text: str) -> str:
        cleaned = self._TAG_RE.sub(" ", text)
        return unicodedata.normalize("NFKC", cleaned)


class MappingCharFilter(CharFilter):
    """Maps custom character sequences to replacements."""

    def __init__(self, mapping: Optional[Dict[str, str]] = None) -> None:
        self.mapping = mapping or {}

    def filter(self, text: str) -> str:
        result = text
        for src, dst in self.mapping.items():
            result = result.replace(src, dst)
        return result


class Tokenizer(ABC):
    """Abstract base class for tokenizers."""

    @abstractmethod
    def tokenize(self, text: str) -> List[str]:
        """Splits text into a sequence of token strings."""
        raise NotImplementedError


class StandardTokenizer(Tokenizer):
    """Standard alphanumeric & symbol tokenizer."""

    _WORD_RE = re.compile(
        r"[A-Za-z0-9_\-\./]+|[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]+"
    )

    def tokenize(self, text: str) -> List[str]:
        return self._WORD_RE.findall(text)


class CJKBigramTokenizer(Tokenizer):
    """
    Tokenizer with CJK 2-gram (Bi-gram) generation for Japanese/Chinese/Korean text,
    and standard word tokenization for Latin/alphanumeric words.
    """

    _LATIN_RE = re.compile(r"[A-Za-z0-9_\-]+")
    _CJK_RE = re.compile(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]")

    def tokenize(self, text: str) -> List[str]:
        tokens: List[str] = []
        # Extract latin words
        for match in self._LATIN_RE.finditer(text):
            tokens.append(match.group(0))

        # Extract CJK characters and generate 2-grams
        cjk_chars = self._CJK_RE.findall(text)
        if len(cjk_chars) == 1:
            tokens.append(cjk_chars[0])
        else:
            for i in range(len(cjk_chars) - 1):
                tokens.append(cjk_chars[i] + cjk_chars[i + 1])
        return tokens


class TokenFilter(ABC):
    """Abstract base class for token filters."""

    @abstractmethod
    def filter(self, tokens: List[str]) -> List[str]:
        """Filters or modifies a token stream."""
        raise NotImplementedError


class LowerCaseFilter(TokenFilter):
    """Converts tokens to lowercase."""

    def filter(self, tokens: List[str]) -> List[str]:
        return [t.lower() for t in tokens]


class StopFilter(TokenFilter):
    """Removes common stop words."""

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
        "の",
        "に",
        "は",
        "を",
        "た",
        "が",
        "で",
        "て",
        "と",
        "し",
        "れ",
        "さ",
        "ある",
        "いる",
    }

    def __init__(self, stop_words: Optional[Set[str]] = None) -> None:
        self.stop_words = (
            stop_words if stop_words is not None else self.DEFAULT_STOP_WORDS
        )

    def filter(self, tokens: List[str]) -> List[str]:
        return [t for t in tokens if t.lower() not in self.stop_words]


class PorterStemFilter(TokenFilter):
    """Simplified Porter Stemmer token filter."""

    def filter(self, tokens: List[str]) -> List[str]:
        return [self._stem(t) for t in tokens]

    def _stem(self, word: str) -> str:
        w = word.lower()
        if len(w) <= 3:
            return w
        for suffix, rep in [
            ("sses", "ss"),
            ("ies", "i"),
            ("ational", "ate"),
            ("tional", "tion"),
            ("ing", ""),
            ("ed", ""),
            ("ly", ""),
            ("es", ""),
            ("s", ""),
        ]:
            if w.endswith(suffix) and len(w) - len(suffix) >= 3:
                return w[: -len(suffix)] + rep
        return w


class SynonymFilter(TokenFilter):
    """Security terminology synonym expander filter."""

    DEFAULT_SYNONYMS: Dict[str, List[str]] = {
        "ransomware": ["ランサムウェア", "身代金型マルウェア", "crypto-ransomware"],
        "zeroday": ["zero-day", "0-day", "ゼロデイ", "未公開脆弱性"],
        "sidechannel": ["side-channel", "サイドチャネル攻撃", "cache-timing"],
        "adversarial": ["adversarial-ml", "敵対的サンプル", "evasion-attack"],
        "postquantum": ["post-quantum", "pqc", "耐量子暗号", "lattice-cryptography"],
    }

    def __init__(self, synonym_map: Optional[Dict[str, List[str]]] = None) -> None:
        self.synonym_map = synonym_map or self.DEFAULT_SYNONYMS

    def filter(self, tokens: List[str]) -> List[str]:
        expanded: List[str] = []
        for t in tokens:
            expanded.append(t)
            clean = t.lower().replace("-", "").replace("_", "")
            if clean in self.synonym_map:
                expanded.extend(self.synonym_map[clean])
        return expanded


class Analyzer:
    """Combines CharFilters, a Tokenizer, and TokenFilters into an analysis pipeline."""

    def __init__(
        self,
        tokenizer: Optional[Tokenizer] = None,
        char_filters: Optional[List[CharFilter]] = None,
        token_filters: Optional[List[TokenFilter]] = None,
    ) -> None:
        self.char_filters = char_filters or [HTMLStripCharFilter()]
        self.tokenizer = tokenizer or StandardTokenizer()
        self.token_filters = token_filters or [LowerCaseFilter(), StopFilter()]

    def analyze(self, text: str) -> List[str]:
        current = text
        for cf in self.char_filters:
            current = cf.filter(current)
        tokens = self.tokenizer.tokenize(current)
        for tf in self.token_filters:
            tokens = tf.filter(tokens)
        return tokens


class StandardAnalyzer(Analyzer):
    """Default Standard Analyzer for alphanumeric text."""

    def __init__(self) -> None:
        super().__init__(
            tokenizer=StandardTokenizer(),
            char_filters=[HTMLStripCharFilter()],
            token_filters=[LowerCaseFilter(), StopFilter()],
        )


class CJKAnalyzer(Analyzer):
    """Bilingual Analyzer with CJK Bigram and Synonym Expansion."""

    def __init__(self) -> None:
        super().__init__(
            tokenizer=CJKBigramTokenizer(),
            char_filters=[HTMLStripCharFilter()],
            token_filters=[LowerCaseFilter(), StopFilter(), SynonymFilter()],
        )
