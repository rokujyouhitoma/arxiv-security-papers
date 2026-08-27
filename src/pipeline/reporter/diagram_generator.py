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
    counts: Dict[str, int] = {}
    for p in papers:
        text = (p.get("title", "") + " " + p.get("summary", "")).lower()
        for kw in keyword_seeds:
            if kw.lower() in text:
                counts[kw] = counts.get(kw, 0) + 1

    lines = ["```mermaid", "mindmap", "  root((急上昇セキュリティ動向))"]
    for kw, count in sorted(counts.items(), key=lambda x: x[1], reverse=True)[:6]:
        if count > 0:
            clean_kw = kw.replace(" ", "_")
            lines.append(f"    {clean_kw}[{kw} ({count} 件)]")
    lines.append("```")
    return "\n".join(lines)
