#!/usr/bin/env python3
"""
Diagram Generator Module
Generates dynamic Mermaid mindmaps and category breakdown visualizations.
"""

from typing import Any, Dict, List


def generate_mermaid_mindmap(papers: List[Dict[str, Any]]) -> str:
    """Generates a Mermaid mindmap representing the domain breakdown of processed papers."""
    categories: Dict[str, int] = {}
    for p in papers:
        cat = p.get("primary_category", "cs.CR")
        categories[cat] = categories.get(cat, 0) + 1

    lines = ["```mermaid", "mindmap", "  root((arXiv Security Papers))"]
    for cat, count in categories.items():
        lines.append(f"    {cat}[{cat} ({count} papers)]")

    lines.append("```")
    return "\n".join(lines)


def _count_keywords_in_text(
    papers: List[Dict[str, Any]], keyword_seeds: List[str]
) -> Dict[str, int]:
    """Counts keyword occurrences across paper titles and summaries."""
    counts: Dict[str, int] = {}
    for p in papers:
        text = (p.get("title", "") + " " + p.get("summary", "")).lower()
        for kw in keyword_seeds:
            if kw.lower() in text:
                counts[kw] = counts.get(kw, 0) + 1
    return counts


def _build_trend_mindmap_lines(counts: Dict[str, int]) -> List[str]:
    """Builds mindmap lines for top keyword trends."""
    lines = ["```mermaid", "mindmap", "  root((急上昇セキュリティ動向))"]
    top_items = sorted(counts.items(), key=lambda x: x[1], reverse=True)[:6]
    for kw, count in top_items:
        if count > 0:
            clean_kw = kw.replace(" ", "_")
            lines.append(f"    {clean_kw}[{kw} ({count} 件)]")
    lines.append("```")
    return lines


def generate_surge_trend_mermaid(papers: List[Dict[str, Any]]) -> str:
    """Generates a dynamic Mermaid mindmap highlighting trending security topics and keywords."""
    keyword_seeds = [
        "LLM",
        "Zero Trust",
        "Quantum",
        "Side-Channel",
        "Fuzzing",
        "Supply Chain",
        "Privacy",
        "Authentication",
    ]
    counts = _count_keywords_in_text(papers, keyword_seeds)
    return "\n".join(_build_trend_mindmap_lines(counts))
