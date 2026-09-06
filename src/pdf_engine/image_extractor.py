#!/usr/bin/env python3
"""
Pure-Python PDF Figure and Diagram Extractor (ISO 32000-1 Clause 8.9).
Extracts XObject images (JPEG/PNG) from PDF pages with defense-in-depth security controls (SC-1 to SC-6).
"""

from __future__ import annotations

import json
import os
import re
import struct
import zlib
from dataclasses import asdict, dataclass
from typing import Any, Dict, List, Optional, Set, Tuple

from .contracts import IndirectRef, PdfPage, PdfStream
from .decompress import StreamDecompressor
from .xref import XRefResolver

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MIN_FIGURE_WIDTH = 150
MIN_FIGURE_HEIGHT = 100
MAX_DIMENSION = 4096
MAX_TOTAL_PIXELS = 16_000_000  # 16 Megapixels (SC-2)
MAX_DECOMPRESSED_BYTES = 30 * 1024 * 1024  # 30 MB DoS guard (SC-1)
MAX_CUMULATIVE_FIGURE_BYTES = 50 * 1024 * 1024  # 50 MB total extraction limit (SC-1)
MAX_PAGE_XOBJECT_SCAN = 50  # SC-5 ReDoS / CPU guard

DANGEROUS_PAYLOADS: Tuple[bytes, ...] = (
    b"<script",
    b"<svg",
    b"<?php",
    b"javascript:",
    b"<html",
    b"onload=",
    b"onerror=",
)


@dataclass
class FigureMetadata:
    """Metadata representing an extracted figure or architecture diagram."""

    fig_id: str
    page_num: int
    width: int
    height: int
    format: str
    file_path: str
    relative_path: str


def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    """Constructs a binary PNG chunk with length and CRC32."""
    length = struct.pack(">I", len(data))
    crc = struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
    return length + chunk_type + data + crc


def _build_png_bytes(
    raw_pixels: bytes, width: int, height: int, color_type: int
) -> bytes:
    """Synthesizes valid 8-bit PNG binary from raw uncompressed pixels (SC-4)."""
    bytes_per_pixel = 3 if color_type == 2 else 1
    stride = width * bytes_per_pixel
    expected_length = stride * height

    pixel_data = raw_pixels[:expected_length]
    if len(pixel_data) < expected_length:
        pixel_data = pixel_data + b"\x00" * (expected_length - len(pixel_data))

    scanlines = bytearray()
    for row in range(height):
        scanlines.append(0)  # Filter type: None
        start = row * stride
        scanlines.extend(pixel_data[start : start + stride])

    compressed_idat = zlib.compress(bytes(scanlines), level=6)

    ihdr_data = struct.pack(
        ">IIBBBBB",
        width,
        height,
        8,  # Bit depth: 8 bits per channel
        color_type,  # 2: RGB, 0: Grayscale
        0,  # Compression: deflate
        0,  # Filter: adaptive
        0,  # Interlace: none
    )

    chunks = [
        PNG_SIGNATURE,
        _png_chunk(b"IHDR", ihdr_data),
        _png_chunk(b"IDAT", compressed_idat),
        _png_chunk(b"IEND", b""),
    ]
    return b"".join(chunks)


def _is_valid_dimension_bounds(width: int, height: int) -> bool:
    if width < MIN_FIGURE_WIDTH or height < MIN_FIGURE_HEIGHT:
        return False
    return width <= MAX_DIMENSION and height <= MAX_DIMENSION


def _is_valid_figure_dimension(width: Any, height: Any) -> bool:
    """Verifies image dimensions meet minimum diagram thresholds and stay within DoS bounds (SC-2)."""
    if not isinstance(width, int) or not isinstance(height, int):
        return False
    if not _is_valid_dimension_bounds(width, height):
        return False
    return (width * height) <= MAX_TOTAL_PIXELS


