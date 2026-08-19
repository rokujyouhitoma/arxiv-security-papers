#!/usr/bin/env python3
"""
Model Context Protocol (MCP) Server: Threat-to-Defense Patch & Rule Generator.
Exposes tools to synthesize Semgrep CI rules, generate academic-aligned secure code patches,
and evaluate MITRE ATT&CK / NIST SP 800 defense coverage.
"""

import json
import sys
from typing import Any, Dict

# ---------------------------------------------------------------------------
# Knowledge Base for Automated Defense Synthesis (Imported from security.taxonomy)
# ---------------------------------------------------------------------------
from security.taxonomy import CWE_DEFENSE_MAP

TOOLS_MANIFEST = [
    {
        "name": "generate_semgrep_rule",
        "description": (
            "Synthesize a ready-to-use Semgrep YAML rule from a CWE ID or vulnerability pattern "
            "for CI/CD DevSecOps pipelines."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "cwe_id": {
                    "type": "string",
                    "description": "Target CWE identifier e.g. 'CWE-94', 'CWE-502', 'CWE-89', 'CWE-22'",
                },
                "custom_pattern": {
                    "type": "string",
                    "description": "Optional custom code pattern e.g. 'pickle.load(...)'",
                },
                "rule_id": {
                    "type": "string",
                    "description": "Optional custom rule identifier",
                },
            },
            "required": ["cwe_id"],
        },
    },
    {
        "name": "synthesize_secure_patch",
        "description": (
            "Generate an academic-aligned secure code remediation patch and diff for a vulnerable code snippet."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "Vulnerable Python code snippet",
                },
                "cwe_id": {
                    "type": "string",
                    "description": "Target CWE identifier e.g. 'CWE-94', 'CWE-502', 'CWE-89'",
                },
            },
            "required": ["code", "cwe_id"],
        },
    },
    {
        "name": "check_threat_coverage",
        "description": (
            "Evaluate the repository defense coverage across MITRE ATT&CK tactics and NIST SP 800-53 controls."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "declared_defenses": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": (
                        "List of active defenses (e.g. ['pickle-free', 'ast-guard', "
                        "'parameterized-queries', 'commonpath-traversal-guard', 'zero-dependency'])"
                    ),
                },
            },
            "required": ["declared_defenses"],
        },
    },
]


def handle_generate_semgrep_rule(params: Dict[str, Any]) -> Dict[str, Any]:
    cwe_id = params.get("cwe_id", "").strip().upper()
    data = CWE_DEFENSE_MAP.get(cwe_id, {})
    rule_id = params.get("rule_id", f"arxiv-security-{cwe_id.lower().replace('-', '')}")
    pattern = params.get("custom_pattern") or data.get("semgrep_pattern", "eval($...X)")
    desc = data.get("description", f"Detects patterns related to {cwe_id}")

    remediation = data.get("secure_alternative", "Use safe APIs")
    msg = f"Detected potential {cwe_id} ({data.get('name', 'Vulnerability')}). Remediation: {remediation}."
    yaml_rule = f"""rules:
  - id: {rule_id}
    patterns:
      - pattern: {pattern}
    message: "{msg}"
    languages:
      - python
    severity: ERROR
    metadata:
      cwe: "{cwe_id}"
      description: "{desc}"
      source: "arxiv-security-papers (DSN-12)"
      mitre_technique: "{data.get('mitre_technique', 'T1059')}"
"""

    return {
        "status": "success",
        "cwe_id": cwe_id,
        "rule_id": rule_id,
        "semgrep_yaml": yaml_rule,
    }


