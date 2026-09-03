#!/usr/bin/env python3
"""
MCP Text and Payload Sanitizer.
Eliminates invisible Unicode characters, bidirectional override attacks,
ANSI escape sequences, and corrupting control codes from academic payloads.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any, Dict

ANSI_ESCAPE_RE = re.compile(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
BIDI_CHARS_RE = re.compile(r"[\u202A-\u202E\u2066-\u2069]")
ZERO_WIDTH_RE = re.compile(r"[\u200B-\u200D\u2060\uFEFF]")
CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]")


def sanitize_text(text: str) -> str:
    """
    Sanitizes string by applying NFKC normalization, removing ANSI escape codes,
    zero-width characters, bidirectional overrides, and dangerous control characters.
    """
    if not isinstance(text, str):
        return text

    # NFKC Normalization
    normalized = unicodedata.normalize("NFKC", text)

    # Strip ANSI escapes
    no_ansi = ANSI_ESCAPE_RE.sub("", normalized)

    # Strip Bidi and Zero-width characters
    no_bidi = BIDI_CHARS_RE.sub("", no_ansi)
    no_zw = ZERO_WIDTH_RE.sub("", no_bidi)

    # Strip non-printable control characters (preserves \t, \n, \r)
    clean = CONTROL_CHARS_RE.sub("", no_zw)
    return clean


def _sanitize_dict(d: Dict[Any, Any]) -> Dict[str, Any]:
    return {sanitize_text(str(k)): sanitize_payload(v) for k, v in d.items()}


def _sanitize_seq(seq: Any) -> Any:
    cleaned = [sanitize_payload(item) for item in seq]
    return tuple(cleaned) if isinstance(seq, tuple) else cleaned


def sanitize_payload(payload: Any) -> Any:
    """
    Recursively applies sanitize_text to all strings within a dictionary,
    list, or scalar payload.
    """
    if isinstance(payload, str):
        return sanitize_text(payload)
    if isinstance(payload, dict):
        return _sanitize_dict(payload)
    if isinstance(payload, (list, tuple)):
        return _sanitize_seq(payload)
    return payload