def _sanitize_xobject_name(raw_name: str) -> str:
    """Sanitizes PDF XObject name to prevent path traversal and shell injection (SC-3)."""
    clean = raw_name.lstrip("/").strip()
    sanitized = re.sub(r"[^a-zA-Z0-9_-]+", "_", clean).strip("_")
    return sanitized[:32] or "image"


def _has_malicious_script_tags(data: bytes) -> bool:
    """Detects HTML/JavaScript polyglot payload markers in image stream (SC-4)."""
    probe = data[:2048].lower()
    for pattern in DANGEROUS_PAYLOADS:
        if pattern in probe:
            return True
    return False


class PdfImageExtractor:
    """
    Pure-Python XObject Image Extractor conforming to ISO 32000-1 Clause 8.9.
    Equipped with multi-layer Security Controls (SC-1 through SC-6).
    """

    def __init__(self, xref: XRefResolver) -> None:
        self.xref = xref
        self._visited_refs: Set[Tuple[int, int]] = set()

    def _resolve_xobject_dict(self, page: PdfPage) -> Dict[str, Any]:
        resources = page.resources
        xobj_dict = resources.get("/XObject")
        if isinstance(xobj_dict, IndirectRef):
            ref_key = (xobj_dict.obj_num, xobj_dict.gen_num)
            if ref_key in self._visited_refs:
                return {}
            self._visited_refs.add(ref_key)
            resolved = self.xref.resolve_object(xobj_dict)
            return resolved if isinstance(resolved, dict) else {}
        return xobj_dict if isinstance(xobj_dict, dict) else {}

    def _resolve_stream(self, ref_or_stream: Any) -> Optional[PdfStream]:
        if isinstance(ref_or_stream, IndirectRef):
            ref_key = (ref_or_stream.obj_num, ref_or_stream.gen_num)
            if ref_key in self._visited_refs:
                return None
            self._visited_refs.add(ref_key)
            obj = self.xref.resolve_object(ref_or_stream)
            return obj if isinstance(obj, PdfStream) else None
        if isinstance(ref_or_stream, PdfStream):
            return ref_or_stream
        return None

    def _extract_dct_image(
        self, stream: PdfStream, width: int, height: int
    ) -> Optional[Tuple[bytes, str, int, int]]:
        """Handles JPEG images encoded with /DCTDecode with Polyglot guard (SC-4)."""
        raw_data = stream.data
        if not raw_data.startswith(b"\xff\xd8"):
            raw_data = StreamDecompressor.decompress(
                raw_data, stream.dictionary.get("/Filter")
            )
        if not raw_data.startswith(b"\xff\xd8"):
            return None
        if _has_malicious_script_tags(raw_data):
            return None
        return (raw_data, "jpg", width, height)

    def _extract_flate_image(
        self, stream: PdfStream, width: int, height: int
    ) -> Optional[Tuple[bytes, str, int, int]]:
        """Handles PNG synthesis from /FlateDecode with Decompression Bomb guard (SC-1)."""
        cs = str(stream.dictionary.get("/ColorSpace", "/DeviceRGB"))
        color_type = 0 if "gray" in cs.lower() else 2
        bpp = 1 if color_type == 0 else 3
        expected_size = width * height * bpp

        if expected_size > MAX_DECOMPRESSED_BYTES:
            return None

        decompressed = StreamDecompressor.decompress(
            stream.data,
            stream.dictionary.get("/Filter"),
            stream.dictionary.get("/DecodeParms"),
        )
        if len(decompressed) > MAX_DECOMPRESSED_BYTES:
            return None

        png_bytes = _build_png_bytes(decompressed, width, height, color_type)
        return (png_bytes, "png", width, height)

    def _process_image_stream(
        self, stream: PdfStream
    ) -> Optional[Tuple[bytes, str, int, int]]:
        sub_type = str(stream.dictionary.get("/Subtype", ""))
        if sub_type != "/Image":
            return None

        width = stream.dictionary.get("/Width", 0)
        height = stream.dictionary.get("/Height", 0)
        if not _is_valid_figure_dimension(width, height):
            return None

        filt = str(stream.dictionary.get("/Filter", ""))
        if "/DCTDecode" in filt or "dct" in filt.lower():
            return self._extract_dct_image(stream, int(width), int(height))
        return self._extract_flate_image(stream, int(width), int(height))

    def _extract_single_xobject(
        self, name: str, ref: Any
    ) -> Optional[Tuple[bytes, str, int, int, str]]:
        stream = self._resolve_stream(ref)
        if not stream:
            return None
        res = self._process_image_stream(stream)
        if not res:
            return None
        img_bytes, ext, w, h = res
        clean_name = _sanitize_xobject_name(name)
        return (img_bytes, ext, w, h, clean_name)

    def extract_figures_from_page(
        self, page: PdfPage, max_per_page: int = 5
    ) -> List[Tuple[bytes, str, int, int, str]]:
        """Extracts candidate figure images from a single PDF page with scan limit (SC-5)."""
        xobjects = self._resolve_xobject_dict(page)
        figures: List[Tuple[bytes, str, int, int, str]] = []

        for idx, (name, ref) in enumerate(xobjects.items()):
            if idx >= MAX_PAGE_XOBJECT_SCAN or len(figures) >= max_per_page:
                break
            extracted = self._extract_single_xobject(name, ref)
            if extracted:
                figures.append(extracted)

        return figures

    def _save_figure(
        self,
        output_dir: str,
        page_num: int,
        idx: int,
        img_info: Tuple[bytes, str, int, int, str],
    ) -> Optional[FigureMetadata]:
        """Saves figure file with Path Traversal verification (SC-3)."""
        img_bytes, ext, w, h, clean_name = img_info
        fig_id = f"fig_p{page_num}_{idx:02d}_{clean_name}"
        filename = f"{fig_id}.{ext}"
        file_path = os.path.join(output_dir, filename)

        real_out = os.path.realpath(output_dir)
        real_target = os.path.realpath(file_path)
        if not real_target.startswith(real_out + os.sep) and real_target != real_out:
            return None

        with open(file_path, "wb") as f:
            f.write(img_bytes)

        return FigureMetadata(
            fig_id=fig_id,
            page_num=page_num,
            width=w,
            height=h,
            format=ext,
            file_path=file_path,
            relative_path=filename,
        )

    def _append_page_figures(
        self,
        output_dir: str,
        page: PdfPage,
        results: List[FigureMetadata],
        max_total: int,
        cumulative_bytes: List[int],
    ) -> None:
        for fig_info in self.extract_figures_from_page(page):
            if len(results) >= max_total:
                break
            img_len = len(fig_info[0])
            if cumulative_bytes[0] + img_len > MAX_CUMULATIVE_FIGURE_BYTES:
                break
            meta = self._save_figure(
                output_dir, page.page_num, len(results) + 1, fig_info
            )
            if meta:
                cumulative_bytes[0] += img_len
                results.append(meta)

    def extract_and_save(
        self,
        pages: List[PdfPage],
        output_dir: str,
        max_total_figures: int = 10,
    ) -> List[FigureMetadata]:
        """Extracts figures across all pages and persists them to output_dir with total byte limits (SC-1)."""
        os.makedirs(output_dir, exist_ok=True)
        results: List[FigureMetadata] = []
        cumulative_bytes = [0]

        for page in pages:
            if len(results) >= max_total_figures:
                break
            if cumulative_bytes[0] >= MAX_CUMULATIVE_FIGURE_BYTES:
                break
            self._append_page_figures(
                output_dir, page, results, max_total_figures, cumulative_bytes
            )

        meta_path = os.path.join(output_dir, "metadata.json")
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump([asdict(r) for r in results], f, indent=2, ensure_ascii=False)

        return results
