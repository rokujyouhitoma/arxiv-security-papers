"""Contracts, data classes, and type definitions for Pure Python PDF Engine."""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Tuple


class TokenType(Enum):
    """PDF lexical token types conforming to ISO 32000-1 Clause 7.2."""

    KEYWORD = "KEYWORD"
    NAME = "NAME"
    NUMBER = "NUMBER"
    STRING_LITERAL = "STRING_LITERAL"
    STRING_HEX = "STRING_HEX"
    DICT_START = "DICT_START"
    DICT_END = "DICT_END"
    ARRAY_START = "ARRAY_START"
    ARRAY_END = "ARRAY_END"


@dataclass(frozen=True)
class IndirectRef:
    """PDF indirect object reference (ISO 32000-1 Clause 7.3.10)."""

    obj_num: int
    gen_num: int = 0

    def __repr__(self) -> str:
        return f"{self.obj_num} {self.gen_num} R"


@dataclass
class PdfStream:
    """PDF stream object containing dictionary metadata and raw byte payload."""

    dictionary: Dict[str, Any]
    data: bytes


@dataclass
class GlyphBox:
    """Represents a positioned glyph/character in 2D page user space."""

    text: str
    x: float
    y: float
    width: float
    height: float
    font_size: float
    font_name: str = ""


@dataclass
class TextLine:
    """A horizontal cluster of glyph boxes forming a logical text line."""

    glyphs: List[GlyphBox] = field(default_factory=list)
    bbox: Tuple[float, float, float, float] = (
        0.0,
        0.0,
        0.0,
        0.0,
    )  # (min_x, min_y, max_x, max_y)

    @property
    def text(self) -> str:
        return "".join(g.text for g in self.glyphs)

    @property
    def min_x(self) -> float:
        return self.bbox[0]

    @property
    def min_y(self) -> float:
        return self.bbox[1]

    @property
    def max_x(self) -> float:
        return self.bbox[2]

    @property
    def max_y(self) -> float:
        return self.bbox[3]


@dataclass
class ColumnBlock:
    """A vertical column containing ordered text lines."""

    lines: List[TextLine] = field(default_factory=list)
    min_x: float = 0.0
    max_x: float = 0.0


@dataclass
class PdfPage:
    """Represents an individual page within a parsed PDF document."""

    page_num: int
    width: float
    height: float
    contents: List[bytes]
    resources: Dict[str, Any] = field(default_factory=dict)
    media_box: Tuple[float, float, float, float] = (
        0.0,
        0.0,
        612.0,
        792.0,
    )  # Default Letter


@dataclass
class ExtractionMetrics:
    """Evaluation metrics for measuring PDF text extraction quality."""

    char_recall: float
    word_f1: float
    similarity: float
    abstract_captured: bool
    column_interleaving_score: float
