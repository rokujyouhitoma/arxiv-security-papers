#!/usr/bin/env python3
"""NLP Keyword & Keyphrase Extractor Module.

Pure-Python implementation of Graph-based TextRank and C-Value compound
term extraction algorithms.
Designed for future promotion to `src/nlp/` generic package.
"""

import math
import re
from collections import defaultdict
from typing import Dict, List, Optional, Set, Tuple

DEFAULT_STOPWORDS: Set[str] = {
    "a",
    "about",
    "above",
    "after",
    "again",
    "against",
    "all",
    "am",
    "an",
    "and",
    "any",
    "are",
    "aren't",
    "as",
    "at",
    "be",
    "because",
    "been",
    "before",
    "being",
    "below",
    "between",
    "both",
    "but",
    "by",
    "can't",
    "cannot",
    "could",
    "couldn't",
    "did",
    "didn't",
    "do",
    "does",
    "doesn't",
    "doing",
    "don't",
    "down",
    "during",
    "each",
    "few",
    "for",
    "from",
    "further",
    "had",
    "hadn't",
    "has",
    "hasn't",
    "have",
    "haven't",
    "having",
    "he",
    "he'd",
    "he'll",
    "he's",
    "her",
    "here",
    "here's",
    "hers",
    "herself",
    "him",
    "himself",
    "his",
    "how",
    "how's",
    "i",
    "i'd",
    "i'll",
    "i'm",
    "i've",
    "if",
    "in",
    "into",
    "is",
    "isn't",
    "it",
    "it's",
    "its",
    "itself",
    "let's",
    "me",
    "more",
    "most",
    "mustn't",
    "my",
    "myself",
    "no",
    "nor",
    "not",
    "of",
    "off",
    "on",
    "once",
    "only",
    "or",
    "other",
    "ought",
    "our",
    "ours",
    "ourselves",
    "out",
    "over",
    "own",
    "same",
    "shan't",
    "she",
    "she'd",
    "she'll",
    "she's",
    "should",
    "shouldn't",
    "so",
    "some",
    "such",
    "than",
    "that",
    "that's",
    "the",
    "their",
    "theirs",
    "them",
    "themselves",
    "then",
    "there",
    "there's",
    "these",
    "they",
    "they'd",
    "they'll",
    "they're",
    "they've",
    "this",
    "those",
    "through",
    "to",
    "too",
    "under",
    "until",
    "up",
    "very",
    "was",
    "wasn't",
    "we",
    "we'd",
    "we'll",
    "we're",
    "we've",
    "were",
    "weren't",
    "what",
    "what's",
    "when",
    "when's",
    "where",
    "where's",
    "which",
    "while",
    "who",
    "who's",
    "whom",
    "why",
    "why's",
    "with",
    "won't",
    "would",
    "wouldn't",
    "you",
    "you'd",
    "you'll",
    "you're",
    "you've",
    "your",
    "yours",
    "yourself",
    "yourselves",
    "paper",
    "propose",
    "proposed",
    "present",
    "presents",
    "show",
    "shows",
    "study",
    "approach",
    "method",
    "system",
    "model",
    "framework",
    "results",
    "evaluation",
    "analysis",
    "using",
    "based",
    "via",
    "toward",
    "towards",
    "new",
    "novel",
    "effective",
    "comprehensive",
    "robust",
}


def _tokenize(text: str) -> List[str]:
    """Tokenizes text into lowercase alphanumeric tokens."""
    return re.findall(r"\b[a-zA-Z0-9_\-\$]{2,}\b", text.lower())


def _add_edges_for_token(
    graph: Dict[str, Set[str]],
    filtered: List[str],
    i: int,
    window_size: int,
) -> None:
    """Adds co-occurrence edges from token i within window size."""
    w1 = filtered[i]
    limit = min(i + window_size, len(filtered))
    for j in range(i + 1, limit):
        w2 = filtered[j]
        if w1 != w2:
            graph[w1].add(w2)
            graph[w2].add(w1)


def _filter_tokens(tokens: List[str], stopwords: Set[str]) -> List[str]:
    """Filters stop words and single-character tokens."""
    return [w for w in tokens if w not in stopwords and len(w) > 2]


def _build_cooccurrence_graph(
    tokens: List[str], window_size: int, stopwords: Set[str]
) -> Tuple[Dict[str, Set[str]], Dict[str, float]]:
    """Constructs undirected word co-occurrence graph."""
    graph: Dict[str, Set[str]] = defaultdict(set)
    filtered = _filter_tokens(tokens, stopwords)

    for i in range(len(filtered)):
        _add_edges_for_token(graph, filtered, i, window_size)

    return graph, {node: 1.0 for node in graph}


def _compute_node_rank(
    graph: Dict[str, Set[str]],
    scores: Dict[str, float],
    node: str,
    damping: float,
    num_nodes: int,
) -> float:
    """Computes updated rank score for a single graph node."""
    rank_sum = sum(
        scores[neighbor] / len(graph[neighbor])
        for neighbor in graph[node]
        if len(graph[neighbor]) > 0
    )
    return (1.0 - damping) / num_nodes + damping * rank_sum


