#!/usr/bin/env python3
"""
Secrets & Token Management Guard Module.
Provides in-memory ephemeral secret storage with zeroization, secret masking for logs/UI,
and heuristic/entropy-based secret leak detection.
Zero external runtime dependencies (Python standard library only).
"""

import atexit
import math
import re
from collections import Counter
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple, Union


@dataclass(frozen=True)
class SecretFinding:
    """Represents an identified exposed secret in inspected text."""

    pattern_name: str
    preview: str
    start: int
    end: int


# Well-known secret regex patterns
_KNOWN_SECRET_PATTERNS: List[Tuple[str, re.Pattern[str]]] = [
    ("AWS_ACCESS_KEY", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    (
        "GITHUB_TOKEN",
        re.compile(r"\b(?:ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{82})\b"),
    ),
    ("OPENAI_API_KEY", re.compile(r"\bsk-[a-zA-Z0-9]{32,}\b")),
    (
        "PRIVATE_KEY_BLOCK",
        re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    ),
]


def mask_secret(
    secret_value: str,
    reveal_len: int = 4,
    mask_char: str = "*",
) -> str:
    """
    Masks a sensitive string preserving only the trailing characters.
    Example: 'sk-1234567890abcdef' -> '************cdef'.
    """
    if not secret_value:
        return ""
    length = len(secret_value)
    if length <= reveal_len:
        return mask_char * length
    hidden_len = length - reveal_len
    return (mask_char * hidden_len) + secret_value[-reveal_len:]


def _calculate_shannon_entropy(data: str) -> float:
    """Computes Shannon entropy in bits per character."""
    if not data:
        return 0.0
    length = len(data)
    counts = Counter(data)
    entropy = 0.0
    for count in counts.values():
        prob = count / length
        entropy -= prob * math.log2(prob)
    return entropy


def _is_high_entropy_candidate(
    token: str,
    min_len: int = 24,
    min_entropy: float = 4.5,
) -> bool:
    """Evaluates whether a candidate token exhibits high randomness indicative of keys."""
    if len(token) < min_len:
        return False
    if " " in token or "\n" in token or "\t" in token:
        return False
    return _calculate_shannon_entropy(token) >= min_entropy


def _scan_regex_matches(text: str) -> List[SecretFinding]:
    """Scans text against registered known credential regexes."""
    findings: List[SecretFinding] = []
    for pattern_name, regex in _KNOWN_SECRET_PATTERNS:
        for match in regex.finditer(text):
            matched_str = match.group(0)
            findings.append(
                SecretFinding(
                    pattern_name=pattern_name,
                    preview=mask_secret(matched_str),
                    start=match.start(),
                    end=match.end(),
                )
            )
    return findings


def _scan_entropy_tokens(
    text: str,
    min_len: int = 24,
    min_entropy: float = 4.5,
) -> List[SecretFinding]:
    """Scans whitespace/delimiter-separated tokens for high-entropy secrets."""
    findings: List[SecretFinding] = []
    token_pattern = re.compile(r"[a-zA-Z0-9_/+=-]{24,}")
    for match in token_pattern.finditer(text):
        token = match.group(0)
        if _is_high_entropy_candidate(token, min_len=min_len, min_entropy=min_entropy):
            findings.append(
                SecretFinding(
                    pattern_name="HIGH_ENTROPY_SECRET",
                    preview=mask_secret(token),
                    start=match.start(),
                    end=match.end(),
                )
            )
    return findings


def _merge_entropy_findings(
    base_findings: List[SecretFinding],
    text: str,
    min_entropy: float,
) -> List[SecretFinding]:
    """Appends high entropy tokens if not already covered by regex matches."""
    entropy_findings = _scan_entropy_tokens(text, min_entropy=min_entropy)
    existing_ranges = {(f.start, f.end) for f in base_findings}
    merged = list(base_findings)
    for ef in entropy_findings:
        if (ef.start, ef.end) not in existing_ranges:
            merged.append(ef)
    return merged


def detect_exposed_secrets(
    text: str,
    check_entropy: bool = True,
    min_entropy: float = 4.5,
) -> List[SecretFinding]:
    """
    Analyzes text to detect exposed credentials, tokens, and private keys.
    Returns a deduplicated list of findings.
    """
    if not text:
        return []

    findings = _scan_regex_matches(text)
    if check_entropy:
        return _merge_entropy_findings(findings, text, min_entropy)

    return findings


class EphemeralSecretStore:
    """
    In-memory zeroizing secret repository.
    Stores sensitive data as bytearrays and securely wipes buffers with zeroes
    upon explicit zeroize() or process termination (atexit).
    """

    def __init__(self) -> None:
        self._store: Dict[str, bytearray] = {}
        atexit.register(self.zeroize)

    def set_secret(self, key: str, value: Union[str, bytes]) -> None:
        """Stores a secret in a newly allocated mutable bytearray."""
        if not key:
            raise ValueError("Secret key cannot be empty")
        raw = value.encode("utf-8") if isinstance(value, str) else value
        # Wipe old buffer if overwriting
        self.delete_secret(key)
        self._store[key] = bytearray(raw)

    def get_secret(self, key: str) -> Optional[str]:
        """Retrieves decoded secret string if present."""
        raw = self.get_secret_bytes(key)
        if raw is None:
            return None
        return raw.decode("utf-8", errors="replace")

    def get_secret_bytes(self, key: str) -> Optional[bytes]:
        """Retrieves raw secret bytes copy if present."""
        buf = self._store.get(key)
        if buf is None:
            return None
        return bytes(buf)

    def delete_secret(self, key: str) -> bool:
        """Wipes bytearray memory with 0x00 and deletes key."""
        buf = self._store.pop(key, None)
        if buf is not None:
            for i in range(len(buf)):
                buf[i] = 0
            return True
        return False

    def zeroize(self) -> None:
        """Wipes all bytearrays in memory with zeroes and clears dictionary."""
        for buf in self._store.values():
            for i in range(len(buf)):
                buf[i] = 0
        self._store.clear()

    def __len__(self) -> int:
        return len(self._store)
