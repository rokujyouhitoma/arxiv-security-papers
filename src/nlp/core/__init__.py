"""Core data structures and SPI protocols for NLP subsystem."""

from nlp.core.protocols import (
    DiscourseSummarizerSPI,
    KeyphraseExtractionSPI,
    MorphologicalAnalyzerSPI,
    SentenceSegmenterSPI,
    TokenizerSPI,
    TopicClustererSPI,
)
from nlp.core.tokens import Morpheme, Sentence, Span, Token, TopicCluster

__all__ = [
    "Span",
    "Token",
    "Sentence",
    "Morpheme",
    "TopicCluster",
    "TokenizerSPI",
    "SentenceSegmenterSPI",
    "MorphologicalAnalyzerSPI",
    "KeyphraseExtractionSPI",
    "DiscourseSummarizerSPI",
    "TopicClustererSPI",
]
