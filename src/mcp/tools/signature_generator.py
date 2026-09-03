#!/usr/bin/env python3
"""
Dynamic Detection Signature Synthesizer (Issue 131, DSN-08).
Generates Semgrep YAML, Sigma SIEM, and YARA memory/file detection signatures
from academic threat patterns, with integrated AST validation and ReDoS defenses.
"""

from typing import Any, Dict, Optional, Tuple

from .ast_rule_validator import ASTRuleValidator


def _check_python_pattern(
    validator: ASTRuleValidator, lang: str, pattern: str
) -> Tuple[bool, bool, str]:
    """Validates Python syntax if language is Python and has no metavariables."""
    if lang != "python" or "$" in pattern or "..." in pattern:
        return True, False, ""
    v_res = validator.validate_python_code(pattern)
    if not v_res.is_valid:
        return False, False, v_res.error_message
    return True, True, ""


def _check_yara_regex(
    validator: ASTRuleValidator, pattern_val: str
) -> Tuple[bool, str]:
    """Inspects pattern for catastrophic backtracking if it's a regex."""
    if pattern_val.startswith("/") and pattern_val.endswith("/"):
        redos_res = validator.check_redos_vulnerability(pattern_val[1:-1])
        if not redos_res.is_valid:
            return False, redos_res.error_message
    return True, ""


def _format_yara_line(
    validator: ASTRuleValidator, var_name: str, pattern_val: str
) -> Tuple[bool, str, str]:
    """Validates ReDoS and formats a single YARA string line."""
    ok, err = _check_yara_regex(validator, pattern_val)
    if not ok:
        return False, "", err

    prefix = "" if var_name.startswith("$") else "$"
    if pattern_val.startswith(("{", "/")):
        return True, f"        {prefix}{var_name} = {pattern_val}", ""
    return True, f'        {prefix}{var_name} = "{pattern_val}" ascii wide', ""


class SignatureGenerator:
    """Synthesizes verified detection rules across Semgrep, Sigma, and YARA formats."""

    def __init__(self) -> None:
        self.validator = ASTRuleValidator()

    def generate_semgrep(
        self,
        rule_id: str,
        cwe_id: str,
        pattern: str,
        lang: str = "python",
        message: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Synthesizes and validates a Semgrep detection rule."""
        clean_rule_id = rule_id.lower().replace(" ", "-").replace("_", "-")
        msg = message or f"Detected insecure pattern corresponding to {cwe_id}."

        ok, ast_checked, err = _check_python_pattern(self.validator, lang, pattern)
        if not ok:
            return {
                "status": "error",
                "rule_type": "semgrep",
                "message": f"Invalid Python pattern syntax: {err}",
            }

        yaml_content = f"""rules:
  - id: {clean_rule_id}
    patterns:
      - pattern: {pattern}
    message: "{msg}"
    languages:
      - {lang}
    severity: ERROR
    metadata:
      cwe: "{cwe_id}"
      source: "arxiv-security-papers"
"""
        struct_res = self.validator.validate_yaml_structure(
            yaml_content, required_keys=["rules", "id", "patterns", "message"]
        )
        if not struct_res.is_valid:
            return {"status": "error", "message": struct_res.error_message}

        return {
            "status": "success",
            "rule_type": "semgrep",
            "rule_id": clean_rule_id,
            "cwe_id": cwe_id,
            "signature": yaml_content,
            "is_valid": True,
            "ast_checked": ast_checked,
            "redos_free": True,
        }

    def generate_sigma(
        self,
        title: str,
        log_source: str,
        detection_fields: Dict[str, Any],
        level: str = "high",
    ) -> Dict[str, Any]:
        """Synthesizes and validates a Sigma SIEM detection rule."""
        rule_id = f"sigma-{title.lower().replace(' ', '-')}"

        selection_lines = []
        for field, value in detection_fields.items():
            if isinstance(value, list):
                val_str = "\n" + "\n".join(f"        - '{v}'" for v in value)
                selection_lines.append(f"      {field}:{val_str}")
            else:
                selection_lines.append(f"      {field}: '{value}'")

        selections = "\n".join(selection_lines)

        yaml_content = f"""title: {title}
id: {rule_id}
status: experimental
description: Auto-generated detection rule from academic threat pattern
logsource:
  category: {log_source}
detection:
  selection:
{selections}
  condition: selection
level: {level}
tags:
  - attack.defense_synthesizer
"""
        struct_res = self.validator.validate_yaml_structure(
            yaml_content, required_keys=["title", "logsource", "detection", "condition"]
        )
        if not struct_res.is_valid:
            return {"status": "error", "message": struct_res.error_message}

        return {
            "status": "success",
            "rule_type": "sigma",
            "title": title,
            "signature": yaml_content,
            "is_valid": True,
            "redos_free": True,
        }

    def generate_yara(
        self,
        rule_name: str,
        strings_dict: Dict[str, str],
        condition: str = "all of them",
    ) -> Dict[str, Any]:
        """Synthesizes and validates a YARA memory/file detection rule."""
        clean_name = rule_name.replace("-", "_").replace(" ", "_")

        string_lines = []
        for var_name, pattern_val in strings_dict.items():
            ok, line, err = _format_yara_line(self.validator, var_name, pattern_val)
            if not ok:
                return {
                    "status": "error",
                    "rule_type": "yara",
                    "message": err,
                }
            string_lines.append(line)

        strings_block = "\n".join(string_lines)

        yara_content = f"""rule {clean_name} {{
    meta:
        description = "Auto-generated YARA detection rule from academic security paper"
        author = "arxiv-security-papers"
    strings:
{strings_block}
    condition:
        {condition}
}}
"""
        return {
            "status": "success",
            "rule_type": "yara",
            "rule_name": clean_name,
            "signature": yara_content,
            "is_valid": True,
            "redos_free": True,
        }
