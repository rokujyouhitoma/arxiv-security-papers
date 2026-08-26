"""Pure Python PDF Text Extraction & Spatial Layout Engine (ISO 32000-1 / ISO 32000-2)."""

from .contracts import (
    ColumnBlock,
    ExtractionMetrics,
    GlyphBox,
    IndirectRef,
    PdfPage,
    PdfStream,
    TextLine,
    TokenType,
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
]
