"""Structured Multi-Stage Summarizer Module.

Parses academic paper abstracts using discourse rhetorical markers to
extract and synthesize 3-point structured summaries:
1. Threat & Vulnerability (背景・課題)
2. Proposed Method (提案手法・アプローチ)
3. Impact & Empirical Results (実証結果・セキュリティ影響)

Delegates to `src/nlp/summarization/` while preserving full backward compatibility.
"""

from typing import Dict, List, Optional, Tuple

from nlp.segmentation.academic_segmenter import AcademicSentenceSegmenter
from nlp.summarization.discourse_parser import (
    IMPACT_MARKERS,
    PROPOSAL_MARKERS,
    THREAT_MARKERS,
    DiscourseRhetoricParser,
)
from nlp.summarization.structured_synthesizer import (
    KEYWORD_TRANSLATIONS,
    StructuredSynthesizer,
)

__all__ = [
    "THREAT_MARKERS",
    "PROPOSAL_MARKERS",
    "IMPACT_MARKERS",
    "KEYWORD_TRANSLATIONS",
    "StructuredSummarizer",
    "generate_structured_summary",
]

_SEGMENTER = AcademicSentenceSegmenter(min_sentence_length=10)
_PARSER = DiscourseRhetoricParser()
_SYNTHESIZER = StructuredSynthesizer(segmenter=_SEGMENTER, parser=_PARSER)


def _split_into_sentences(text: str) -> List[str]:
    """Split text into sentences using AcademicSentenceSegmenter."""
    return _SEGMENTER.split_text(text)


def _classify_sentences(
    sentences: List[str],
) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """Classify sentences into Threat, Proposal, and Impact."""
    return _PARSER.select_aspect_sentences(sentences)


class StructuredSummarizer:
    """Generates 3-point structured executive summaries for security papers."""

    def __init__(
        self,
        synthesizer: Optional[StructuredSynthesizer] = None,
    ) -> None:
        """Initialize StructuredSummarizer."""
        self._synthesizer = synthesizer or _SYNTHESIZER

    def summarize(
        self,
        title: str,
        abstract: str,
        clean_id: str,
        japanese_title: Optional[str] = None,
    ) -> Dict[str, str]:
        """Synthesize structured 3-point elements and single-line executive summary."""
        return self._synthesizer.summarize_paper(
            title=title,
            abstract=abstract,
            clean_id=clean_id,
            japanese_title=japanese_title,
        )


def generate_structured_summary(
    title: str,
    abstract: str,
    clean_id: str,
    japanese_title: Optional[str] = None,
) -> Dict[str, str]:
    """Convenience helper to generate structured 3-point executive summary."""
    summarizer = StructuredSummarizer()
    return summarizer.summarize(
        title=title,
        abstract=abstract,
        clean_id=clean_id,
        japanese_title=japanese_title,
    )
