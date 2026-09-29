"""Service Provider Interface (SPI) Protocols for NLP subsystem.

Defines domain-agnostic, zero-dependency interfaces using typing.Protocol.
All interfaces are @runtime_checkable to enable safe dynamic introspection.
"""

from typing import Dict, List, Optional, Protocol, Sequence, Tuple, runtime_checkable

from nlp.core.tokens import Morpheme, Sentence, Token, TopicCluster


@runtime_checkable
class TokenizerSPI(Protocol):
    """Protocol for tokenizing text into atomic linguistic tokens."""

    def tokenize(self, text: str) -> List[Token]:
        """Tokenize source text into a list of Token instances."""
        ...


@runtime_checkable
class SentenceSegmenterSPI(Protocol):
    """Protocol for segmenting academic or technical text into sentences."""

    def split_sentences(self, text: str) -> List[Sentence]:
        """Segment source text into rich Sentence instances with exact spans."""
        ...

    def split_text(self, text: str) -> List[str]:
        """Segment source text into clean sentence string values."""
        ...


@runtime_checkable
class MorphologicalAnalyzerSPI(Protocol):
    """Protocol for morphological analysis and part-of-speech tagging."""

    def parse(self, text: str) -> List[Morpheme]:
        """Parse text into a sequence of morphemes."""
        ...


@runtime_checkable
class KeyphraseExtractionSPI(Protocol):
    """Protocol for extracting salient keyphrases and compound terms."""

    def extract_keyphrases(self, text: str, top_k: int = 5) -> List[Tuple[str, float]]:
        """Extract top-k keyphrases paired with relevance scores."""
        ...


@runtime_checkable
class DiscourseSummarizerSPI(Protocol):
    """Protocol for extracting structured 3-point academic summaries."""

    def summarize(self, text: str) -> Dict[str, str]:
        """Synthesize structured summary mapping aspects to summaries."""
        ...


@runtime_checkable
class TopicClustererSPI(Protocol):
    """Protocol for clustering documents and deriving dynamic macro topics."""

    def cluster(
        self,
        documents: Sequence[Dict[str, str]],
        num_clusters: Optional[int] = None,
    ) -> List[TopicCluster]:
        """Cluster documents and return identified topic clusters."""
        ...
