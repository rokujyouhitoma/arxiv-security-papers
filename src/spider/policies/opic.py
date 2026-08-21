"""On-line Page Importance Computation (OPIC) and Topic-Focused Relevance Scorer."""

from __future__ import annotations

import re
from collections import defaultdict
from typing import DefaultDict, Sequence, Set


class OpicCalculator:
    """Implements On-line Page Importance Computation (OPIC) cash propagation."""

    def __init__(self, initial_cash: float = 1.0) -> None:
        self.initial_cash: float = initial_cash
        self._cash: DefaultDict[str, float] = defaultdict(lambda: self.initial_cash)
        self._history: DefaultDict[str, float] = defaultdict(float)

    def get_cash(self, url: str) -> float:
        return self._cash[url]

    def get_history(self, url: str) -> float:
        return self._history[url]

    def visit(self, url: str, out_links: Sequence[str]) -> None:
        """Transfers cash from visited page to its outgoing links."""
        current_cash = self._cash[url]
        self._history[url] += current_cash
        self._cash[url] = 0.0

        if out_links and current_cash > 0:
            share = current_cash / len(out_links)
            for link in out_links:
                self._cash[link] += share


class TopicRelevanceScorer:
    """Calculates security domain keyword relevance score for focused crawling."""

    SECURITY_TERMS: Set[str] = {
        "security",
        "vulnerability",
        "cryptography",
        "exploit",
        "attack",
        "malware",
        "ransomware",
        "zero-trust",
        "cve",
        "authentication",
        "encryption",
        "privacy",
        "adversarial",
        "side-channel",
        "patch",
        "firmware",
        "protocol",
        "audit",
    }

    @classmethod
    def score_text(cls, text: str) -> float:
        """Calculates security topic relevance score [0.0, 1.0]."""
        if not text:
            return 0.0
        words = re.findall(r"\b[a-zA-Z_-]+\b", text.lower())
        if not words:
            return 0.0

        matches = sum(1 for w in words if w in cls.SECURITY_TERMS)
        ratio = matches / len(words)
        return min(1.0, ratio * 10.0)

    @classmethod
    def is_relevant(cls, text: str, threshold: float = 0.05) -> bool:
        return cls.score_text(text) >= threshold
