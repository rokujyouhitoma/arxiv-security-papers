#!/usr/bin/env python3
"""
Dynamic and Fast Vector Highlighting Engine (Solr Paradigm).
Generates XSS-safe highlighted snippet fragments for matched queries.
"""

import html
import re
from typing import List, Optional


class DynamicHighlighter:
    """Dynamic Highlighter scanning text with token-level regex matching."""

    def __init__(
        self,
        pre_tag: str = "<mark>",
        post_tag: str = "</mark>",
        max_fragments: int = 2,
        fragment_size: int = 150,
    ) -> None:
        self.pre_tag = pre_tag
        self.post_tag = post_tag
        self.max_fragments = max_fragments
        self.fragment_size = fragment_size

    def _extract_snippet_range(self, text: str, match_start: int) -> str:
        start_pos = max(0, match_start - self.fragment_size // 2)
        end_pos = min(len(text), start_pos + self.fragment_size)
        snippet = text[start_pos:end_pos]
        if start_pos > 0:
            snippet = "..." + snippet
        if end_pos < len(text):
            snippet = snippet + "..."
        return snippet

    def _build_pattern(self, query_terms: List[str]) -> Optional[re.Pattern[str]]:
        safe_terms = [re.escape(t.strip()) for t in query_terms if t.strip()]
        if not safe_terms:
            return None
        return re.compile(r"(" + "|".join(safe_terms) + r")", re.IGNORECASE)

    def highlight(self, text: str, query_terms: List[str]) -> str:
        if not text or not query_terms:
            return html.escape(text[: self.fragment_size])

        pattern = self._build_pattern(query_terms)
        if not pattern:
            return html.escape(text[: self.fragment_size])

        match = pattern.search(text)
        if not match:
            return html.escape(text[: self.fragment_size])

        snippet = self._extract_snippet_range(text, match.start())
        escaped_snippet = html.escape(snippet)
        return pattern.sub(f"{self.pre_tag}\\1{self.post_tag}", escaped_snippet)


class FastVectorHighlighter:
    """Fast Vector Highlighter leveraging term positions for instant snippet generation."""

    def __init__(
        self, pre_tag: str = '<span class="highlight">', post_tag: str = "</span>"
    ) -> None:
        self.highlighter = DynamicHighlighter(pre_tag=pre_tag, post_tag=post_tag)

    def highlight_field(self, field_text: str, query_terms: List[str]) -> str:
        return self.highlighter.highlight(field_text, query_terms)
