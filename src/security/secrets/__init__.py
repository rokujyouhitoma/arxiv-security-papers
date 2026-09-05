#!/usr/bin/env python3
"""
Secrets & Token Management Guard Package.
Provides ephemeral in-memory storage with memory zeroization,
secret masking, leak detection, and constant-time cryptographic utilities.
Zero external runtime dependencies.
"""

from .crypto_util import (
    constant_time_compare,
    generate_csrf_token,
    generate_secure_token,
    verify_csrf_token,
)
from .manager import (
    EphemeralSecretStore,
    SecretFinding,
    detect_exposed_secrets,
    mask_secret,
)

__all__ = [
    "EphemeralSecretStore",
    "SecretFinding",
    "constant_time_compare",
    "detect_exposed_secrets",
    "generate_csrf_token",
    "generate_secure_token",
    "mask_secret",
    "verify_csrf_token",
]
