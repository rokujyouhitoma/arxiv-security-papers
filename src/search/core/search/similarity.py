#!/usr/bin/env python3
"""
Lucene-style BM25 Similarity & Scoring.
"""

import math


class Similarity:
    """Base abstract scoring class."""

    def score(
        self, term_freq: int, doc_len: int, avg_doc_len: float, idf: float
    ) -> float:
        raise NotImplementedError


class BM25Similarity(Similarity):
    """
    Okapi BM25 implementation conforming to Lucene's default similarity formula.
    """

    def __init__(self, k1: float = 1.5, b: float = 0.75) -> None:
        self.k1 = k1
        self.b = b

    def compute_idf(self, doc_freq: int, total_docs: int) -> float:
        if total_docs <= 0 or doc_freq <= 0:
            return 1.0
        # Lucene formula: log(1 + (N - n + 0.5) / (n + 0.5))
        return math.log(1.0 + (total_docs - doc_freq + 0.5) / (doc_freq + 0.5))

    def score(
        self, term_freq: int, doc_len: int, avg_doc_len: float, idf: float
    ) -> float:
        if term_freq <= 0:
            return 0.0
        avg_len = avg_doc_len if avg_doc_len > 0 else 1.0
        num = term_freq * (self.k1 + 1.0)
        denom = term_freq + self.k1 * (1.0 - self.b + self.b * (doc_len / avg_len))
        return idf * (num / denom)
