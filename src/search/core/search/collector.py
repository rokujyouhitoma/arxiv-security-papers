#!/usr/bin/env python3
"""
Lucene-style TopDocs and ScoreDoc Collector.
"""

from typing import List


class ScoreDoc:
    """Represents a scored search hit."""

    def __init__(self, doc_id: str, score: float) -> None:
        self.doc_id = doc_id
        self.score = score

    def __repr__(self) -> str:
        return f"ScoreDoc(id='{self.doc_id}', score={self.score:.4f})"


class TopDocs:
    """Contains total hit count and top scored documents."""

    def __init__(self, total_hits: int, score_docs: List[ScoreDoc]) -> None:
        self.total_hits = total_hits
        self.score_docs = score_docs


class TopDocsCollector:
    """Collects and ranks top-k scored documents."""

    def __init__(self, top_k: int = 10) -> None:
        self.top_k = top_k
        self.hits: List[ScoreDoc] = []

    def collect(self, doc_id: str, score: float) -> None:
        if score > 0:
            self.hits.append(ScoreDoc(doc_id, score))

    def get_top_docs(self) -> TopDocs:
        self.hits.sort(key=lambda x: x.score, reverse=True)
        return TopDocs(len(self.hits), self.hits[: self.top_k])
