"""Unit tests for discourse rhetoric aspect analysis and modifiers."""

from nlp.summarization.discourse_parser import (
    AspectScore,
    DiscourseRhetoricParser,
    SentenceAspect,
)


def test_aspect_score_dominant_aspect() -> None:
    """Verify dominant_aspect computation."""
    threat_dominant = AspectScore("Threat sent", threat=5.0, proposal=2.0, impact=1.0)
    assert threat_dominant.dominant_aspect == SentenceAspect.THREAT

    prop_dominant = AspectScore("Prop sent", threat=1.0, proposal=4.0, impact=2.0)
    assert prop_dominant.dominant_aspect == SentenceAspect.PROPOSAL

    impact_dominant = AspectScore("Impact sent", threat=1.0, proposal=2.0, impact=4.0)
    assert impact_dominant.dominant_aspect == SentenceAspect.IMPACT


def test_negation_suppression() -> None:
    """Verify negated proposals are properly dampened and not chosen as proposal."""
    parser = DiscourseRhetoricParser()
    sentences = [
        "In this work, we do not propose a new encryption protocol.",
        "Instead, we develop an automated testing framework for smart contracts.",
        "Our experiments demonstrate high exploit detection coverage.",
    ]
    scores = parser.parse_sentences(sentences)

    # First sentence has negation
    assert scores[0].is_negated is True
    # Proposal score of negated sentence must be heavily suppressed
    assert scores[0].proposal < scores[1].proposal

    _, prop, _ = parser.select_aspect_sentences(sentences)
    # The second sentence should be selected as proposal, not the negated first
    assert prop == sentences[1]


def test_prior_work_differentiation() -> None:
    """Verify prior work descriptions are suppressed from proposal aspect."""
    parser = DiscourseRhetoricParser()
    sentences = [
        "Prior work proposed hardware mitigations against RowHammer attacks.",
        "We introduce a zero-cost compiler instrumentation tool.",
        "Results show 98% protection rate with minimal overhead.",
    ]
    scores = parser.parse_sentences(sentences)

    # First sentence is prior work
    assert scores[0].is_prior_work is True
    assert scores[0].proposal < scores[1].proposal

    _, prop, _ = parser.select_aspect_sentences(sentences)
    assert prop == sentences[1]


def test_modality_boosting() -> None:
    """Verify strong empirical evidence boosts impact score."""
    parser = DiscourseRhetoricParser()
    neutral_sent = "We evaluate our method on standard benchmarks."
    boosted_sent = (
        "Experimental evaluations demonstrate that our approach "
        "outperforms prior models with 99.8% accuracy."
    )

    scores = parser.parse_sentences([neutral_sent, boosted_sent])

    assert scores[1].modality_score > scores[0].modality_score
    assert scores[1].impact > scores[0].impact


def test_select_aspect_sentences_distinct() -> None:
    """Verify distinct sentences are assigned to threat, proposal, and impact."""
    parser = DiscourseRhetoricParser()
    sentences = [
        "Hardware security vulnerabilities pose severe threats to cloud isolation.",
        "We present IronGuard, a hardware-software co-design framework.",
        "Evaluations empirically prove our defense eliminates microarchitectural leakage.",
    ]
    threat, prop, impact = parser.select_aspect_sentences(sentences)

    assert threat == sentences[0]
    assert prop == sentences[1]
    assert impact == sentences[2]
    # Ensure all three are non-null and distinct
    assert len({threat, prop, impact}) == 3
