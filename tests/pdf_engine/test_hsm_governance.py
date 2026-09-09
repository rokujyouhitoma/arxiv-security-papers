#!/usr/bin/env python3
"""
Unit and integration tests for PDF Engine Stream Decoding & Safety Guard HSM Governance.
Verifies CWE-409 Decompression Bomb defense, lifecycle transitions, and fail-secure traps.
"""

import zlib

import pytest

from pdf_engine.contracts import (
    EVENT_CHECK_SAFETY,
    EVENT_DECODING_DONE,
    EVENT_DECOMPRESS,
    EVENT_FILTER_START,
    EVENT_HEADER_PARSED,
    EVENT_SYNTHESIS_DONE,
    PdfSafetyLimitExceededError,
    SafetyLimitConfig,
    build_pdf_stream_hsm,
)
from pdf_engine.decompress import StreamDecompressor
from pdf_engine.extractor import PurePdfTextExtractor


def test_pdf_hsm_tree_structure() -> None:
    """Verifies that the PDF Stream HSM initializes in PROCESSING.PARSING_HEADER."""
    hsm = build_pdf_stream_hsm()
    assert hsm.current_state.get_path() == "PROCESSING.PARSING_HEADER"
    assert hsm.is_in_state("PROCESSING")
    assert hsm.is_in_state("PROCESSING.PARSING_HEADER")


def test_pdf_hsm_manual_lifecycle_transitions() -> None:
    """Tests the step-by-step deterministic progression through all HSM states."""
    hsm = build_pdf_stream_hsm()

    # 1. Header parsed -> moves to STREAM_DECODING.APPLYING_FILTER
    res = hsm.send_event(EVENT_HEADER_PARSED)
    assert res is True
    assert hsm.current_state.get_path() == "PROCESSING.STREAM_DECODING.APPLYING_FILTER"

    # 2. Decompressing filter
    res = hsm.send_event(EVENT_DECOMPRESS)
    assert res is True
    assert hsm.current_state.get_path() == "PROCESSING.STREAM_DECODING.DECOMPRESSING"

    # 3. Safety check
    res = hsm.send_event(EVENT_CHECK_SAFETY)
    assert res is True
    assert (
        hsm.current_state.get_path() == "PROCESSING.STREAM_DECODING.SAFETY_LIMIT_CHECK"
    )

    # 4. Next filter in chain
    res = hsm.send_event(EVENT_FILTER_START)
    assert res is True
    assert hsm.current_state.get_path() == "PROCESSING.STREAM_DECODING.APPLYING_FILTER"

    # 5. Finished stream decoding -> LAYOUT_SYNTHESIS
    res = hsm.send_event(EVENT_DECODING_DONE)
    assert res is True
    assert hsm.current_state.get_path() == "PROCESSING.LAYOUT_SYNTHESIS"

    # 6. Layout synthesis complete -> TERMINATED.COMPLETED
    res = hsm.send_event(EVENT_SYNTHESIS_DONE)
    assert res is True
    assert hsm.current_state.get_path() == "TERMINATED.COMPLETED"
    assert hsm.is_in_state("TERMINATED")


def test_stream_decompressor_filter_depth_violation() -> None:
    """Verifies rejection of deep nested filter chains exceeding safety limits."""
    hsm = build_pdf_stream_hsm()
    hsm.send_event(EVENT_HEADER_PARSED)

    cfg = SafetyLimitConfig(max_filter_depth=3)
    filters = ["/FlateDecode", "/ASCII85Decode", "/FlateDecode", "/ASCIIHexDecode"]

    with pytest.raises(PdfSafetyLimitExceededError) as exc_info:
        StreamDecompressor.decompress(
            b"testpayload",
            filters,
            hsm=hsm,
            config=cfg,
        )

    assert "exceeds safety limit 3" in str(exc_info.value)
    assert hsm.is_in_state("TERMINATED.FAILED")


