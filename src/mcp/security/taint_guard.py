#!/usr/bin/env python3
"""
MCP Taint Guard and Prompt Injection Neutralizer.
Inspects payloads originating from raw academic papers, detects adversarial prompt injections,
neutralizes execution delimiters, and enforces safe boundary encapsulation.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Tuple, cast

INJECTION_PATTERNS: List[Tuple[str, re.Pattern[str]]] = [
    (
        "instruction_override",
        re.compile(
            r"(?i)\b(ignore|disregard|forget)\s+(all\s+)?(previous|prior|above)\s+(instructions|directives|prompts)\b"
        ),
    ),
    (
        "system_token_spoofing",
        re.compile(
            r"(?i)(<\|im_start\|>|<\|im_end\|>|###\s*(system|human|assistant|instruction)|<<SYS>>|\[INST\])"
        ),
    ),
    (
        "dan_jailbreak",
        re.compile(
            r"(?i)\b(you\s+are\s+now\s+(in\s+)?DAN|do\s+anything\s+now|jailbreak\s+mode|developer\s+mode\s+enabled)\b"
        ),
    ),
    (
        "confused_deputy_exfiltration",
        re.compile(
            r"(?i)\b(send|post|exfiltrate)\s+(all\s+)?(files|keys|passwords|env|tokens)\s+to\b"
        ),
    ),
]


class TaintGuard:
    """
    Analyzes, tracks, and neutralizes prompt injections and taint in MCP communications.
    """

    @classmethod
    def _find_matches(cls, text: str) -> List[str]:
        """Scans text and returns list of matched injection rule names."""
        matches: List[str] = []
        for name, pattern in INJECTION_PATTERNS:
            if pattern.search(text):
                matches.append(name)
        return matches

    @classmethod
    def _neutralize_matches(cls, text: str) -> str:
        """Neutralizes matched injection patterns in text."""
        guarded = text
        for _, pattern in INJECTION_PATTERNS:
            guarded = pattern.sub(
                lambda m: f"[NEUTRALIZED:{m.group(0).replace('<', '{').replace('>', '}')}]",
                guarded,
            )
        return guarded

    @classmethod
    def inspect_text(cls, text: str) -> Tuple[str, bool, List[str]]:
        """
        Scans text for adversarial prompt injection patterns.
        If detected, neutralizes delimiter markers and wraps in safe boundary tags.
        Returns: (guarded_text, is_tainted, matched_rules)
        """
        if not isinstance(text, str):
            return text, False, []

        matched_rules = cls._find_matches(text)
        if not matched_rules:
            return text, False, []

        guarded = cls._neutralize_matches(text)
        rule_tag = ",".join(matched_rules)
        encapsulated = (
            f'<academic_untrusted_data taint_rules="{rule_tag}">\n'
            f"{guarded}\n"
            f"</academic_untrusted_data>"
        )
        return encapsulated, True, matched_rules

    @classmethod
    def guard_payload(cls, payload: Dict[str, Any]) -> Dict[str, Any]:
        """
        Recursively inspects a dictionary payload.
        If any field is tainted, sets `_meta.taint_status = 'neutralized'` and records triggers.
        """
        tainted_fields: List[str] = []
        all_rules: List[str] = []

        def _traverse(val: Any, path: str) -> Any:
            if isinstance(val, str):
                guarded, is_tainted, rules = cls.inspect_text(val)
                if is_tainted:
                    tainted_fields.append(path)
                    all_rules.extend(rules)
                return guarded
            elif isinstance(val, dict):
                return {
                    k: _traverse(v, f"{path}.{k}" if path else k)
                    for k, v in val.items()
                }
            elif isinstance(val, list):
                return [_traverse(item, f"{path}[{i}]") for i, item in enumerate(val)]
            return val

        result = _traverse(payload, "")
        if tainted_fields:
            if "_meta" not in result or not isinstance(result["_meta"], dict):
                result["_meta"] = {}
            result["_meta"]["taint_detected"] = True
            result["_meta"]["taint_status"] = "neutralized"
            result["_meta"]["tainted_fields"] = tainted_fields
            result["_meta"]["taint_rules"] = sorted(list(set(all_rules)))
        return cast(Dict[str, Any], result)
