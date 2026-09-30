"""Thematic Synthesizer and Macro Trend Engine Facade.

Delegates multi-paper dynamic topic clustering and macro trend synthesis
to the pure-Python nlp.clustering package while maintaining 100% backward
compatibility with existing callers.
Zero external dependencies, Xenon CC <= 3, and Mypy strict compliant.
"""

from typing import Any, Dict, List, Tuple

from nlp.clustering import DynamicTopicClusterer, TrendAnalyzer

# Backward compatible canonical domain keyword mapping
DOMAIN_KEYWORD_MAP: List[Tuple[str, List[str]]] = [
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


class ThematicSynthesizer:
    """Synthesizes macro security trends and Mermaid diagrams across multiple papers."""

    def __init__(
        self,
        clusterer: DynamicTopicClusterer | None = None,
        analyzer: TrendAnalyzer | None = None,
    ) -> None:
        """Initialize with optional clusterer and analyzer instances."""
        self._clusterer = (
            clusterer if clusterer is not None else DynamicTopicClusterer()
        )
        self._analyzer = analyzer if analyzer is not None else TrendAnalyzer()

    def synthesize(self, papers: List[Dict[str, Any]], date_str: str) -> Dict[str, Any]:
        """Synthesize insights and Mermaid mindmap from a collection of papers."""
        if not papers:
            return {
                "macro_insights": "本日の対象論文はありません。",
                "mermaid_mindmap": "",
                "clusters": {},
            }

        clusters = self._clusterer.cluster(papers)
        return self._analyzer.synthesize(
            clusters=clusters, papers=papers, date_str=date_str
        )


def synthesize_thematic_trends(
    papers: List[Dict[str, Any]], date_str: str
) -> Dict[str, Any]:
    """Convenience helper to synthesize trends across papers."""
    return ThematicSynthesizer().synthesize(papers=papers, date_str=date_str)
