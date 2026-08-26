"""Unified High-Level Pure Python PDF Text Extraction API."""

import io
import os
from typing import List, Union

from .interpreter import TextInterpreter
from .layout import SpatialLayoutEngine
from .navigator import PageTreeNavigator
from .xref import XRefResolver


class PurePdfTextExtractor:
    """Zero-dependency Pure Python PDF Text Extraction Engine conforming to ISO 32000-1."""

    @classmethod
    def extract_text(cls, source: Union[str, bytes, io.BytesIO]) -> str:
        """Extracts normalized UTF-8 text with 2D spatial two-column layout reconstruction.

        Args:
            source: File path (str), raw PDF byte sequence (bytes), or io.BytesIO stream.

        Returns:
            Extracted UTF-8 plain text string.
        """
        raw_bytes = cls._load_bytes(source)
        if not raw_bytes:
            return ""

        xref = XRefResolver(raw_bytes)
        xref.parse_all_xrefs()

        navigator = PageTreeNavigator(xref)
        pages = navigator.extract_all_pages()

        pages_text: List[str] = []
        for page in pages:
            interpreter = TextInterpreter(page)
            glyphs = interpreter.extract_glyphs()
            page_text = SpatialLayoutEngine.reconstruct(glyphs, page.width, page.height)
            if page_text:
                pages_text.append(page_text)

        return "\n\n".join(pages_text)

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
            if not os.path.exists(source):
                return b""
            with open(source, "rb") as f:
                return f.read()
        if isinstance(source, io.BytesIO):
            return source.getvalue()
        if isinstance(source, (bytes, bytearray, memoryview)):
            return bytes(source)
        return b""
