"""Unit tests for NLP keyphrase extraction subsystem."""

from nlp.core.protocols import KeyphraseExtractionSPI
from nlp.extraction import extract_keyphrases
from nlp.extraction.cvalue import CValueExtractor
from nlp.extraction.textrank import TextRankKeywordExtractor

SAMPLE_ABSTRACT = """
RowHammer is a critical hardware vulnerability in modern DRAM devices.
In this paper, we propose Target-Row Refresh Guard, a lightweight defense mechanism.
Experimental evaluations demonstrate that our approach prevents unauthorized memory disturbance
while achieving 99.8% execution efficiency and negligible performance overhead.
"""


def test_textrank_spi_compliance() -> None:
    """Verify TextRankKeywordExtractor satisfies KeyphraseExtractionSPI."""
    extractor = TextRankKeywordExtractor()
    assert isinstance(extractor, KeyphraseExtractionSPI)


def test_textrank_extraction() -> None:
    """Verify TextRank extracts salient keywords with monotonic decreasing scores."""
    extractor = TextRankKeywordExtractor()
    ranks = extractor.extract_keyphrases(SAMPLE_ABSTRACT, top_k=5)
    assert len(ranks) > 0
    assert len(ranks) <= 5

    # Ensure scores are strictly sorted in descending order
    scores = [score for _, score in ranks]
    assert scores == sorted(scores, reverse=True)


def test_textrank_empty_input() -> None:
    """Verify TextRank gracefully handles empty or whitespace input."""
    extractor = TextRankKeywordExtractor()
    assert extractor.extract_keyphrases("") == []
    assert extractor.extract_keyphrases("   ") == []


def test_cvalue_compounds() -> None:
    """Verify CValueExtractor extracts capitalized and hyphenated technical compounds."""
    extractor = CValueExtractor()
    compounds = extractor.extract_compounds(SAMPLE_ABSTRACT, top_k=5)
    assert any("Row" in c or "Guard" in c or "DRAM" in c for c in compounds)


def test_cvalue_empty_input() -> None:
    """Verify CValueExtractor returns empty list for blank text."""
    extractor = CValueExtractor()
    assert extractor.extract_compounds("") == []


def test_extract_keyphrases_unified() -> None:
    """Verify high-level extract_keyphrases combines compounds and TextRank."""
    results = extract_keyphrases(SAMPLE_ABSTRACT, top_k=4)
    assert len(results) <= 4
    assert len(results) > 0
    # No duplicate tokens
    assert len(results) == len(set(r.lower() for r in results))
