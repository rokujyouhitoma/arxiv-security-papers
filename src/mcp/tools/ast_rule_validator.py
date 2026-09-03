#!/usr/bin/env python3
"""
In-Memory AST Syntax Validator and ReDoS Static Analyzer (Issue 131, DSN-08).
Validates generated detection signatures using Python standard library `ast` without code execution,
and scans regular expressions for catastrophic backtracking (ReDoS) vulnerabilities.
"""

import ast
import re
from typing import NamedTuple, Optional


class ValidationResult(NamedTuple):
    is_valid: bool
    error_message: str = ""
    ast_checked: bool = False
    redos_free: bool = True


# Patterns indicative of exponential catastrophic backtracking (ReDoS)
REDOS_VULNERABLE_PATTERNS = [
    re.compile(r"\([^)]*[+*]\)[+*]"),  # Nested repetition e.g. (a+)+ or (.*)*
    re.compile(r"\([^)]*\\w[+*]\)[+*]"),  # (\w+)+
    re.compile(r"\([^)]*\\d[+*]\)[+*]"),  # (\d+)+
    re.compile(r"\([^|()]+(\|[^|()]+)+\)[+*]"),  # (a|aa)+ overlapping alternation
]


def _is_yaml_key_line(line: str) -> bool:
    stripped = line.strip()
    return bool(stripped and not stripped.startswith("#") and ":" in stripped)


def _extract_yaml_keys(lines: list[str]) -> set[str]:
    found = set()
    for line in lines:
        if _is_yaml_key_line(line):
            k = line.strip().split(":", 1)[0].lstrip("- ").strip()
            found.add(k)
    return found


def _check_missing_yaml_keys(
    found_keys: set[str], required_keys: Optional[list[str]]
) -> Optional[str]:
    if not required_keys:
        return None
    for req in required_keys:
        if req not in found_keys:
            return f"Missing mandatory YAML key '{req}' in signature"
    return None


class ASTRuleValidator:
    """Performs static syntax and ReDoS security checks on detection signatures."""

    @staticmethod
    def validate_python_code(code_snippet: str) -> ValidationResult:
        """Validates Python code syntax via standard library `ast.parse`."""
        if not code_snippet.strip():
            return ValidationResult(
                is_valid=False, error_message="Empty code snippet", ast_checked=False
            )

        try:
            ast.parse(code_snippet)
            return ValidationResult(is_valid=True, ast_checked=True, redos_free=True)
        except SyntaxError as e:
            return ValidationResult(
                is_valid=False,
                error_message=f"Python SyntaxError: {e.msg} at line {e.lineno}",
                ast_checked=True,
            )

    @staticmethod
    def check_redos_vulnerability(regex_str: str) -> ValidationResult:
        """
        Statically inspects regular expression string for nested quantifiers
        and catastrophic backtracking hazards.
        """
        # First verify regex compiles
        try:
            re.compile(regex_str)
        except re.error as e:
            return ValidationResult(
                is_valid=False,
                error_message=f"Invalid regular expression syntax: {e}",
                redos_free=False,
            )

        for pat in REDOS_VULNERABLE_PATTERNS:
            if pat.search(regex_str):
                return ValidationResult(
                    is_valid=False,
                    error_message=f"Catastrophic backtracking (ReDoS) detected in pattern: {regex_str}",
                    redos_free=False,
                )

        return ValidationResult(is_valid=True, redos_free=True)

    @staticmethod
    def validate_yaml_structure(
        yaml_content: str, required_keys: Optional[list[str]] = None
    ) -> ValidationResult:
        """Lightweight YAML structure sanity verification."""
        if not yaml_content.strip():
            return ValidationResult(is_valid=False, error_message="Empty YAML content")

        found_keys = _extract_yaml_keys(yaml_content.splitlines())
        err = _check_missing_yaml_keys(found_keys, required_keys)
        if err:
            return ValidationResult(is_valid=False, error_message=err)

        return ValidationResult(is_valid=True)
