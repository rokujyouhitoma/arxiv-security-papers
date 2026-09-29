"""Immutable data structures for NLP core processing.

Provides type-safe, lightweight, memory-efficient data objects
used across tokenization, sentence segmentation, morphology, and clustering.
Zero external dependencies.
"""

from dataclasses import dataclass
from typing import Optional, Tuple


@dataclass(frozen=True, slots=True)
class Span:
    """Represents a character span [start, end) within source text."""

    start: int
    end: int

    def __post_init__(self) -> None:
        """Validate span bounds."""
        if self.start < 0:
            raise ValueError(f"Span start must be non-negative: {self.start}")
        if self.end < self.start:
            raise ValueError(
                f"Span end ({self.end}) cannot precede start ({self.start})"
            )

    @property
    def length(self) -> int:
        """Return span length in characters."""
        return self.end - self.start


@dataclass(frozen=True, slots=True)
class Token:
    """Represents an atomic token with span and linguistic annotations."""

    text: str
    span: Span
    tag: Optional[str] = None
    lemma: Optional[str] = None


@dataclass(frozen=True, slots=True)
class Sentence:
    """Represents a single parsed sentence with boundary span and optional tokens."""

    text: str
    span: Span
    tokens: Tuple[Token, ...] = ()


@dataclass(frozen=True, slots=True)
class Morpheme:
    """Represents a Japanese/English morphological element."""

    surface: str
    pos: str
    subpos: str = "*"
    base_form: str = "*"
    cost: int = 0


@dataclass(frozen=True, slots=True)
class TopicCluster:
    """Represents a thematic cluster extracted across multiple documents."""

    cluster_id: str
    label: str
    keywords: Tuple[str, ...]
    score: float
    document_ids: Tuple[str, ...] = ()
