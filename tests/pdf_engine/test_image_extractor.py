"""Unit tests for Pure-Python PDF Image Extractor with SC-1 to SC-6 Security Controls."""

import os
import struct
import tempfile
import zlib

from pdf_engine.contracts import IndirectRef, PdfPage, PdfStream
from pdf_engine.extractor import PurePdfTextExtractor
from pdf_engine.image_extractor import (
    PdfImageExtractor,
    _build_png_bytes,
    _has_malicious_script_tags,
    _is_valid_figure_dimension,
    _sanitize_xobject_name,
)
from pdf_engine.xref import XRefResolver

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def test_is_valid_figure_dimension_sc2() -> None:
    """SC-2: Dimension & Pixel Flood Guards."""
    # Invalid types
    assert not _is_valid_figure_dimension("400", 300)
    assert not _is_valid_figure_dimension(400, None)

    # Too small (icons, bullets)
    assert not _is_valid_figure_dimension(100, 50)
    assert not _is_valid_figure_dimension(149, 100)
    assert not _is_valid_figure_dimension(200, 99)

    # Valid range
    assert _is_valid_figure_dimension(150, 100)
    assert _is_valid_figure_dimension(800, 600)
    assert _is_valid_figure_dimension(1920, 1080)
    assert _is_valid_figure_dimension(4000, 4000)

    # DoS attack / oversized dimensions
    assert not _is_valid_figure_dimension(4097, 1000)
    assert not _is_valid_figure_dimension(1000, 4097)

    # Pixel flood (16 Megapixels exceeded)
    assert not _is_valid_figure_dimension(4096, 4096)  # 16,777,216 > 16,000,000


def test_sanitize_xobject_name_sc3() -> None:
    """SC-3: Path Traversal & Special Characters Sanitization."""
    assert _sanitize_xobject_name("/Im1") == "Im1"
    assert _sanitize_xobject_name("../../../etc/passwd") == "etc_passwd"
    assert _sanitize_xobject_name("Image with spaces.png") == "Image_with_spaces_png"
    assert _sanitize_xobject_name("") == "image"
    assert _sanitize_xobject_name("///$$$///") == "image"


def test_malicious_script_tags_detection_sc4() -> None:
    """SC-4: Detection of HTML/JS script tags inside image streams."""
    safe_jpeg = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00"
    assert not _has_malicious_script_tags(safe_jpeg)

    polyglot_script = b"\xff\xd8\xff\xfe\x00<script>alert(1)</script>"
    assert _has_malicious_script_tags(polyglot_script)

    polyglot_svg = b"\xff\xd8\xff\xfe\x00<svg onload=alert(1)>"
    assert _has_malicious_script_tags(polyglot_svg)

    polyglot_php = b"\xff\xd8\xff\xfe\x00<?php phpinfo(); ?>"
    assert _has_malicious_script_tags(polyglot_php)


def test_build_png_bytes_rgb() -> None:
    width = 2
    height = 2
    raw_rgb = b"\xff\x00\x00" * 4
    png_data = _build_png_bytes(raw_rgb, width, height, color_type=2)

    assert png_data.startswith(PNG_SIGNATURE)
    assert png_data.endswith(b"IEND\xaeB`\x82")

    ihdr_start = len(PNG_SIGNATURE)
    ihdr_len = struct.unpack(">I", png_data[ihdr_start : ihdr_start + 4])[0]
    assert ihdr_len == 13
    assert png_data[ihdr_start + 4 : ihdr_start + 8] == b"IHDR"

    ihdr_data = png_data[ihdr_start + 8 : ihdr_start + 8 + 13]
    w, h, depth, ctype, comp, filt, interlace = struct.unpack(">IIBBBBB", ihdr_data)
    assert w == 2
    assert h == 2
    assert depth == 8
    assert ctype == 2
    assert comp == 0
    assert filt == 0
    assert interlace == 0


def test_build_png_bytes_grayscale() -> None:
    width = 3
    height = 1
    raw_gray = b"\x10\x20\x30"
    png_data = _build_png_bytes(raw_gray, width, height, color_type=0)

    assert png_data.startswith(PNG_SIGNATURE)
    assert png_data.endswith(b"IEND\xaeB`\x82")


def test_decompression_bomb_prevention_sc1() -> None:
    """SC-1: Pre-decompression estimation exceeds MAX_DECOMPRESSED_BYTES."""
    # 4000 x 3000 x 3 bytes = 36 MB > 30 MB
    img_stream = PdfStream(
        dictionary={
            "/Subtype": "/Image",
            "/Width": 4000,
            "/Height": 3000,
            "/ColorSpace": "/DeviceRGB",
            "/Filter": "/FlateDecode",
        },
        data=b"tiny_compressed_bomb",
    )
    page = PdfPage(
        page_num=1,
        width=612.0,
        height=792.0,
        resources={"/XObject": {"/Bomb": img_stream}},
        contents=[],
    )

    raw_bytes = b"%PDF-1.4\n%%EOF"
    xref = XRefResolver(raw_bytes)
    extractor = PdfImageExtractor(xref)

    with tempfile.TemporaryDirectory() as tmpdir:
        figs = extractor.extract_and_save(pages=[page], output_dir=tmpdir)
        # Bomb must be safely rejected without crashing or expanding memory
        assert figs == []


