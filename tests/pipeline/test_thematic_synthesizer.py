"""Unit tests for Thematic Synthesizer and Macro Trend Engine."""

from pipeline.transformer.thematic_synthesizer import (
    ThematicSynthesizer,
    synthesize_thematic_trends,
)


def test_thematic_synthesizer_multi_papers() -> None:
    papers = [
        {
            "title": "Prompt Injection Attacks in LLM Agents",
            "title_ja": "LLMエージェントにおけるプロンプトインジェクション攻撃",
            "abstract": "We explore jailbreak vulnerabilities in agent workflows.",
            "tags": ["cs.CR", "AI/ML Security"],
        },
        {
            "title": "RowHammer Fault Injection on DDR5",
            "title_ja": "DDR5メモリに対するRowHammerフォールト注入",
            "abstract": "Hardware attacks on modern DRAM architectures.",
            "tags": ["cs.CR", "Hardware Security"],
        },
        {
            "title": "Post-Quantum QKD IPsec Tunnels",
            "title_ja": "耐量子QKD統合IPsecトンネル",
            "abstract": "Quantum key distribution protocols.",
            "tags": ["cs.CR", "Cryptography"],
        },
    ]

    synth = ThematicSynthesizer()
    res = synth.synthesize(papers=papers, date_str="2026-09-01")

    assert "macro_insights" in res
    assert "mermaid_mindmap" in res
    assert "clusters" in res
    assert "```mermaid" in res["mermaid_mindmap"]
    assert "mindmap" in res["mermaid_mindmap"]
    assert len(res["clusters"]) > 0


def test_thematic_synthesizer_empty() -> None:
    res = synthesize_thematic_trends(papers=[], date_str="2026-09-01")
    assert "本日の対象論文はありません" in res["macro_insights"]
    assert res["mermaid_mindmap"] == ""
