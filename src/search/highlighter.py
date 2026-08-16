#!/usr/bin/env python3
"""
Dynamic Snippet Highlighter for Enterprise Search Engine.
Extracts context snippets around query hits with safe HTML-escaped highlight tags.
"""

import html
import re
from typing import List


class DynamicHighlighter:
    """
    Extracts relevant snippets and highlights query terms safely.
    """

    def __init__(
        self,
        pre_tag: str = '<mark class="highlight">',
        post_tag: str = "</mark>",
        snippet_length: int = 160,
    ) -> None:
        self.pre_tag = pre_tag
        self.post_tag = post_tag
        self.snippet_length = snippet_length

    def highlight(
        self, text: str, query_terms: List[str]
    ) -> str:
        """
        Extracts the most relevant snippet from text and applies highlight tags.
        """
        if not text or not query_terms:
            safe_text = html.escape(text[: self.snippet_length])
            return safe_text + ("..." if len(text) > self.snippet_length else "")

        # Clean query terms
        terms = [
            re.escape(t.lower().strip())
            for t in query_terms
            if len(t.strip()) >= 2
        ]
        if not terms:
            safe_text = html.escape(text[: self.snippet_length])
            return safe_text + ("..." if len(text) > self.snippet_length else "")

        pattern = re.compile(r"(" + "|".join(terms) + r")", re.IGNORECASE)

        # Find first match position
        first_match = pattern.search(text)
        if not first_match:
            safe_text = html.escape(text[: self.snippet_length])
            return safe_text + ("..." if len(text) > self.snippet_length else "")

        # Calculate snippet window around match
        match_start = first_match.start()
        half_len = self.snippet_length // 2
        snippet_start = max(0, match_start - half_len)
        snippet_end = min(len(text), snippet_start + self.snippet_length)
        if snippet_end - snippet_start < self.snippet_length and snippet_start > 0:
            snippet_start = max(0, snippet_end - self.snippet_length)

        raw_snippet = text[snippet_start:snippet_end]

        # Escape HTML first to prevent XSS
        escaped_snippet = html.escape(raw_snippet)

        # Highlight matched terms in escaped text
        escaped_terms = [
            re.escape(html.escape(t.lower().strip()))
            for t in query_terms
            if len(t.strip()) >= 2
        ]
        if escaped_terms:
            hl_pattern = re.compile(
                r"(" + "|".join(escaped_terms) + r")", re.IGNORECASE
            )
            highlighted = hl_pattern.sub(
                f"{self.pre_tag}\\1{self.post_tag}", escaped_snippet
            )
        else:
            highlighted = escaped_snippet

        prefix = "..." if snippet_start > 0 else ""
        suffix = "..." if snippet_end < len(text) else ""
        return f"{prefix}{highlighted}{suffix}"
