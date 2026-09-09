"""Unified High-Level Pure Python PDF Text Extraction API."""

import io
import os
from typing import List, Optional, Tuple, Union

from core.hsm import HierarchicalStateMachine

from .contracts import (
    EVENT_DECODING_DONE,
    EVENT_FAIL,
    EVENT_HEADER_PARSED,
    EVENT_SAFETY_VIOLATION,
    EVENT_SYNTHESIS_DONE,
    PdfPage,
    PdfSafetyLimitExceededError,
    SafetyLimitConfig,
    build_pdf_stream_hsm,
)
from .image_extractor import FigureMetadata, PdfImageExtractor
from .interpreter import TextInterpreter
from .layout import SpatialLayoutEngine
from .navigator import PageTreeNavigator
from .xref import XRefResolver


def _init_pipeline_context(
    config: Optional[SafetyLimitConfig],
    hsm: Optional[HierarchicalStateMachine],
) -> Tuple[SafetyLimitConfig, HierarchicalStateMachine]:
    """Resolves or initializes the safety limit configuration and HSM."""
    cfg = config if config is not None else SafetyLimitConfig()
    state_m = hsm if hsm is not None else build_pdf_stream_hsm(cfg)
    return cfg, state_m


def _handle_pipeline_exception(
    exc: Exception, state_m: HierarchicalStateMachine
) -> None:
    """Dispatches fail-secure events upon pipeline error and re-raises."""
    if not state_m.is_in_state("TERMINATED.FAILED"):
        event = (
            EVENT_SAFETY_VIOLATION
            if isinstance(exc, PdfSafetyLimitExceededError)
            else EVENT_FAIL
        )
        state_m.send_event(event)
    raise exc


def _read_file_bytes(source: str) -> bytes:
    """Reads byte content from a filesystem path if it exists."""
    if not os.path.exists(source):
        return b""
    with open(source, "rb") as f:
        return f.read()


class PurePdfTextExtractor:
    """Zero-dependency Pure Python PDF Text Extraction Engine conforming to ISO 32000-1."""

    @classmethod
    def _parse_and_navigate(
        cls,
        raw_bytes: bytes,
        hsm: HierarchicalStateMachine,
        cfg: SafetyLimitConfig,
    ) -> Tuple[XRefResolver, List[PdfPage]]:
        """Parses XRef header and resolves pages with stream safety checks."""
        xref = XRefResolver(raw_bytes)
        xref.parse_all_xrefs()
        hsm.send_event(EVENT_HEADER_PARSED)

        navigator = PageTreeNavigator(xref, hsm=hsm, config=cfg)
        pages = navigator.extract_all_pages()
        hsm.send_event(EVENT_DECODING_DONE)
        return xref, pages

    @classmethod
    def _synthesize_layout(
        cls, pages: List[PdfPage], hsm: HierarchicalStateMachine
    ) -> str:
        """Extracts glyphs and synthesizes 2D spatial text layout."""
        pages_text: List[str] = []
        for page in pages:
            interpreter = TextInterpreter(page)
            glyphs = interpreter.extract_glyphs()
            page_text = SpatialLayoutEngine.reconstruct(glyphs, page.width, page.height)
            if page_text:
                pages_text.append(page_text)

        hsm.send_event(EVENT_SYNTHESIS_DONE)
        return "\n\n".join(pages_text)

    @classmethod
    def _execute_extraction_pipeline(
        cls,
        raw_bytes: bytes,
        config: Optional[SafetyLimitConfig] = None,
        hsm: Optional[HierarchicalStateMachine] = None,
    ) -> str:
        cfg, state_m = _init_pipeline_context(config, hsm)
        try:
            _, pages = cls._parse_and_navigate(raw_bytes, state_m, cfg)
            return cls._synthesize_layout(pages, state_m)
        except Exception as exc:
            _handle_pipeline_exception(exc, state_m)
            return ""

    @classmethod
    def extract_text(
        cls,
        source: Union[str, bytes, io.BytesIO],
        config: Optional[SafetyLimitConfig] = None,
        hsm: Optional[HierarchicalStateMachine] = None,
    ) -> str:
        """Extracts normalized UTF-8 text with 2D spatial two-column layout reconstruction.

        Args:
            source: File path (str), raw PDF byte sequence (bytes), or io.BytesIO stream.
            config: Optional resource limits to prevent Decompression Bombs.
            hsm: Optional state machine to track extraction lifecycle.

        Returns:
            Extracted UTF-8 plain text string.
        """
        raw_bytes = cls._load_bytes(source)
        if not raw_bytes:
            return ""
        return cls._execute_extraction_pipeline(raw_bytes, config, hsm)

    @classmethod
    def extract_figures(
        cls,
        source: Union[str, bytes, io.BytesIO],
        output_dir: str,
        max_figures: int = 10,
    ) -> List[FigureMetadata]:
        """Extracts figures, diagrams, and architecture charts from PDF to output_dir."""
        raw_bytes = cls._load_bytes(source)
        if not raw_bytes:
            return []

        xref = XRefResolver(raw_bytes)
        xref.parse_all_xrefs()

        navigator = PageTreeNavigator(xref)
        pages = navigator.extract_all_pages()

        extractor = PdfImageExtractor(xref)
        return extractor.extract_and_save(
            pages=pages, output_dir=output_dir, max_total_figures=max_figures
        )

    @classmethod
    def _extract_figures_from_pages(
        cls,
        xref: XRefResolver,
        pages: List[PdfPage],
        output_dir: str,
        max_figures: int,
    ) -> List[FigureMetadata]:
        """Extracts and persists image figures from document pages."""
        img_extractor = PdfImageExtractor(xref)
        return img_extractor.extract_and_save(
            pages=pages,
            output_dir=output_dir,
            max_total_figures=max_figures,
        )

    @classmethod
    def extract_text_and_figures(
        cls,
        source: Union[str, bytes, io.BytesIO],
        figures_output_dir: str,
        max_figures: int = 10,
        config: Optional[SafetyLimitConfig] = None,
        hsm: Optional[HierarchicalStateMachine] = None,
    ) -> Tuple[str, List[FigureMetadata]]:
        """Extracts text and figures in a single parsing pass."""
        raw_bytes = cls._load_bytes(source)
        if len(raw_bytes) == 0:
            return "", []

        cfg, state_m = _init_pipeline_context(config, hsm)
        try:
            xref, pages = cls._parse_and_navigate(raw_bytes, state_m, cfg)
            text = cls._synthesize_layout(pages, state_m)
            figures = cls._extract_figures_from_pages(
                xref, pages, figures_output_dir, max_figures
            )
            return text, figures
        except Exception as exc:
            _handle_pipeline_exception(exc, state_m)
            return "", []

    @classmethod
    def extract_text_from_file(cls, filepath: str) -> str:
        """Extracts text from a file path on disk."""
        return cls.extract_text(filepath)

    @classmethod
    def extract_text_from_bytes(cls, pdf_bytes: bytes) -> str:
        """Extracts text directly from in-memory byte buffer."""
        return cls.extract_text(pdf_bytes)

    @staticmethod
    def _load_bytes(source: Union[str, bytes, io.BytesIO]) -> bytes:
        if isinstance(source, str):
            return _read_file_bytes(source)
        if isinstance(source, io.BytesIO):
            return source.getvalue()
        if isinstance(source, (bytes, bytearray, memoryview)):
            return bytes(source)
        return b""
