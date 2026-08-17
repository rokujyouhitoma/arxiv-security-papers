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
