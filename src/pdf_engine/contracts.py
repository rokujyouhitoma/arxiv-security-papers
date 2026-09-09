"""Contracts, data classes, and type definitions for Pure Python PDF Engine."""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple

from core.hsm import HierarchicalStateMachine, StateNode, TransitionRule

# Event constants for PDF Stream Decoding & Safety Guard HSM
EVENT_START_PARSING = "START_PARSING"
EVENT_HEADER_PARSED = "HEADER_PARSED"
EVENT_FILTER_START = "FILTER_START"
EVENT_DECOMPRESS = "DECOMPRESS"
EVENT_CHECK_SAFETY = "CHECK_SAFETY"
EVENT_DECODING_DONE = "DECODING_DONE"
EVENT_SYNTHESIS_DONE = "SYNTHESIS_DONE"
EVENT_SAFETY_VIOLATION = "SAFETY_VIOLATION"
EVENT_FAIL = "FAIL"


@dataclass(frozen=True)
class SafetyLimitConfig:
    """Resource constraints to mitigate Decompression Bomb (CWE-409) and DoS attacks."""

    max_decompressed_bytes: int = 33_554_432  # 32 MiB
    max_expansion_ratio: float = 1000.0  # Max 1000:1 ratio
    max_filter_depth: int = 5  # Max chained filters


class PdfSafetyLimitExceededError(Exception):
    """Raised when PDF stream decoding exceeds safe expansion or memory boundaries."""


def _add_pdf_processing_nodes(root: StateNode) -> None:
    """Builds the PROCESSING state hierarchy for PDF Engine HSM."""
    proc = root.add_child(StateNode("PROCESSING", initial_child="PARSING_HEADER"))
    proc.add_child(StateNode("PARSING_HEADER"))
    dec = proc.add_child(StateNode("STREAM_DECODING", initial_child="APPLYING_FILTER"))
    dec.add_child(StateNode("APPLYING_FILTER"))
    dec.add_child(StateNode("DECOMPRESSING"))
    dec.add_child(StateNode("SAFETY_LIMIT_CHECK"))
    proc.add_child(StateNode("LAYOUT_SYNTHESIS"))


def _add_pdf_terminated_nodes(root: StateNode) -> None:
    """Builds the TERMINATED state hierarchy for PDF Engine HSM."""
    term = root.add_child(StateNode("TERMINATED", initial_child="COMPLETED"))
    term.add_child(StateNode("COMPLETED"))
    term.add_child(StateNode("FAILED"))


def _register_pdf_transition_rules(root: StateNode) -> None:
    """Registers transition pathways for PDF Engine HSM."""
    root.add_transition(
        TransitionRule(
            "PARSING_HEADER",
            EVENT_HEADER_PARSED,
            "PROCESSING.STREAM_DECODING.APPLYING_FILTER",
        )
    )
    root.add_transition(
        TransitionRule(
            "APPLYING_FILTER",
            EVENT_DECOMPRESS,
            "PROCESSING.STREAM_DECODING.DECOMPRESSING",
        )
    )
    root.add_transition(
        TransitionRule(
            "DECOMPRESSING",
            EVENT_CHECK_SAFETY,
            "PROCESSING.STREAM_DECODING.SAFETY_LIMIT_CHECK",
        )
    )
    root.add_transition(
        TransitionRule(
            "SAFETY_LIMIT_CHECK",
            EVENT_FILTER_START,
            "PROCESSING.STREAM_DECODING.APPLYING_FILTER",
        )
    )
    root.add_transition(
        TransitionRule(
            "SAFETY_LIMIT_CHECK",
            EVENT_DECODING_DONE,
            "PROCESSING.LAYOUT_SYNTHESIS",
        )
    )
    root.add_transition(
        TransitionRule(
            "STREAM_DECODING",
            EVENT_DECODING_DONE,
            "PROCESSING.LAYOUT_SYNTHESIS",
        )
    )
    root.add_transition(
        TransitionRule(
            "LAYOUT_SYNTHESIS",
            EVENT_SYNTHESIS_DONE,
            "TERMINATED.COMPLETED",
        )
    )
    root.add_transition(
        TransitionRule(
            "PROCESSING",
            EVENT_SAFETY_VIOLATION,
            "TERMINATED.FAILED",
        )
    )
    root.add_transition(
        TransitionRule(
            "PROCESSING",
            EVENT_FAIL,
            "TERMINATED.FAILED",
        )
    )


def build_pdf_stream_hsm(
    config: Optional[SafetyLimitConfig] = None,
) -> HierarchicalStateMachine:
    """Constructs the PDF Engine parsing, stream decoding and safety guard HSM tree."""
    _ = config or SafetyLimitConfig()
    root = StateNode("ROOT", initial_child="PROCESSING")
    _add_pdf_processing_nodes(root)
    _add_pdf_terminated_nodes(root)
    _register_pdf_transition_rules(root)
    return HierarchicalStateMachine(root)


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
