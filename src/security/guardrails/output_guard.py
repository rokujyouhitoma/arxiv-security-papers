#!/usr/bin/env python3
"""
Agentic & LLM Output Guardrails Module.
Provides prompt injection heuristic detection, PII and secret data loss prevention (DLP),
and output length limit enforcement.
Zero external runtime dependencies.
"""

import re
from typing import List, Pattern, Tuple

# Prompt Injection heuristic detection patterns
PROMPT_INJECTION_RULES: List[Tuple[Pattern[str], str]] = [
    (
        re.compile(
            r"\b(ignore\s+(all\s+)?previous\s+instructions|disregard\s+(all\s+)?prior\s+prompts)\b",
            re.IGNORECASE,
        ),
        "Instruction Override Attack",
    ),
    (
        re.compile(
            r"\b(system\s+prompt\s*:\s*you\s+are|you\s+are\s+now\s+in\s+dan\s+mode|simulate\s+unfiltered)\b",
            re.IGNORECASE,
        ),
        "Persona / Jailbreak Hijacking",
    ),
    (
        re.compile(
            r"\b(reveal\s+(your\s+)?(system\s+prompt|api\s+key|environment\s+variables|master\s+key))\b",
            re.IGNORECASE,
        ),
        "Secret Exfiltration Probe",
    ),
    (
        re.compile(
            r"(<\s*/?\s*system\s*>|<\s*/?\s*instruction\s*>|\[\s*/?\s*INST\s*\])",
            re.IGNORECASE,
        ),
        "Delimiter Injection Vector",
    ),
]

# DLP Patterns for PII and Secret masking
DLP_RULES: List[Tuple[Pattern[str], str]] = [
    (
        re.compile(
            r"-----BEGIN (?:[A-Z0-9_-]+ )?PRIVATE KEY-----[\s\S]*?-----END (?:[A-Z0-9_-]+ )?PRIVATE KEY-----"
        ),
        "[PRIVATE_KEY_MASKED]",
    ),
    (
        re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
        "[AWS_KEY_MASKED]",
    ),
    (
        re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{36,255}\b"),
        "[GITHUB_TOKEN_MASKED]",
    ),
    (
        re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,7}\b"),
        "[EMAIL_MASKED]",
    ),
    (
        re.compile(r"\b(?:\d{4}[-\s]?){3}\d{4}\b"),
        "[CARD_MASKED]",
    ),
    (
        re.compile(
            r"\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{2,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{4}\b"
        ),
        "[PHONE_MASKED]",
    ),
]

DEFAULT_MAX_OUTPUT_CHARS = 50000


def detect_prompt_injection(text: str) -> List[str]:
    """Scans text for known prompt injection, jailbreak, or delimiter escape attempts."""
    if not text or not isinstance(text, str):
        return []
    findings: List[str] = []
    for pattern, rule_name in PROMPT_INJECTION_RULES:
        if pattern.search(text):
            findings.append(rule_name)
    return findings


def mask_pii_and_secrets(text: str) -> str:
    """Applies Data Loss Prevention (DLP) masks over sensitive tokens and PII."""
    if not text or not isinstance(text, str):
        return ""
    masked = text
    for pattern, replacement in DLP_RULES:
        masked = pattern.sub(replacement, masked)
    return masked


def _check_length_limit(text: str, max_chars: int, violations: List[str]) -> None:
    """Appends violation if text exceeds character budget."""
    if len(text) > max_chars:
        violations.append(
            f"Output exceeds maximum character limit ({len(text)} > {max_chars})"
        )


def validate_output_safety(
    text: str,
    max_chars: int = DEFAULT_MAX_OUTPUT_CHARS,
) -> Tuple[bool, List[str], str]:
    """
    Validates safety of LLM / agent output.
    Enforces maximum length budget, checks for prompt injection markers, and masks PII/secrets.
    Returns:
        (is_safe, violations, sanitized_text)
    """
    if not text or not isinstance(text, str):
        return True, [], ""

    violations: List[str] = []
    _check_length_limit(text, max_chars, violations)

    injections = detect_prompt_injection(text)
    violations.extend(injections)

    sanitized = mask_pii_and_secrets(text)
    is_safe = len(violations) == 0
    return is_safe, violations, sanitized
