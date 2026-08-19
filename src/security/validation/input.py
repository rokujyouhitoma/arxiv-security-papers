#!/usr/bin/env python3
"""
Input Sanitization & Vulnerability Pattern Detection Engine.
Detects common injection attempts (SQLi, XSS, Command Injection) and validates inputs.
"""

import html
import re
from typing import List, Tuple

DANGEROUS_COMMAND_PATTERNS: List[Tuple[str, str]] = [
    (
        r"(?i)\b(rm\s+-rf|chmod\s+777|wget\s+http|curl\s+http.*\|\s*sh)\b",
        "Dangerous Shell Command",
    ),
    (r"(?i)\b(nc\s+-e|/bin/sh|/bin/bash)\b", "Reverse Shell Pattern"),
    (
        r"(?i)\b(eval\(|exec\(|__import__\(|getattr\(.*system)\b",
        "Dynamic Code Execution",
    ),
]

SQLI_PATTERNS: List[Tuple[str, str]] = [
    (
        r"(?i)(\bUNION\b\s+\bSELECT\b|'\s+OR\s+'1'='1|--\s*$|/\*.*\*/)",
        "SQL Injection Pattern",
    ),
]

XSS_PATTERNS: List[Tuple[str, str]] = [
    (r"(?i)<script.*?>.*?</script.*?>", "Script Tag XSS"),
    (r"(?i)javascript:", "JavaScript URI Scheme"),
    (r"(?i)onload\s*=|onerror\s*=", "Inline Event Handler XSS"),
]


def sanitize_html(text: str) -> str:
    """Escapes HTML special characters to neutralize XSS vectors."""
    if not text or not isinstance(text, str):
        return ""
    return html.escape(text, quote=True)


def detect_dangerous_patterns(text: str) -> List[str]:
    """
    Scans input string against security patterns and returns a list of detected threats.
    """
    if not text or not isinstance(text, str):
        return []

    warnings: List[str] = []
    for pattern, label in DANGEROUS_COMMAND_PATTERNS:
        if re.search(pattern, text):
            warnings.append(f"COMMAND_INJECTION: {label}")

    for pattern, label in SQLI_PATTERNS:
        if re.search(pattern, text):
            warnings.append(f"SQLI: {label}")

    for pattern, label in XSS_PATTERNS:
        if re.search(pattern, text):
            warnings.append(f"XSS: {label}")

    return warnings
