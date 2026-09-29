"""Unit tests for AcademicSentenceSegmenter."""

import time

import pytest

from nlp.segmentation.academic_segmenter import AcademicSentenceSegmenter
from pipeline.transformer.structured_summarizer import (
    _split_into_sentences,
    generate_structured_summary,
)


@pytest.fixture
def segmenter() -> AcademicSentenceSegmenter:
    return AcademicSentenceSegmenter()


def test_basic_sentence_splitting(segmenter: AcademicSentenceSegmenter):
    """Test standard multi-sentence splitting."""
    text = (
        "Side-channel attacks pose severe threats to modern processors. "
        "We propose a novel hardware-assisted defense mechanism. "
        "Experimental evaluations show negligible performance overhead."
    )
    sentences = segmenter.split_sentences(text)
    assert len(sentences) == 3
    assert (
        sentences[0].text
        == "Side-channel attacks pose severe threats to modern processors."
    )
    assert (
        sentences[1].text == "We propose a novel hardware-assisted defense mechanism."
    )
    assert (
        sentences[2].text
        == "Experimental evaluations show negligible performance overhead."
    )


def test_academic_abbreviations_protection(segmenter: AcademicSentenceSegmenter):
    """Verify that abbreviations like et al. and e.g. do not cause false boundary splits."""
    text = (
        "Smith et al. investigated zero-day exploits in autonomous systems. "
        "Modern mitigations (e.g. control-flow integrity) fail against speculative execution. "
        "Furthermore, vs. conventional approaches, our technique achieves 99.8% precision."
    )
    sentences = segmenter.split_sentences(text)
    assert len(sentences) == 3
    assert "Smith et al." in sentences[0].text
    assert "e.g." in sentences[1].text
    assert "vs." in sentences[2].text


def test_reference_and_citation_protection(segmenter: AcademicSentenceSegmenter):
    """Verify figure, table, section, and reference indicators are preserved."""
    text = (
        "As illustrated in Fig. 1, the pipeline monitors kernel events. "
        "In Table. 2, latency numbers are compared across microarchitectures. "
        "According to Ref. [3], memory safety bugs remain dominant."
    )
    sentences = segmenter.split_sentences(text)
    assert len(sentences) == 3
    assert "Fig. 1" in sentences[0].text
    assert "Table. 2" in sentences[1].text
    assert "Ref. [3]" in sentences[2].text


def test_decimals_and_versions(segmenter: AcademicSentenceSegmenter):
    """Verify floating point decimals and version numbers are preserved."""
    text = (
        "The model achieves a p-value of 0.001 under adversarial conditions. "
        "We evaluated Linux kernel v5.15 on ARM64 platforms."
    )
    sentences = segmenter.split_sentences(text)
    assert len(sentences) == 2
    assert "0.001" in sentences[0].text
    assert "v5.15" in sentences[1].text


def test_quoted_text_dots_protection(segmenter: AcademicSentenceSegmenter):
    """Verify that periods inside quotation marks do not split the sentence."""
    text = (
        'The attacker injects "rm -rf /." into the vulnerable parser. '
        "This allows unauthorized escalation of privileges."
    )
    sentences = segmenter.split_sentences(text)
    assert len(sentences) == 2
    assert (
        'The attacker injects "rm -rf /." into the vulnerable parser.'
        == sentences[0].text
    )


def test_spans_accuracy(segmenter: AcademicSentenceSegmenter):
    """Verify that Span start and end accurately slice the cleaned string."""
    text = "First sentence here. Second sentence starts here."
    cleaned = "First sentence here. Second sentence starts here."
    sentences = segmenter.split_sentences(text)
    assert len(sentences) == 2

    s1 = sentences[0]
    s2 = sentences[1]
    assert cleaned[s1.span.start : s1.span.end] == s1.text
    assert cleaned[s2.span.start : s2.span.end] == s2.text
    assert s1.span.end <= s2.span.start


def test_empty_and_whitespace_inputs(segmenter: AcademicSentenceSegmenter):
    """Verify edge cases with empty or whitespace-only inputs."""
    assert segmenter.split_sentences("") == []
    assert segmenter.split_sentences("   \n\t  ") == []
    assert segmenter.split_text("") == []


def test_input_length_limit():
    """Verify ValueError when input exceeds max_text_length."""
    short_segmenter = AcademicSentenceSegmenter(max_text_length=100)
    with pytest.raises(ValueError, match="Input text exceeds maximum"):
        short_segmenter.split_sentences("A" * 101)


def test_redos_resilience(segmenter: AcademicSentenceSegmenter):
    """Verify linear-time resilience against Catastrophic Backtracking inputs."""
    pathological = '("e.g. "' * 500 + "." + " Normal sentence."
    start = time.perf_counter()
    sentences = segmenter.split_sentences(pathological)
    elapsed = time.perf_counter() - start

    assert elapsed < 0.5, f"Execution took too long ({elapsed:.3f}s), possible ReDoS!"
    assert len(sentences) >= 1


def test_structured_summarizer_integration():
    """Verify backward compatibility and integration with structured_summarizer."""
    abstract = (
        "Spectre vulnerabilities allow unauthorized cache side-channel leakage in CPUs. "
        "Smith et al. proposed hardware partitioning, but it incurs massive overhead. "
        "We propose SpecShield, an adaptive branch prediction barrier. "
        "Experimental results demonstrate a 99.4% reduction in exploit success with 1.2% overhead."
    )
    sentences = _split_into_sentences(abstract)
    assert len(sentences) >= 3

    summary = generate_structured_summary("SpecShield Defense", abstract, "2401.12345")
    assert "threat" in summary
    assert "proposal" in summary
    assert "impact" in summary
    assert "executive_summary" in summary
    assert len(summary["threat"]) > 0
    assert len(summary["proposal"]) > 0
    assert len(summary["impact"]) > 0
