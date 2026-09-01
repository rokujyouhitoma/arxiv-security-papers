"""Thematic Synthesizer and Macro Trend Engine.

Performs multi-paper clustering, extracts surge topics, and generates
executive-level synthesis summaries along with Mermaid mindmaps.
"""

from collections import defaultdict
from typing import Any, Dict, List

DOMAIN_KEYWORD_MAP: List[tuple[str, List[str]]] = [
    (
        "AI/LLM セキュリティ & 敵対的攻撃",
        [
            "llm",
            "prompt injection",
            "jailbreak",
            "agent",
            "adversarial",
            "rag",
        ],
    ),
    (
        "ハードウェア & 低レイヤ物理セキュリティ",
        ["rowhammer", "fault injection", "dram", "hardware", "side-channel"],
    ),
    (
        "量子暗号 & ゼロ知識証明技術",
        [
            "quantum",
            "qkd",
            "post-quantum",
            "lattice",
            "zero-knowledge",
            "cryptography",
        ],
    ),
    (
        "ソフトウェア脆弱性 & Web3/DeFi",
        [
            "smart contract",
            "defi",
            "blockchain",
            "vulnerability",
            "fuzzing",
            "malware",
        ],
    ),
    (
        "ネットワークセキュリティ & 通信耐障害性",
        [
            "network",
            "ipsec",
            "ddos",
            "traffic",
            "quic",
            "routing",
            "firewall",
        ],
    ),
    (
        "プライバシー保護 & 匿名化技術",
        ["privacy", "anonymity", "differential privacy"],
    ),
]


def _match_domain_keywords(text: str, keywords: List[str]) -> bool:
    """Checks if any keyword is present in text."""
    return any(k in text for k in keywords)


def _get_combined_paper_text(paper: Dict[str, Any]) -> str:
    """Combines paper metadata fields into lowercase search text."""
    title = (paper.get("title") or "").lower()
    abstract = (paper.get("abstract") or "").lower()
    tags = [t.lower() for t in paper.get("tags") or []]
    return f"{title} {abstract} {' '.join(tags)}"


def _categorize_paper(paper: Dict[str, Any]) -> str:
    """Categorizes a paper into high-level thematic security clusters."""
    text = _get_combined_paper_text(paper)

    for domain_name, keywords in DOMAIN_KEYWORD_MAP:
        if _match_domain_keywords(text, keywords):
            return domain_name

    return "システムセキュリティ & 基盤防御"


def _format_paper_title_item(p: Dict[str, Any]) -> str:
    """Formats individual paper title for insight summary."""
    title = p.get("title_ja") or p.get("title") or ""
    return f"「{title[:30]}...」" if len(title) > 30 else f"「{title}」"


def _build_cluster_insights(
    cluster_name: str, count: int, top_papers: List[Dict[str, Any]]
) -> str:
    """Generates a contextual insight bullet for a specific security cluster."""
    short_titles = [_format_paper_title_item(p) for p in top_papers[:2]]
    title_summary = "、".join(short_titles)
    return (
        f"- **{cluster_name}** ({count} 件): "
        f"注目論文として {title_summary} 等が発表され、実務防御および攻撃検証の進展が見られます。"
    )


def _build_mermaid_mindmap(
    sorted_clusters: List[tuple[str, List[Dict[str, Any]]]],
    date_str: str,
) -> str:
    """Renders Mermaid mindmap for security clusters."""
    mermaid_lines = [
        "```mermaid",
        "mindmap",
        f"  root((セキュリティ動向<br/>{date_str}))",
    ]
    for c_name, p_list in sorted_clusters[:5]:
        safe_c_name = c_name.replace('"', "")
        mermaid_lines.append(f'    {safe_c_name}["{safe_c_name} ({len(p_list)}件)"]')
        for p in p_list[:2]:
            title = p.get("title_ja") or p.get("title") or ""
            clean_title = title.replace('"', "").replace("(", "").replace(")", "")[:25]
            mermaid_lines.append(f'      ["{clean_title}..."]')
    mermaid_lines.append("```")
    return "\n".join(mermaid_lines)


class ThematicSynthesizer:
    """Synthesizes macro security trends and Mermaid diagrams across multiple papers."""

    def synthesize(self, papers: List[Dict[str, Any]], date_str: str) -> Dict[str, Any]:
        """Synthesizes insights and Mermaid mindmap from a collection of papers."""
        if not papers:
            return {
                "macro_insights": "本日の対象論文はありません。",
                "mermaid_mindmap": "",
                "clusters": {},
            }

        clusters: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        for p in papers:
            c = _categorize_paper(p)
            clusters[c].append(p)

        sorted_clusters = sorted(
            clusters.items(), key=lambda x: len(x[1]), reverse=True
        )

        bullets = [
            f"本日の収集論文（計 {len(papers)} 件）において、以下の重点セキュリティ領域で活発な研究動向が確認されました："
        ]
        for c_name, p_list in sorted_clusters[:4]:
            bullets.append(_build_cluster_insights(c_name, len(p_list), p_list))

        return {
            "macro_insights": "\n".join(bullets),
            "mermaid_mindmap": _build_mermaid_mindmap(sorted_clusters, date_str),
            "clusters": dict(clusters),
        }


def synthesize_thematic_trends(
    papers: List[Dict[str, Any]], date_str: str
) -> Dict[str, Any]:
    """Convenience helper to synthesize trends across papers."""
    return ThematicSynthesizer().synthesize(papers=papers, date_str=date_str)
