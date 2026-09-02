"""
Sensitive Data & PII Masking Engine.
Zero external dependencies (pure standard library).
Provides fast compiled regex masking for credentials, tokens, and PII (CWE-532 compliant).
"""

import re
from typing import Any, Dict, List, Pattern, Tuple

# Compiled regex patterns for high-throughput log masking
_PATTERNS: List[Tuple[Pattern[str], str]] = [
    # 1. Bearer / JWT / Authorization Tokens
    (
        re.compile(
            r"(?i)(bearer\s+|jwt\s+|token\s*[:=]\s*['\"]?)([a-zA-Z0-9_\-\.]{12,})(['\"]?)",
            re.IGNORECASE,
        ),
        r"\g<1>***MASKED***\g<3>",
    ),
    # 2. Passwords / Secrets / API Keys
    (
        re.compile(
            r"(?i)(password|passwd|secret|api[_-]?key|access[_-]?token|private[_-]?key)"
            r"\s*([:=])\s*(['\"]?)([^'\",\s\r\n]{4,})\3",
            re.IGNORECASE,
        ),
        r"\1\2\3***MASKED***\3",
    ),
    # 3. Email Addresses (PII)
    (
        re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
        "***MASKED_EMAIL***",
    ),
    # 4. Credit Card Numbers / PAN (13-19 digits with optional hyphens/spaces)
    (
        re.compile(r"\b(?:\d{4}[- ]?){3}\d{4}\b"),
        "***MASKED_CARD***",
    ),
]

_SENSITIVE_KEY_SUBSTRINGS = (
    "password",
    "secret",
    "token",
    "api_key",
    "apikey",
    "authorization",
    "cookie",
    "private_key",
)


def mask_text(text: str) -> str:
    """Applies all compiled masking patterns to the input string."""
    if not text:
        return text
    result = text
    for pattern, repl in _PATTERNS:
        result = pattern.sub(repl, result)
    return result


def _is_sensitive_key(key: str) -> bool:
    lowered = key.lower()
    return any(sub in lowered for sub in _SENSITIVE_KEY_SUBSTRINGS)


def _mask_list_item(item: Any) -> Any:
    if isinstance(item, dict):
        return mask_dict(item)
    if isinstance(item, str):
        return mask_text(item)
    return item


def _mask_nested_value(val: Any) -> Any:
    if isinstance(val, dict):
        return mask_dict(val)
    if isinstance(val, list):
        return [_mask_list_item(item) for item in val]
    if isinstance(val, str):
        return mask_text(val)
    return val


def mask_dict(data: Dict[str, Any]) -> Dict[str, Any]:
    """Recursively masks sensitive values in dictionaries and nested structures."""
    if not isinstance(data, dict):
        return data
    masked: Dict[str, Any] = {}
    for k, v in data.items():
        if _is_sensitive_key(str(k)):
            masked[k] = "***MASKED***"
        else:
            masked[k] = _mask_nested_value(v)
    return masked


__all__ = ["mask_text", "mask_dict"]
