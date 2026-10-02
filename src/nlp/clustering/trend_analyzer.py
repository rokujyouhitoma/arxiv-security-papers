"""Macro Security Trend Analyzer and Mermaid Mindmap Synthesis Engine.

Identifies emerging surges, synthesizes structured Japanese executive insights,
and generates sanitized Mermaid mindmaps across dynamic topic clusters.
Zero external dependencies, Xenon CC <= 3, and Mypy strict compliant.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Sequence, Tuple

from nlp.core.tokens import TopicCluster

_DISALLOWED_MERMAID_CHARS = re.compile(r'["()\[\]{};:<>]')


def _sanitize_mermaid_text(text: str, max_length: int = 25) -> str:
    """Sanitize and truncate text safely for Mermaid mindmap rendering."""
    cleaned = _DISALLOWED_MERMAID_CHARS.sub(" ", text).strip()
    cleaned = re.sub(r"\s+", " ", cleaned)
    if len(cleaned) > max_length:
        return f"{cleaned[:max_length]}..."
    return cleaned


def _format_paper_title(paper: Dict[str, Any]) -> str:
    """Format single paper title with quotes for Japanese insight text."""
    title = str(paper.get("title_ja") or paper.get("title") or "")
    clean = title.strip()
    return f"「{clean[:30]}...」" if len(clean) > 30 else f"「{clean}」"


def _build_cluster_insight_bullet(
    label: str, count: int, top_papers: List[Dict[str, Any]]
) -> str:
    """Construct bullet point summarizing papers within a single cluster."""
    titles = [_format_paper_title(p) for p in top_papers[:2]]
    joined_titles = "、".join(titles) if titles else "複数研究"
    return (
        f"- **{label}** ({count} 件): "
        f"注目論文として {joined_titles} 等が発表され、実務防御および攻撃検証の進展が見られます。"
    )


def _render_mindmap_node(label: str, count: int) -> str:
    """Render cluster node for Mermaid mindmap."""
    safe_label = _sanitize_mermaid_text(label, max_length=30)
    return f'    ["{safe_label} ({count}件)"]'


def _render_mindmap_leaf(paper: Dict[str, Any]) -> str:
    """Render paper leaf node for Mermaid mindmap."""
    title = str(paper.get("title_ja") or paper.get("title") or "")
    safe_title = _sanitize_mermaid_text(title, max_length=25)
    return f'      ["{safe_title}"]'


def _build_mermaid_mindmap_tree(
    cluster_pairs: List[Tuple[TopicCluster, List[Dict[str, Any]]]],
    date_str: str,
) -> str:
    """Construct complete Mermaid mindmap diagram string."""
    safe_date = _sanitize_mermaid_text(date_str, max_length=20)
    lines: List[str] = [
        "```mermaid",
        "mindmap",
        f'  root["セキュリティ動向 ({safe_date})"]',
    ]
    for cluster, papers in cluster_pairs[:5]:
        lines.append(_render_mindmap_node(cluster.label, len(papers)))
        for p in papers[:2]:
            lines.append(_render_mindmap_leaf(p))
    lines.append("```")
    return "\n".join(lines)


def _index_single_id(
    indexed: Dict[str, Dict[str, Any]], key_val: Any, paper: Dict[str, Any]
) -> None:
    """Store paper under string representation of key_val if present."""
    if key_val:
        indexed[str(key_val)] = paper


def _register_paper_keys(
    indexed: Dict[str, Dict[str, Any]], paper: Dict[str, Any], idx: int
) -> None:
    """Register all available keys for a paper in index."""
    _index_single_id(indexed, paper.get("clean_id"), paper)
    _index_single_id(indexed, paper.get("arxiv_id"), paper)
    indexed[f"doc_{idx}"] = paper


def _index_papers_by_id(papers: Sequence[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """Index papers by all possible ID keys."""
    indexed: Dict[str, Dict[str, Any]] = {}
    for idx, p in enumerate(papers):
        _register_paper_keys(indexed, p, idx)
    return indexed


def _resolve_papers_for_cluster(
    cluster: TopicCluster, indexed: Dict[str, Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """Map document IDs in a TopicCluster back to paper dictionaries."""
    matched: List[Dict[str, Any]] = []
    for did in cluster.document_ids:
        if did in indexed and indexed[did] not in matched:
            matched.append(indexed[did])
    return matched


class TrendAnalyzer:
    """Trend Analyzer and Synthesis Engine for dynamic cybersecurity clusters."""

    def __init__(self, max_top_clusters: int = 5) -> None:
        """Initialize TrendAnalyzer."""
        self._max_top_clusters = max_top_clusters

    def synthesize_macro_insights(
        self,
        cluster_pairs: List[Tuple[TopicCluster, List[Dict[str, Any]]]],
        total_papers: int,
    ) -> str:
        """Synthesize Japanese macro trend executive summary prose."""
        if total_papers == 0:
            return "本日の対象論文はありません。"

        bullets: List[str] = [
            f"本日の収集論文（計 {total_papers} 件）において、"
            f"以下の重点セキュリティ領域で活発な研究動向が確認されました："
        ]
        for cluster, papers in cluster_pairs[: self._max_top_clusters]:
            if papers:
                bullets.append(
                    _build_cluster_insight_bullet(cluster.label, len(papers), papers)
                )
        return "\n".join(bullets)

    def generate_mindmap(
        self,
        cluster_pairs: List[Tuple[TopicCluster, List[Dict[str, Any]]]],
        date_str: str,
    ) -> str:
        """Generate Mermaid mindmap syntax string from clusters."""
        if not cluster_pairs:
            return ""
        return _build_mermaid_mindmap_tree(cluster_pairs, date_str)

    def extract_emerging_topics(
        self, clusters: Sequence[TopicCluster], top_k: int = 5
    ) -> List[Tuple[str, float]]:
        """Extract top emerging topics scored by cluster size and keywords."""
        scored: List[Tuple[str, float]] = []
        for c in clusters:
            scored.append((c.label, c.score))
        scored.sort(key=lambda x: x[1], reverse=True)
        return scored[:top_k]

    def synthesize(
        self,
        clusters: Sequence[TopicCluster],
        papers: Sequence[Dict[str, Any]],
        date_str: str,
    ) -> Dict[str, Any]:
        """Produce full trend synthesis dictionary compatible with pipeline."""
        if not papers:
            return {
                "macro_insights": "本日の対象論文はありません。",
                "mermaid_mindmap": "",
                "clusters": {},
            }

        indexed = _index_papers_by_id(papers)
        cluster_pairs: List[Tuple[TopicCluster, List[Dict[str, Any]]]] = []
        clusters_dict: Dict[str, List[Dict[str, Any]]] = {}

        for c in clusters:
            p_list = _resolve_papers_for_cluster(c, indexed)
            if p_list:
                cluster_pairs.append((c, p_list))
                clusters_dict[c.label] = p_list

        cluster_pairs.sort(key=lambda cp: len(cp[1]), reverse=True)

        return {
            "macro_insights": self.synthesize_macro_insights(
                cluster_pairs, len(papers)
            ),
            "mermaid_mindmap": self.generate_mindmap(cluster_pairs, date_str),
            "clusters": clusters_dict,
        }
