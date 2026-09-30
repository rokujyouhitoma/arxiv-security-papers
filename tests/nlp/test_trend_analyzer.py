"""Unit tests for TrendAnalyzer and Mermaid Mindmap generation."""

from nlp.clustering.trend_analyzer import TrendAnalyzer
from nlp.core.tokens import TopicCluster


def test_trend_analyzer_empty_papers() -> None:
    """Verify synthesis output when paper collection is empty."""
    analyzer = TrendAnalyzer()
    res = analyzer.synthesize(clusters=[], papers=[], date_str="2026-09-30")

    assert res["macro_insights"] == "本日の対象論文はありません。"
    assert res["mermaid_mindmap"] == ""
    assert res["clusters"] == {}


def test_trend_analyzer_synthesis_structure() -> None:
    """Verify macro insights and Mermaid mindmap structure for clustered papers."""
    papers = [
        {
            "clean_id": "p_01",
            "title": "LLM Jailbreak Attack Exploration",
            "title_ja": "LLMジェイルブレイク攻撃の探索",
            "abstract": "Prompt injection in LLM pipelines.",
        },
        {
            "clean_id": "p_02",
            "title": "Hardware DRAM RowHammer Faults",
            "title_ja": "ハードウェアDRAM RowHammerフォールト",
            "abstract": "Physical disturbance errors in DDR memory.",
        },
    ]

    clusters = [
        TopicCluster(
            cluster_id="cluster_1",
            label="AI/LLM セキュリティ & 敵対的攻撃",
            keywords=("llm", "jailbreak"),
            score=1.0,
            document_ids=("p_01",),
        ),
        TopicCluster(
            cluster_id="cluster_2",
            label="ハードウェア & 低レイヤ物理セキュリティ",
            keywords=("rowhammer", "dram"),
            score=1.0,
            document_ids=("p_02",),
        ),
    ]

    analyzer = TrendAnalyzer()
    res = analyzer.synthesize(clusters=clusters, papers=papers, date_str="2026-09-30")

    assert "macro_insights" in res
    assert "mermaid_mindmap" in res
    assert "clusters" in res

    # Verify Japanese prose
    insights = res["macro_insights"]
    assert "本日の収集論文（計 2 件）" in insights
    assert "AI/LLM セキュリティ & 敵対的攻撃" in insights
    assert "ハードウェア & 低レイヤ物理セキュリティ" in insights
    assert "注目論文として" in insights

    # Verify Mermaid mindmap
    mindmap = res["mermaid_mindmap"]
    assert mindmap.startswith("```mermaid\nmindmap")
    assert mindmap.endswith("```")
    assert "root((セキュリティ動向<br/>2026-09-30))" in mindmap
    assert "LLMジェイルブレイク" in mindmap or "LLM" in mindmap


def test_trend_analyzer_mermaid_sanitization() -> None:
    """Verify Mermaid mindmap sanitizes quotes, parentheses, brackets, and colons."""
    papers = [
        {
            "clean_id": "dirty_1",
            "title": 'Malicious [Title]: with (parentheses) & "quotes"; and <html tags>',
            "title_ja": '悪意ある[タイトル]: (括弧) と "引用符"; および <タグ>',
            "abstract": "Testing sanitization rules.",
        }
    ]
    clusters = [
        TopicCluster(
            cluster_id="cluster_1",
            label='テスト[特殊記号] & "引用"',
            keywords=("test",),
            score=1.0,
            document_ids=("dirty_1",),
        )
    ]

    analyzer = TrendAnalyzer()
    res = analyzer.synthesize(clusters=clusters, papers=papers, date_str="2026-09-30")
    mindmap = res["mermaid_mindmap"]

    # Verify syntax breaks are not present
    assert "<html" not in mindmap
    assert "<タグ>" not in mindmap
    assert '""' not in mindmap


def test_trend_analyzer_extract_emerging_topics() -> None:
    """Verify extraction of emerging topics sorted by relevance score."""
    clusters = [
        TopicCluster(
            cluster_id="c1",
            label="Low Score Topic",
            keywords=("k1",),
            score=1.0,
            document_ids=("d1",),
        ),
        TopicCluster(
            cluster_id="c2",
            label="High Surge Topic",
            keywords=("k2",),
            score=5.0,
            document_ids=("d2", "d3", "d4", "d5", "d6"),
        ),
    ]

    analyzer = TrendAnalyzer()
    emerging = analyzer.extract_emerging_topics(clusters, top_k=2)

    assert len(emerging) == 2
    assert emerging[0][0] == "High Surge Topic"
    assert emerging[0][1] == 5.0
    assert emerging[1][0] == "Low Score Topic"
