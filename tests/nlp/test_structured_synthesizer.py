"""Unit tests for structured 3-point academic summarizer."""

from nlp.core.protocols import DiscourseSummarizerSPI
from nlp.summarization.structured_synthesizer import (
    StructuredSynthesizer,
    _format_executive_one_liner,
)

SAMPLE_TITLE = "JENGA: Breaking Predictability with RowHammer Attacks"
SAMPLE_ABSTRACT = """
RowHammer is a catastrophic vulnerability in modern DRAM architectures.
Prior work failed to exploit this in hard real-time systems.
We propose JENGA, a novel timing attack leveraging RowHammer refresh delays.
Extensive experiments demonstrate that JENGA causes severe deadline misses in autonomous vehicles.
"""


def test_structured_synthesizer_spi_compliance() -> None:
    """Verify StructuredSynthesizer satisfies DiscourseSummarizerSPI."""
    synthesizer = StructuredSynthesizer()
    assert isinstance(synthesizer, DiscourseSummarizerSPI)


def test_summarize_spi_call() -> None:
    """Verify generic summarize SPI method returns non-empty structured dict."""
    synthesizer = StructuredSynthesizer()
    result = synthesizer.summarize(SAMPLE_ABSTRACT)

    assert "threat" in result
    assert "proposal" in result
    assert "impact" in result
    assert "executive_summary" in result


def test_summarize_paper() -> None:
    """Verify summarize_paper synthesizes 3-point elements and Japanese title."""
    synthesizer = StructuredSynthesizer()
    result = synthesizer.summarize_paper(
        title=SAMPLE_TITLE,
        abstract=SAMPLE_ABSTRACT,
        clean_id="2609.01077",
    )

    assert "title_ja" in result
    assert len(result["title_ja"]) > 0

    assert "threat" in result
    assert "proposal" in result
    assert "impact" in result
    assert "executive_summary" in result

    # Check executive summary formatting
    assert result["executive_summary"].startswith("【提案】")
    assert "実証評価により" in result["executive_summary"]


def test_thesaurus_and_keyword_translation() -> None:
    """Verify security keywords and thesaurus terms are translated."""
    synthesizer = StructuredSynthesizer()
    abstract_with_terms = """
    We explore zero-trust architecture and smart contract vulnerabilities.
    We propose a verified runtime monitor.
    Results show differential privacy preservation.
    """
    res = synthesizer.summarize_paper(
        title="Zero-Trust Smart Contract Security",
        abstract=abstract_with_terms,
        clean_id="2609.99999",
    )
    # Check that zero-trust and smart contract get translated or recognized
    all_text = res["threat"] + res["proposal"] + res["impact"]
    assert any(
        term in all_text
        for term in ["ゼロトラスト", "スマートコントラクト", "提案", "脆弱性"]
    )


def test_executive_one_liner_truncation() -> None:
    """Verify executive summary length does not exceed limit."""
    long_prop = "A" * 150
    long_impact = "B" * 150
    summary = _format_executive_one_liner(long_prop, long_impact)
    assert len(summary) <= 130
    assert summary.endswith("...")
