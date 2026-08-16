#!/usr/bin/env python3
"""
Lucene-style CharFilter pipeline.
Preprocesses input raw text stream prior to Tokenization (e.g. HTML stripping, Unicode normalization).
"""

import html
import re
import unicodedata


class CharFilter:
    """Base class for Character Filters."""

    def filter(self, text: str) -> str:
        raise NotImplementedError


class HTMLStripCharFilter(CharFilter):
    """Strips HTML tags and unescapes entities."""

    def filter(self, text: str) -> str:
        if not text:
            return ""
        # Remove HTML tags
        clean = re.sub(r"<[^>]+>", " ", text)
        return html.unescape(clean)


class UnicodeNormalizeCharFilter(CharFilter):
    """Normalizes Unicode text to NFKC form (unifying zenkaku/hankaku)."""

    def filter(self, text: str) -> str:
        if not text:
            return ""
        return unicodedata.normalize("NFKC", text)
