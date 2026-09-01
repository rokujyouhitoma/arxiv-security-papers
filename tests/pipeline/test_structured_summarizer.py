"""Unit tests for Structured Multi-Stage Summarizer."""

from pipeline.transformer.structured_summarizer import (
    StructuredSummarizer,
    generate_structured_summary,
)


def test_structured_summarizer_three_points() -> None:
    title = "JENGA: Exploiting Counter-Based RowHammer Countermeasures"
    abstract = (
        "Modern DRAM devices are vulnerable to RowHammer disturbance errors. "
        "We propose JENGA, a novel timing attack framework that circumvents hardware counters. "
        "Our experimental results show a 99.4% bypass success rate on enterprise servers."
    )
    clean_id = "2609.01077"

    summarizer = StructuredSummarizer()
    res = summarizer.summarize(title=title, abstract=abstract, clean_id=clean_id)

    assert "threat" in res
    assert "proposal" in res
    assert "impact" in res
    assert "executive_summary" in res

    # Verify no legacy boilerplate
    assert "課題分析と防御モデルの検証" not in res["executive_summary"]
    assert "【提案】" in res["executive_summary"]


def test_structured_summarizer_empty_and_fallback() -> None:
    res = generate_structured_summary(
        title="Unknown Paper",
        abstract="",
        clean_id="0000.0000",
    )
    assert res["title_ja"] != ""
    assert res["executive_summary"] != ""