def _run_pagerank_iteration(
    graph: Dict[str, Set[str]],
    scores: Dict[str, float],
    damping: float,
    num_nodes: int,
) -> Tuple[Dict[str, float], float]:
    """Runs single PageRank iteration step and computes max delta."""
    new_scores = {
        n: _compute_node_rank(graph, scores, n, damping, num_nodes) for n in graph
    }
    max_diff = max((abs(new_scores[n] - scores[n]) for n in graph), default=0.0)
    return new_scores, max_diff


def _run_pagerank(
    graph: Dict[str, Set[str]],
    scores: Dict[str, float],
    damping: float = 0.85,
    max_iter: int = 30,
    tol: float = 1e-4,
) -> Dict[str, float]:
    """Executes PageRank algorithm on the co-occurrence graph."""
    if not graph:
        return {}

    num_nodes = len(graph)
    for _ in range(max_iter):
        scores, max_diff = _run_pagerank_iteration(graph, scores, damping, num_nodes)
        if max_diff < tol:
            break
    return scores


class TextRankKeywordExtractor:
    """Graph-based keyword extractor using TextRank algorithm."""

    def __init__(
        self,
        stopwords: Optional[Set[str]] = None,
        window_size: int = 4,
        damping: float = 0.85,
    ) -> None:
        self.stopwords = stopwords or DEFAULT_STOPWORDS
        self.window_size = window_size
        self.damping = damping

    def extract(self, text: str, top_k: int = 5) -> List[Tuple[str, float]]:
        """Extracts top_k keywords with their PageRank scores."""
        if not text or not text.strip():
            return []
        tokens = _tokenize(text)
        graph, init_scores = _build_cooccurrence_graph(
            tokens, self.window_size, self.stopwords
        )
        scores = _run_pagerank(graph, init_scores, damping=self.damping)
        sorted_keywords = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        return sorted_keywords[:top_k]


def _is_valid_compound(clean: str, stopwords: Set[str]) -> bool:
    """Checks if compound phrase is valid and not dominated by stopwords."""
    words = clean.lower().split()
    if len(words) < 2:
        return False
    return not any(w in stopwords for w in words)


class CValueExtractor:
    """Extracts compound multi-word technical phrases (C-Value method)."""

    def __init__(self, stopwords: Optional[Set[str]] = None) -> None:
        self.stopwords = stopwords or DEFAULT_STOPWORDS

    def _extract_candidates(self, text: str) -> List[str]:
        """Extracts candidate multi-word technical terms matching patterns."""
        patterns = [
            r"\b[A-Z][a-z0-9]+(?:\s+[A-Z][a-z0-9]+)+\b",
            r"\b[a-zA-Z0-9]+-[a-zA-Z0-9]+(?:\s+[a-zA-Z0-9]+)?\b",
        ]
        candidates: List[str] = []
        for pat in patterns:
            for match in re.findall(pat, text):
                clean = match.strip()
                if _is_valid_compound(clean, self.stopwords):
                    candidates.append(clean)
        return candidates

    def extract_compounds(self, text: str, top_k: int = 5) -> List[str]:
        """Extracts top compound technical phrases based on frequency and length."""
        candidates = self._extract_candidates(text)
        if not candidates:
            return []

        counts: Dict[str, int] = defaultdict(int)
        for c in candidates:
            counts[c] += 1

        scored: List[Tuple[str, float]] = []
        for term, freq in counts.items():
            length = len(term.split())
            score = math.log2(length + 1) * freq
            scored.append((term, score))

        scored.sort(key=lambda x: x[1], reverse=True)
        return [t[0] for t in scored[:top_k]]


def _append_unique_phrase(results: List[str], seen: Set[str], phrase: str) -> None:
    """Appends phrase to results if not already present."""
    norm = phrase.lower()
    if norm not in seen:
        results.append(phrase)
        seen.add(norm)


def _merge_keyphrase_results(
    compounds: List[str], ranked: List[Tuple[str, float]], top_k: int
) -> List[str]:
    """Combines compound phrases and single-word TextRank results."""
    results: List[str] = []
    seen: Set[str] = set()

    for comp in compounds:
        _append_unique_phrase(results, seen, comp)

    for word, _score in ranked:
        if len(results) >= top_k:
            break
        _append_unique_phrase(results, seen, word)

    return results[:top_k]


def extract_keyphrases(
    text: str,
    top_k: int = 5,
    include_compounds: bool = True,
    stopwords: Optional[Set[str]] = None,
) -> List[str]:
    """Universal high-level API to extract top technical keyphrases from text."""
    if not text or not text.strip():
        return []

    compounds = (
        CValueExtractor(stopwords=stopwords).extract_compounds(text, top_k=top_k)
        if include_compounds
        else []
    )
    ranked = TextRankKeywordExtractor(stopwords=stopwords).extract(
        text, top_k=top_k * 2
    )

    return _merge_keyphrase_results(compounds, ranked, top_k)
