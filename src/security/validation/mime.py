#!/usr/bin/env python3
"""
MIME Type & Magic Byte Validation Module.
Verifies file payload authenticity using binary magic bytes without external C-libraries.
Detects extension spoofing, binary corruption, and prohibited non-text control characters.
Zero external runtime dependencies.
"""

import json
from typing import Callable, List, Optional, Tuple, Union

# MIME type constants
MIME_PDF = "application/pdf"
MIME_PNG = "image/png"
MIME_JPEG = "image/jpeg"
MIME_GIF = "image/gif"
MIME_GZIP = "application/gzip"
MIME_ZIP = "application/zip"
MIME_TAR = "application/x-tar"
MIME_JSON = "application/json"
MIME_XML = "application/xml"
MIME_TEXT = "text/plain"


def _check_pdf_magic(data: bytes) -> bool:
    """Checks for standard PDF header signature '%PDF-'."""
    return data.startswith(b"%PDF-")


def _check_png_magic(data: bytes) -> bool:
    """Checks for PNG 8-byte file header."""
    return data.startswith(b"\x89PNG\r\n\x1a\n")


def _check_jpeg_magic(data: bytes) -> bool:
    """Checks for JPEG start-of-image marker FF D8 FF."""
    return data.startswith(b"\xff\xd8\xff")


def _check_gif_magic(data: bytes) -> bool:
    """Checks for GIF87a or GIF89a file header."""
    return data.startswith(b"GIF87a") or data.startswith(b"GIF89a")


def _check_gzip_magic(data: bytes) -> bool:
    """Checks for GZIP compression magic bytes 1F 8B."""
    return data.startswith(b"\x1f\x8b")


def _check_zip_magic(data: bytes) -> bool:
    """Checks for standard ZIP local header signature PK 03 04."""
    return (
        data.startswith(b"PK\x03\x04")
        or data.startswith(b"PK\x05\x06")
        or data.startswith(b"PK\x07\x08")
    )


def _check_tar_magic(data: bytes) -> bool:
    """Checks for POSIX TAR archive magic at offset 257."""
    if len(data) >= 265:
        return data[257:262] == b"ustar"
    return False


def _check_xml_magic(data: bytes) -> bool:
    """Checks whether content begins with XML declaration or root tag."""
    stripped = data.lstrip()
    if stripped.startswith(b"<?xml"):
        return True
    return stripped.startswith(b"<") and not stripped.startswith(b"<!")


def _has_json_enclosing_brackets(stripped: bytes) -> bool:
    """Checks if byte string is wrapped in JSON object or array brackets."""
    is_obj = stripped.startswith(b"{") and stripped.endswith(b"}")
    is_arr = stripped.startswith(b"[") and stripped.endswith(b"]")
    return is_obj or is_arr


def _check_json_magic(data: bytes) -> bool:
    """Validates if bytes represent well-formed JSON array or object."""
    stripped = data.strip()
    if not stripped or not _has_json_enclosing_brackets(stripped):
        return False
    try:
        json.loads(stripped.decode("utf-8"))
        return True
    except (UnicodeDecodeError, json.JSONDecodeError):
        return False


def _is_safe_text_codepoint(cp: int) -> bool:
    """Verifies that an individual codepoint is printable or common whitespace."""
    if cp in (9, 10, 13):  # tab, newline, carriage return
        return True
    if cp < 32:  # non-printable control characters
        return False
    if cp == 127:  # DEL
        return False
    return True


def _decode_to_text(data: Union[bytes, str]) -> Optional[str]:
    """Decodes raw input to text string while rejecting null bytes."""
    if isinstance(data, bytes):
        if b"\x00" in data:
            return None
        try:
            return data.decode("utf-8")
        except UnicodeDecodeError:
            return None
    return None if "\x00" in data else data


def is_safe_text_content(data: Union[bytes, str]) -> bool:
    """
    Checks that text does not contain null bytes or illegal control characters.
    Validates UTF-8 encoding if raw bytes are provided.
    """
    text = _decode_to_text(data)
    if text is None:
        return False
    return all(_is_safe_text_codepoint(ord(ch)) for ch in text)


# Ordered registry of binary signatures
_BINARY_CHECKERS: List[Tuple[str, Callable[[bytes], bool]]] = [
    (MIME_PDF, _check_pdf_magic),
    (MIME_PNG, _check_png_magic),
    (MIME_JPEG, _check_jpeg_magic),
    (MIME_GIF, _check_gif_magic),
    (MIME_GZIP, _check_gzip_magic),
    (MIME_ZIP, _check_zip_magic),
    (MIME_TAR, _check_tar_magic),
    (MIME_XML, _check_xml_magic),
    (MIME_JSON, _check_json_magic),
]


def _find_matching_binary_mime(data: bytes) -> Optional[str]:
    """Scans registered binary checkers for a matching signature."""
    for mime_type, checker in _BINARY_CHECKERS:
        if checker(data):
            return mime_type
    return None


def detect_mime_type_from_bytes(data: bytes) -> Optional[str]:
    """
    Detects MIME type by inspecting leading magic bytes and content structure.
    Returns detected MIME type string or None if unrecognized binary.
    """
    if not data or not isinstance(data, bytes):
        return None

    binary_type = _find_matching_binary_mime(data)
    if binary_type is not None:
        return binary_type

    return MIME_TEXT if is_safe_text_content(data) else None


def _is_text_compatible(norm_expected: str, detected: str) -> bool:
    """Checks if detected MIME is compatible with generic text extensions."""
    if norm_expected in (MIME_TEXT, "text/markdown", "text/csv"):
        return detected in (MIME_TEXT, MIME_JSON, MIME_XML)
    return False


def _is_xml_compatible(norm_expected: str, detected: str) -> bool:
    """Checks if detected MIME is compatible with XML/RSS feeds."""
    if norm_expected in (MIME_XML, "application/rss+xml", "application/atom+xml"):
        return detected == MIME_XML
    return False


def _is_mime_match(norm_expected: str, detected: str) -> bool:
    """Checks direct match or compatible group matching."""
    if detected == norm_expected:
        return True
    if _is_text_compatible(norm_expected, detected):
        return True
    return _is_xml_compatible(norm_expected, detected)


def verify_magic_bytes(data: bytes, expected_mime: str) -> bool:
    """
    Verifies that the provided data strictly conforms to the expected MIME type signature.
    Prevents file extension / Content-Type spoofing attacks.
    """
    if not data or not expected_mime:
        return False

    detected = detect_mime_type_from_bytes(data)
    if detected is None:
        return False

    return _is_mime_match(expected_mime.strip().lower(), detected)
