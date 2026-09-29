"""Graph-based TextRank Keyphrase Extraction Module.

Implements the PageRank mathematical graph algorithm for identifying
salient keywords and keyphrases in technical security documents.
Zero external dependencies. Fully compliant with KeyphraseExtractionSPI.
"""

import math
import re
from collections import defaultdict
from typing import AbstractSet, Dict, List, Optional, Sequence, Set, Tuple

from nlp.core.protocols import KeyphraseExtractionSPI
from nlp.lexicon.stop_words import STOPWORDS


def _tokenize_words(text: str) -> List[str]:
    """Tokenize text into lowercase alphanumeric words."""
    return re.findall(r"\b[a-zA-Z0-9_\-]{2,}\b", text.lower())


def _filter_window_tokens(
    tokens: Sequence[str], stopwords: AbstractSet[str]
) -> List[str]:
    """Filter out stopwords and short tokens."""
    return [t for t in tokens if len(t) > 2 and t not in stopwords]


def _build_edge_pairs(
    filtered: Sequence[str], window_size: int
) -> List[Tuple[str, str]]:
    """Generate undirected co-occurrence edges within window."""
    edges: List[Tuple[str, str]] = []
    n = len(filtered)
    for i in range(n):
        w1 = filtered[i]
        limit = min(i + window_size, n)
        for j in range(i + 1, limit):
            w2 = filtered[j]
            if w1 != w2:
                edges.append((w1, w2))
    return edges


def _populate_graph(
    edges: Sequence[Tuple[str, str]],
) -> Tuple[Dict[str, Set[str]], Dict[str, float]]:
    """Build adjacency set and initial uniform score dictionary."""
    graph: Dict[str, Set[str]] = defaultdict(set)
    for w1, w2 in edges:
        graph[w1].add(w2)
        graph[w2].add(w1)

    nodes = list(graph.keys())
    init_val = 1.0 / len(nodes) if nodes else 0.0
    scores = {node: init_val for node in nodes}
    return graph, scores


def _compute_node_rank(
    neighbors: Set[str],
    graph: Dict[str, Set[str]],
    scores: Dict[str, float],
    damping: float,
    teleport: float,
) -> float:
    """Calculate single node PageRank value."""
    incoming = 0.0
    for neighbor in neighbors:
        degree = len(graph[neighbor])
        if degree > 0:
            incoming += scores[neighbor] / degree
    return teleport + damping * incoming


def _pagerank_step(
    graph: Dict[str, Set[str]],
    scores: Dict[str, float],
    damping: float,
    num_nodes: int,
) -> Tuple[Dict[str, float], float]:
    """Execute a single PageRank power iteration step."""
    teleport = (1.0 - damping) / num_nodes if num_nodes > 0 else 0.0
    new_scores: Dict[str, float] = {}
    max_diff = 0.0

    for node, neighbors in graph.items():
        new_val = _compute_node_rank(neighbors, graph, scores, damping, teleport)
        diff = math.fabs(new_val - scores[node])
        if diff > max_diff:
            max_diff = diff
        new_scores[node] = new_val

    return new_scores, max_diff


def _run_pagerank(
    graph: Dict[str, Set[str]],
    init_scores: Dict[str, float],
    damping: float = 0.85,
    max_iter: int = 50,
    tol: float = 1e-4,
) -> Dict[str, float]:
    """Execute power iterations until convergence or maximum iterations."""
    num_nodes = len(graph)
    if num_nodes == 0:
        return {}

    scores = init_scores.copy()
    for _ in range(max_iter):
        scores, max_diff = _pagerank_step(graph, scores, damping, num_nodes)
        if max_diff < tol:
            break
    return scores


class TextRankKeywordExtractor(KeyphraseExtractionSPI):
    """Pure-Python graph-based keyword extractor using TextRank algorithm."""

    def __init__(
        self,
        stopwords: Optional[AbstractSet[str]] = None,
        window_size: int = 4,
        damping: float = 0.85,
    ) -> None:
        """Initialize TextRank extractor."""
        self._stopwords: AbstractSet[str] = (
            stopwords if stopwords is not None else STOPWORDS
        )
        self._window_size = window_size
        self._damping = damping

    def extract_keyphrases(self, text: str, top_k: int = 5) -> List[Tuple[str, float]]:
        """Extract top-k keyphrases paired with PageRank relevance scores."""
        if not text or not text.strip():
            return []

        tokens = _tokenize_words(text)
        filtered = _filter_window_tokens(tokens, self._stopwords)
        if not filtered:
            return []

        edges = _build_edge_pairs(filtered, self._window_size)
        graph, init_scores = _populate_graph(edges)
        scores = _run_pagerank(graph, init_scores, damping=self._damping)
        sorted_ranks = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        return sorted_ranks[:top_k]

    def extract(self, text: str, top_k: int = 5) -> List[Tuple[str, float]]:
        """Backward-compatible alias for extract_keyphrases."""
        return self.extract_keyphrases(text=text, top_k=top_k)
