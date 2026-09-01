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

PROMPT_INJECTION_PATTERNS: List[Tuple[str, str]] = [
    (
        r"(?i)\b(ignore\s+(all\s+)?previous\s+instructions|disregard\s+(all\s+)?prior\s+prompts)\b",
        "Instruction Override Attack",
    ),
    (
        r"(?i)\b(system\s+prompt\s*:\s*you\s+are|you\s+are\s+now\s+in\s+dan\s+mode)\b",
        "Persona / Jailbreak Hijacking",
    ),
    (
        r"(?i)\b(reveal\s+(your\s+)?(system\s+prompt|api\s+key|environment\s+variables))\b",
        "Secret Exfiltration Probe",
    ),
]


def sanitize_html(text: str) -> str:
    """Escapes HTML special characters to neutralize XSS vectors."""
    if not text or not isinstance(text, str):
        return ""
    return html.escape(text, quote=True)


def wrap_untrusted_paper_content(text: str) -> str:
    """
    Capsules untrusted academic paper text inside isolated XML boundary tags
    to prevent indirect prompt injection into LLM orchestration layers (DSN-16 / DSN-07).
    """
    if not text or not isinstance(text, str):
        return "<untrusted_paper_content>\n</untrusted_paper_content>"
    # Sanitize closing boundary tag within text to prevent tag escape
    sanitized = text.replace("</untrusted_paper_content>", "[ESCAPED_CLOSING_TAG]")
    return f"<untrusted_paper_content>\n{sanitized}\n</untrusted_paper_content>"


ALL_SECURITY_PATTERN_GROUPS: List[Tuple[str, List[Tuple[str, str]]]] = [
    ("COMMAND_INJECTION", DANGEROUS_COMMAND_PATTERNS),
    ("SQLI", SQLI_PATTERNS),
    ("XSS", XSS_PATTERNS),
    ("PROMPT_INJECTION", PROMPT_INJECTION_PATTERNS),
]


def _check_pattern_group(
    prefix: str, group: List[Tuple[str, str]], text: str, warnings: List[str]
) -> None:
    """Appends matching patterns from a group to warnings list."""
    for pattern, label in group:
        if re.search(pattern, text):
            warnings.append(f"{prefix}: {label}")


def detect_dangerous_patterns(text: str) -> List[str]:
    """
    Scans input string against security patterns and returns a list of detected threats.
    """
    if not text or not isinstance(text, str):
        return []

    warnings: List[str] = []
    for prefix, group in ALL_SECURITY_PATTERN_GROUPS:
        _check_pattern_group(prefix, group, text, warnings)
    return warnings
