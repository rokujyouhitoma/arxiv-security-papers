"""Unit tests for NLP Keyword and Technical Term Extractor."""

from pipeline.transformer.keyword_extractor import (
    CValueExtractor,
    TextRankKeywordExtractor,
    extract_keyphrases,
)


def test_textrank_keyword_extractor_basic() -> None:
    text = (
        "We propose a novel framework for Physical Fault Injection in hardware. "
        "Our approach evaluates side-channel vulnerability and fault injection attacks "
        "on microcontrollers with high accuracy."
    )
    extractor = TextRankKeywordExtractor(window_size=3)
    results = extractor.extract(text, top_k=5)

    assert len(results) > 0
    words = [w[0] for w in results]
    assert any("fault" in w or "injection" in w or "hardware" in w for w in words)


def test_textrank_keyword_extractor_empty() -> None:
    extractor = TextRankKeywordExtractor()
    assert extractor.extract("") == []
    assert extractor.extract("   ") == []


def test_cvalue_extractor_compounds() -> None:
    text = (
        "We demonstrate Context Privilege Escalation in multi-agent LLM systems. "
        "Context Privilege Escalation allows unauthorized access to backend tools. "
        "Furthermore, Physical Fault Injection attacks are analyzed."
    )
    extractor = CValueExtractor()
    compounds = extractor.extract_compounds(text, top_k=3)

    assert len(compounds) > 0
    assert any(
        "Context Privilege Escalation" in c or "Physical Fault Injection" in c
        for c in compounds
    )


def test_cvalue_extractor_empty() -> None:
    extractor = CValueExtractor()
    assert extractor.extract_compounds("") == []


def test_extract_keyphrases_high_level_api() -> None:
    text = (
        "JENGA: Exploiting Counter-Based RowHammer Countermeasures to Break Real-Time Predictability. "
        "In this work, we analyze DRAM disturbance errors and timing attacks."
    )
    keyphrases = extract_keyphrases(text, top_k=4)

    assert len(keyphrases) <= 4
    assert len(keyphrases) > 0
    # Should not crash on empty text
    assert extract_keyphrases("") == []
