"""Pure Python PDF Text Extraction & Spatial Layout Engine (ISO 32000-1 / ISO 32000-2)."""

from .contracts import (
    EVENT_CHECK_SAFETY,
    EVENT_DECODING_DONE,
    EVENT_DECOMPRESS,
    EVENT_FAIL,
    EVENT_FILTER_START,
    EVENT_HEADER_PARSED,
    EVENT_SAFETY_VIOLATION,
    EVENT_START_PARSING,
    EVENT_SYNTHESIS_DONE,
    ColumnBlock,
    ExtractionMetrics,
    GlyphBox,
    IndirectRef,
    PdfPage,
    PdfSafetyLimitExceededError,
    PdfStream,
    SafetyLimitConfig,
    TextLine,
    TokenType,
    build_pdf_stream_hsm,
)
from .extractor import PurePdfTextExtractor


def extract_text(source: object) -> str:
    """Convenience functional interface for Pure Python PDF text extraction."""
    return PurePdfTextExtractor.extract_text(source)  # type: ignore[arg-type]


__all__ = [
    "PurePdfTextExtractor",
    "extract_text",
    "GlyphBox",
    "TextLine",
    "ColumnBlock",
    "PdfPage",
    "PdfStream",
    "IndirectRef",
    "TokenType",
    "ExtractionMetrics",
    "SafetyLimitConfig",
    "PdfSafetyLimitExceededError",
    "build_pdf_stream_hsm",
    "EVENT_START_PARSING",
    "EVENT_HEADER_PARSED",
    "EVENT_FILTER_START",
    "EVENT_DECOMPRESS",
    "EVENT_CHECK_SAFETY",
    "EVENT_DECODING_DONE",
    "EVENT_SYNTHESIS_DONE",
    "EVENT_SAFETY_VIOLATION",
    "EVENT_FAIL",
]