def handle_synthesize_secure_patch(params: Dict[str, Any]) -> Dict[str, Any]:
    code = params.get("code", "")
    cwe_id = params.get("cwe_id", "").strip().upper()
    data = CWE_DEFENSE_MAP.get(cwe_id, {})

    remediation_notes = data.get(
        "patch_strategy", "Apply defensive validation and input sanitization"
    )
    patched_code = code

    # Basic automated heuristic replacements for common CWEs
    if cwe_id == "CWE-502" and "pickle." in code:
        patched_code = (
            code.replace("import pickle", "import json")
            .replace("pickle.loads(", "json.loads(")
            .replace("pickle.load(", "json.load(")
        )
    elif cwe_id == "CWE-94" and "eval(" in code:
        patched_code = "import ast\n" + code.replace("eval(", "ast.literal_eval(")
    elif cwe_id == "CWE-89" and 'f"' in code:
        patched_code = (
            "# TODO: Ensure parameterized tuples: cursor.execute(query, (params,))\n"
            + code
        )

    return {
        "status": "success",
        "cwe_id": cwe_id,
        "vulnerability_name": data.get("name", "Unknown Vulnerability"),
        "remediation_strategy": remediation_notes,
        "recommended_alternative": data.get("secure_alternative", "Safe API"),
        "original_code": code,
        "suggested_patch": patched_code,
    }


def handle_check_threat_coverage(params: Dict[str, Any]) -> Dict[str, Any]:
    defenses = [d.lower() for d in params.get("declared_defenses", [])]
    total_key_defenses = 5
    matched = 0
    breakdown = []

    checklist = [
        (
            "pickle-free",
            "CWE-502 (Deserialization / Model Poisoning)",
            "T1587.001",
            "SI-10 (Information Input Validation)",
        ),
        (
            "ast-guard",
            "CWE-94 (Dynamic Code Injection)",
            "T1059.006",
            "SI-3 (Malicious Code Protection)",
        ),
        (
            "zero-dependency",
            "Supply-Chain Malware & Slopsquatting",
            "T1195.001",
            "SR-3 (Supply Chain Controls)",
        ),
        (
            "commonpath-traversal-guard",
            "CWE-22 (Path Traversal)",
            "T1083",
            "AC-3 (Access Enforcement)",
        ),
        (
            "parameterized-queries",
            "CWE-89 (SQL Injection)",
            "T1190",
            "SI-10 (Information Input Validation)",
        ),
    ]

    for key, cwe_desc, mitre, nist in checklist:
        active = any(key in d for d in defenses)
        if active:
            matched += 1
        breakdown.append(
            {
                "defense_key": key,
                "protects_against": cwe_desc,
                "mitre_technique": mitre,
                "nist_control": nist,
                "status": "ENFORCED" if active else "MISSING",
            }
        )

    coverage_score = round(matched / total_key_defenses, 4)

    return {
        "status": "success",
        "coverage_score": coverage_score,
        "coverage_percentage": f"{int(coverage_score * 100)}%",
        "rating": (
            "A+ (Excellent)"
            if coverage_score >= 0.8
            else "B (Moderate)" if coverage_score >= 0.5 else "C (Needs Attention)"
        ),
        "breakdown": breakdown,
    }


def main() -> None:
    """MCP standard input/output transport loop."""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            method = req.get("method")
            req_id = req.get("id")

            if method == "tools/list":
                resp = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"tools": TOOLS_MANIFEST},
                }
            elif method == "tools/call":
                p = req.get("params", {})
                tool_name = p.get("name")
                args = p.get("arguments", {})

                if tool_name == "generate_semgrep_rule":
                    res = handle_generate_semgrep_rule(args)
                elif tool_name == "synthesize_secure_patch":
                    res = handle_synthesize_secure_patch(args)
                elif tool_name == "check_threat_coverage":
                    res = handle_check_threat_coverage(args)
                else:
                    res = {"error": f"Unknown tool '{tool_name}'"}

                resp = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": json.dumps(res, ensure_ascii=False, indent=2),
                            }
                        ]
                    },
                }
            else:
                resp = {"jsonrpc": "2.0", "id": req_id, "result": {}}

            sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
            sys.stdout.flush()
        except Exception as e:
            sys.stderr.write(f"Error handling MCP request: {e}\n")


if __name__ == "__main__":
    main()
