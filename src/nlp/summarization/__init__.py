"""Discourse Rhetoric and Structured Summarization Subsystem.

Provides discourse aspect analysis, negation/prior-work detection,
and 3-point structured Japanese summary synthesis.
Zero external dependencies.
"""

from nlp.summarization.discourse_parser import (
    AspectScore,
    DiscourseRhetoricParser,
    SentenceAspect,
)
from nlp.summarization.structured_synthesizer import StructuredSynthesizer

__all__ = [
    "SentenceAspect",
    "AspectScore",
    "DiscourseRhetoricParser",
    "StructuredSynthesizer",
]