def test_stream_decompressor_expansion_ratio_violation() -> None:
    """Verifies CWE-409 Decompression Bomb detection via expansion ratio threshold."""
    # 50,000 repetitive bytes compress down to ~80 bytes (ratio > 600x)
    original = b"A" * 50000
    compressed = zlib.compress(original)
    assert len(compressed) < 200

    hsm = build_pdf_stream_hsm()
    hsm.send_event(EVENT_HEADER_PARSED)

    # Restrict expansion ratio to 50x
    cfg = SafetyLimitConfig(max_expansion_ratio=50.0)

    with pytest.raises(PdfSafetyLimitExceededError) as exc_info:
        StreamDecompressor.decompress(
            compressed,
            "/FlateDecode",
            hsm=hsm,
            config=cfg,
        )

    assert "Expansion ratio" in str(exc_info.value)
    assert hsm.is_in_state("TERMINATED.FAILED")


def test_stream_decompressor_max_decompressed_bytes_violation() -> None:
    """Verifies stream size threshold enforcement against memory exhaustion."""
    original = b"B" * 10000
    compressed = zlib.compress(original)

    hsm = build_pdf_stream_hsm()
    hsm.send_event(EVENT_HEADER_PARSED)

    # Restrict max decompressed size to 5,000 bytes
    cfg = SafetyLimitConfig(max_decompressed_bytes=5000, max_expansion_ratio=1000.0)

    with pytest.raises(PdfSafetyLimitExceededError) as exc_info:
        StreamDecompressor.decompress(
            compressed,
            "/FlateDecode",
            hsm=hsm,
            config=cfg,
        )

    assert "exceeds safety limit 5000" in str(exc_info.value)
    assert hsm.is_in_state("TERMINATED.FAILED")


def test_pdf_extractor_normal_document_lifecycle() -> None:
    """Verifies that an end-to-end PDF extraction transitions HSM through to COMPLETED."""
    # Construct a minimal valid PDF with a simple content stream
    content = b"BT /F1 12 Tf 72 712 Td (Hello HSM) Tj ET"
    content_compressed = zlib.compress(content)

    header = b"%PDF-1.4\n"
    obj1 = b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
    obj2 = b"2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
    obj3 = (
        b"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Contents 4 0 R /Resources << >> >>\nendobj\n"
    )
    obj4_head = (
        f"4 0 obj\n<< /Length {len(content_compressed)} /Filter /FlateDecode >>\nstream\n"
    ).encode("ascii")
    obj4 = obj4_head + content_compressed + b"\nendstream\nendobj\n"

    o1 = len(header)
    o2 = o1 + len(obj1)
    o3 = o2 + len(obj2)
    o4 = o3 + len(obj3)
    xref_off = o4 + len(obj4)

    xref_sec = b"xref\n0 5\n" b"0000000000 65535 f \n" + f"{o1:010d} 00000 n \n".encode(
        "ascii"
    ) + f"{o2:010d} 00000 n \n".encode("ascii") + f"{o3:010d} 00000 n \n".encode(
        "ascii"
    ) + f"{o4:010d} 00000 n \n".encode(
        "ascii"
    )
    trailer = (
        b"trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n"
        + str(xref_off).encode("ascii")
        + b"\n%%EOF"
    )

    sample_pdf = header + obj1 + obj2 + obj3 + obj4 + xref_sec + trailer

    hsm = build_pdf_stream_hsm()
    extracted = PurePdfTextExtractor.extract_text(sample_pdf, hsm=hsm)

    assert "Hello HSM" in extracted
    assert hsm.current_state.get_path() == "TERMINATED.COMPLETED"


def test_pdf_extractor_fail_secure_on_malformed_stream() -> None:
    """Verifies that an unhandled parsing or decompression failure triggers fail-secure trap."""
    hsm = build_pdf_stream_hsm()
    # Totally corrupt bytes
    corrupt_pdf = b"%PDF-1.4\n1 0 obj\n<< corrupt >>"

    with pytest.raises(Exception):
        PurePdfTextExtractor.extract_text(corrupt_pdf, hsm=hsm)

    assert hsm.is_in_state("TERMINATED.FAILED")
