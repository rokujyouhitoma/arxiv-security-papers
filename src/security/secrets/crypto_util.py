#!/usr/bin/env python3
"""
Cryptographic Utilities & Constant-Time Operations Module.
Provides timing-attack-resistant comparisons and cryptographically secure token generation.
Zero external runtime dependencies (Python standard library only).
"""

import hmac
import secrets
from typing import Union


def constant_time_compare(
    val_a: Union[str, bytes],
    val_b: Union[str, bytes],
) -> bool:
    """
    Compares two strings or byte sequences in constant time to prevent timing side-channel attacks.
    Uses hmac.compare_digest under the hood.
    """
    bytes_a = val_a.encode("utf-8") if isinstance(val_a, str) else val_a
    bytes_b = val_b.encode("utf-8") if isinstance(val_b, str) else val_b
    return hmac.compare_digest(bytes_a, bytes_b)


def generate_secure_token(nbytes: int = 32, url_safe: bool = True) -> str:
    """
    Generates a cryptographically strong pseudo-random token.
    Uses secrets.token_urlsafe or secrets.token_hex.
    """
    if nbytes <= 0:
        raise ValueError("Token length must be positive")
    if url_safe:
        return secrets.token_urlsafe(nbytes)
    return secrets.token_hex(nbytes)


def generate_csrf_token() -> str:
    """Generates an URL-safe CSRF token with 256 bits of entropy."""
    return generate_secure_token(32, url_safe=True)


def verify_csrf_token(received_token: str, expected_token: str) -> bool:
    """
    Verifies a received CSRF token against the expected token in constant time.
    Rejects empty or non-string inputs.
    """
    if not received_token or not expected_token:
        return False
    return constant_time_compare(received_token, expected_token)