def test_circular_reference_guard_sc6() -> None:
    """SC-6: Circular IndirectRef Resolution Guard."""
    raw_bytes = b"%PDF-1.4\n%%EOF"
    xref = XRefResolver(raw_bytes)
    # Mock circular lookup: ref (10, 0) points to itself or cycles
    ref = IndirectRef(obj_num=10, gen_num=0)
    xref.offsets[10] = 0

    extractor = PdfImageExtractor(xref)
    page = PdfPage(
        page_num=1,
        width=612.0,
        height=792.0,
        resources={"/XObject": ref},
        contents=[],
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        figs = extractor.extract_and_save(pages=[page], output_dir=tmpdir)
        assert figs == []


def test_extract_images_synthetic_jpeg_and_polyglot_rejection() -> None:
    """SC-4: Valid JPEG accepted, Polyglot JPEG rejected."""
    fake_jpeg = (
        b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00`\x00`\x00\x00\xff\xd9"
    )
    safe_stream = PdfStream(
        dictionary={
            "/Subtype": "/Image",
            "/Width": 200,
            "/Height": 150,
            "/ColorSpace": "/DeviceRGB",
            "/Filter": "/DCTDecode",
        },
        data=fake_jpeg,
    )
    bad_stream = PdfStream(
        dictionary={
            "/Subtype": "/Image",
            "/Width": 200,
            "/Height": 150,
            "/ColorSpace": "/DeviceRGB",
            "/Filter": "/DCTDecode",
        },
        data=b"\xff\xd8<script>alert('pwn')</script>\xff\xd9",
    )

    page = PdfPage(
        page_num=1,
        width=612.0,
        height=792.0,
        resources={"/XObject": {"/Safe": safe_stream, "/Evil": bad_stream}},
        contents=[],
    )

    raw_bytes = b"%PDF-1.4\n%%EOF"
    xref = XRefResolver(raw_bytes)
    extractor = PdfImageExtractor(xref)

    with tempfile.TemporaryDirectory() as tmpdir:
        figs = extractor.extract_and_save(pages=[page], output_dir=tmpdir)
        # Evil stream must be rejected; safe stream accepted
        assert len(figs) == 1
        assert figs[0].width == 200
        assert figs[0].format == "jpg"
        assert "Evil" not in figs[0].fig_id


def test_extract_images_synthetic_flate_png() -> None:
    width = 160
    height = 120
    raw_rgb = b"\xaa\xbb\xcc" * (width * height)
    compressed = zlib.compress(raw_rgb)

    img_stream = PdfStream(
        dictionary={
            "/Subtype": "/Image",
            "/Width": width,
            "/Height": height,
            "/ColorSpace": "/DeviceRGB",
            "/BitsPerComponent": 8,
            "/Filter": "/FlateDecode",
        },
        data=compressed,
    )

    page = PdfPage(
        page_num=2,
        width=612.0,
        height=792.0,
        resources={"/XObject": {"/FigA": img_stream}},
        contents=[],
    )

    raw_bytes = b"%PDF-1.4\n%%EOF"
    xref = XRefResolver(raw_bytes)
    extractor = PdfImageExtractor(xref)

    with tempfile.TemporaryDirectory() as tmpdir:
        figs = extractor.extract_and_save(pages=[page], output_dir=tmpdir)
        assert len(figs) == 1
        assert figs[0].width == 160
        assert figs[0].height == 120
        assert figs[0].format == "png"
        assert os.path.exists(figs[0].file_path)
        with open(figs[0].file_path, "rb") as f:
            assert f.read().startswith(PNG_SIGNATURE)


def test_pure_pdf_text_extractor_integration() -> None:
    header = b"%PDF-1.4\n"
    obj1 = b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
    obj2 = b"2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n"
    off1 = len(header)
    off2 = off1 + len(obj1)
    xref_off = off2 + len(obj2)

    xref_sec = (
        b"xref\n0 3\n"
        b"0000000000 65535 f \n"
        + f"{off1:010d} 00000 n \n".encode("ascii")
        + f"{off2:010d} 00000 n \n".encode("ascii")
    )
    trailer = (
        b"trailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n"
        + str(xref_off).encode("ascii")
        + b"\n%%EOF"
    )
    valid_pdf = header + obj1 + obj2 + xref_sec + trailer

    with tempfile.TemporaryDirectory() as tmpdir:
        pdf_path = os.path.join(tmpdir, "sample.pdf")
        with open(pdf_path, "wb") as f:
            f.write(valid_pdf)

        figures_dir = os.path.join(tmpdir, "figs")
        figs = PurePdfTextExtractor.extract_figures(pdf_path, figures_dir)
        assert figs == []

        txt, figs2 = PurePdfTextExtractor.extract_text_and_figures(
            pdf_path, figures_dir
        )
        assert isinstance(txt, str)
        assert figs2 == []
