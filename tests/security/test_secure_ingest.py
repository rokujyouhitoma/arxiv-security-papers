#!/usr/bin/env python3
"""
Unit tests for Secure Ingestion, MIME Validation, and Parser Hardening.
"""

import pytest

from src.security.validation.file_scanner import (
    DecompressionBombError,
    DefusedXMLError,
    parse_safe_xml,
    validate_pdf_safety_metadata,
    validate_safe_decompression,
)
from src.security.validation.mime import (
    MIME_GZIP,
    MIME_JPEG,
    MIME_JSON,
    MIME_PDF,
    MIME_PNG,
    MIME_TEXT,
    MIME_XML,
    MIME_ZIP,
    detect_mime_type_from_bytes,
    is_safe_text_content,
    verify_magic_bytes,
)


def test_mime_detection_binary_formats() -> None:
    """Tests magic byte recognition for common binary document and image formats."""
    assert detect_mime_type_from_bytes(b"%PDF-1.7\n%...") == MIME_PDF
    assert detect_mime_type_from_bytes(b"\x89PNG\r\n\x1a\n\x00\x00") == MIME_PNG
    assert detect_mime_type_from_bytes(b"\xff\xd8\xff\xe0\x00\x10JFIF") == MIME_JPEG
    assert detect_mime_type_from_bytes(b"\x1f\x8b\x08\x00\x00") == MIME_GZIP
    assert detect_mime_type_from_bytes(b"PK\x03\x04\x14\x00\x00") == MIME_ZIP


def test_mime_detection_structured_formats() -> None:
    """Tests detection of JSON, XML, and plain text."""
    assert detect_mime_type_from_bytes(b'{"title": "Paper", "count": 42}') == MIME_JSON
    assert detect_mime_type_from_bytes(b'  ["item1", "item2"] ') == MIME_JSON
    assert (
        detect_mime_type_from_bytes(b'<?xml version="1.0"?><root></root>') == MIME_XML
    )
    assert detect_mime_type_from_bytes(b"<feed><title>arXiv</title></feed>") == MIME_XML
    assert (
        detect_mime_type_from_bytes(b"This is regular safe ascii text.\n") == MIME_TEXT
    )


def test_mime_detection_invalid_and_empty() -> None:
    """Tests empty, non-bytes, or random corrupt bytes."""
    assert detect_mime_type_from_bytes(b"") is None
    assert detect_mime_type_from_bytes(b"\x00\x01\x02\x03\x04") is None


def test_is_safe_text_content() -> None:
    """Tests text safety against null bytes and control chars."""
    assert is_safe_text_content("Clean documentation text\nLine 2\tTabbed")
    assert not is_safe_text_content("Null byte poison\x00malicious")
    assert not is_safe_text_content(b"Raw bytes with \x00 null")
    assert not is_safe_text_content(b"\xff\xfe\xfa\xfb")  # invalid UTF-8
    assert not is_safe_text_content("Control char \x07 bell")


def test_verify_magic_bytes_enforcement() -> None:
    """Tests verification of expected vs actual MIME types and anti-spoofing."""
    pdf_bytes = b"%PDF-2.0\n1 0 obj..."
    assert verify_magic_bytes(pdf_bytes, "application/pdf")
    assert not verify_magic_bytes(pdf_bytes, "image/png")

    xml_rss = b'<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>'
    assert verify_magic_bytes(xml_rss, "application/rss+xml")
    assert verify_magic_bytes(xml_rss, "application/xml")

    # Anti-spoofing: executable masquerading as PDF
    fake_pdf = b"#!/bin/bash\necho PWNED\n"
    assert not verify_magic_bytes(fake_pdf, "application/pdf")


def test_parse_safe_xml_valid() -> None:
    """Tests that safe, normal XML parses cleanly."""
    valid_xml = b"""<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
        <title>arXiv cs.CR</title>
        <entry>
            <id>http://arxiv.org/abs/2301.00001</id>
            <summary>Test Abstract</summary>
        </entry>
    </feed>
    """
    root = parse_safe_xml(valid_xml)
    assert "feed" in root.tag
    assert len(root) > 0


def test_parse_safe_xml_xxe_rejection() -> None:
    """Tests that XML External Entity (XXE) injection is rejected."""
    xxe_payload = b"""<?xml version="1.0" encoding="ISO-8859-1"?>
    <!DOCTYPE foo [
      <!ELEMENT foo ANY >
      <!ENTITY xxe SYSTEM "file:///etc/passwd" >]>
    <foo>&xxe;</foo>
    """
    with pytest.raises(DefusedXMLError, match="XML DTD declarations are prohibited"):
        parse_safe_xml(xxe_payload)


def test_parse_safe_xml_billion_laughs_rejection() -> None:
    """Tests that XML entity expansion attacks are blocked."""
    bomb_payload = b"""<?xml version="1.0"?>
    <!DOCTYPE lolz [
      <!ENTITY lol "lol">
      <!ENTITY lol1 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
    ]>
    <lolz>&lol1;</lolz>
    """
    with pytest.raises(DefusedXMLError, match="XML DTD declarations are prohibited"):
        parse_safe_xml(bomb_payload)


def test_validate_safe_decompression() -> None:
    """Tests decompression quota and expansion ratio thresholds."""
    # Safe 10x ratio
    assert validate_safe_decompression(
        compressed_size=100000, uncompressed_size=1000000
    )

    # Negative sizes
    with pytest.raises(DecompressionBombError, match="Invalid negative"):
        validate_safe_decompression(compressed_size=-1, uncompressed_size=100)

    # Exceeding 50MB quota
    with pytest.raises(DecompressionBombError, match="exceeds quota"):
        validate_safe_decompression(
            compressed_size=1000, uncompressed_size=60 * 1024 * 1024
        )

    # Exceeding 50x ratio on substantial payload
    with pytest.raises(DecompressionBombError, match="Expansion ratio"):
        validate_safe_decompression(
            compressed_size=10000, uncompressed_size=5 * 1024 * 1024
        )


def test_validate_pdf_safety_metadata() -> None:
    """Tests PDF file size, magic header, and dangerous active action checks."""
    valid_pdf = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
    is_safe, reason = validate_pdf_safety_metadata(valid_pdf)
    assert is_safe
    assert reason is None

    # Invalid header
    bad_header = b"NOT_A_PDF_CONTENT"
    is_safe, reason = validate_pdf_safety_metadata(bad_header)
    assert not is_safe
    assert "not a PDF file" in (reason or "")

    # Dangerous JavaScript action
    js_pdf = b"%PDF-1.4\n<< /Type /Action /S /JavaScript /JS (app.alert('evil')) >>\n"
    is_safe, reason = validate_pdf_safety_metadata(js_pdf)
    assert not is_safe
    assert "prohibited action detected" in (reason or "")

    # Dangerous Launch action
    launch_pdf = b"%PDF-1.4\n<< /Type /Action /S /Launch /F (cmd.exe) >>\n"
    is_safe, reason = validate_pdf_safety_metadata(launch_pdf)
    assert not is_safe
    assert "Launch action" in (reason or "")
