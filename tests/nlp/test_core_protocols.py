"""Unit tests for NLP core tokens and SPI protocols."""

import pytest

from nlp.core.protocols import (
    DiscourseSummarizerSPI,
    KeyphraseExtractionSPI,
    MorphologicalAnalyzerSPI,
    SentenceSegmenterSPI,
    TokenizerSPI,
    TopicClustererSPI,
)
from nlp.core.tokens import Morpheme, Sentence, Span, Token, TopicCluster
from nlp.segmentation.academic_segmenter import AcademicSentenceSegmenter


class DummyTokenizer:
    def tokenize(self, text: str):
        return []


class DummyMorphology:
    def parse(self, text: str):
        return []


class DummyKeyphrase:
    def extract_keyphrases(self, text: str, top_k: int = 5):
        return []


class DummySummarizer:
    def summarize(self, text: str):
        return {}


class DummyClusterer:
    def cluster(self, documents, num_clusters=None):
        return []


def test_span_validation_and_length():
    """Test valid and invalid span creation."""
    span = Span(0, 10)
    assert span.start == 0
    assert span.end == 10
    assert span.length == 10

    with pytest.raises(ValueError, match="Span start must be non-negative"):
        Span(-1, 5)

    with pytest.raises(ValueError, match="cannot precede start"):
        Span(10, 5)


def test_token_immutability():
    """Test token properties and frozen dataclass enforcement."""
    token = Token(text="security", span=Span(0, 8), tag="NN", lemma="security")
    assert token.text == "security"
    assert token.span.length == 8
    assert token.tag == "NN"

    with pytest.raises(AttributeError):
        token.text = "hacked"  # type: ignore


def test_sentence_immutability():
    """Test sentence structure and frozen semantics."""
    token = Token(text="Test", span=Span(0, 4))
    sentence = Sentence(text="Test.", span=Span(0, 5), tokens=(token,))
    assert sentence.text == "Test."
    assert sentence.tokens[0].text == "Test"

    with pytest.raises(AttributeError):
        sentence.text = "Other"  # type: ignore


def test_morpheme_structure():
    """Test morpheme defaults and values."""
    morpheme = Morpheme(
        surface="脆弱性", pos="名詞", subpos="一般", base_form="脆弱性", cost=120
    )
    assert morpheme.surface == "脆弱性"
    assert morpheme.pos == "名詞"
    assert morpheme.cost == 120


def test_topic_cluster_structure():
    """Test topic cluster construction."""
    cluster = TopicCluster(
        cluster_id="cluster-01",
        label="Post-Quantum Cryptography",
        keywords=("kyber", "dilithium", "lattice"),
        score=0.95,
        document_ids=("paper-01", "paper-02"),
    )
    assert cluster.cluster_id == "cluster-01"
    assert cluster.score == 0.95
    assert len(cluster.keywords) == 3


def test_spi_protocols_runtime_checkable():
    """Verify runtime_checkable behavior for all SPI interfaces."""
    segmenter = AcademicSentenceSegmenter()
    assert isinstance(segmenter, SentenceSegmenterSPI)

    assert isinstance(DummyTokenizer(), TokenizerSPI)
    assert isinstance(DummyMorphology(), MorphologicalAnalyzerSPI)
    assert isinstance(DummyKeyphrase(), KeyphraseExtractionSPI)
    assert isinstance(DummySummarizer(), DiscourseSummarizerSPI)
    assert isinstance(DummyClusterer(), TopicClustererSPI)

    class IncompleteObject:
        pass

    assert not isinstance(IncompleteObject(), SentenceSegmenterSPI)
    assert not isinstance(IncompleteObject(), TokenizerSPI)
