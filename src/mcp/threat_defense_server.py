from typing import Any, Callable, Dict

from mcp.base import run_mcp_server
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
    {
        "name": "generate_caldera_playbook",
        "description": (
            "Generate an automated adversary emulation ability / playbook (YAML) in Caldera format "
            "from a MITRE ATT&CK technique ID (DSN-16 / DSN-08)."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "tech_id": {
                    "type": "string",
                    "description": "Target MITRE ATT&CK technique ID e.g. 'T1059', 'T1190', 'T1566'",
                },
                "platform": {
                    "type": "string",
                    "description": "Target OS platform e.g. 'linux', 'darwin', 'windows' (default: 'linux')",
                },
            },
            "required": ["tech_id"],
        },
    },
    {
        "name": "generate_sigma_rule",
        "description": (
            "Generate a SIEM threat detection rule draft in Sigma YAML format "
            "from a MITRE ATT&CK technique ID (DSN-16)."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "tech_id": {
                    "type": "string",
                    "description": "Target MITRE ATT&CK technique ID e.g. 'T1059', 'T1190', 'T1574'",
                },
                "title": {
                    "type": "string",
                    "description": "Optional custom detection rule title",
                },
            },
            "required": ["tech_id"],
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


def _patch_pickle(code: str) -> str:
    return (
        code.replace("import pickle", "import json")
        .replace("pickle.loads(", "json.loads(")
        .replace("pickle.load(", "json.load(")
    )


def _patch_safetensors(code: str) -> str:
    return "from safetensors.torch import load_file\n" + code.replace(
        "torch.load(", "load_file("
    ).replace("import pickle", "# pickle removed for safety")


def _apply_cwe_patch_heuristics(cwe_id: str, code: str) -> str:
    """Applies heuristic code transformations based on target CWE vulnerability."""
    if cwe_id == "CWE-502":
        return _patch_pickle(code) if "pickle." in code else code
    if cwe_id == "CWE-693":
        return _patch_safetensors(code)
    if cwe_id == "CWE-1357":
        return (
            "# Enforce verified package imports and pin dependencies with hashes\n"
            + code
        )
    if cwe_id == "CWE-94":
        if "eval(" in code:
            return "import ast\n" + code.replace("eval(", "ast.literal_eval(")
        return code
    if cwe_id == "CWE-89":
        if 'f"' in code:
            return (
                "# TODO: Ensure parameterized tuples: cursor.execute(query, (params,))\n"
                + code
            )
        return code
    return code


def handle_synthesize_secure_patch(params: Dict[str, Any]) -> Dict[str, Any]:
    code = params.get("code", "")
    cwe_id = params.get("cwe_id", "").strip().upper()
    data = CWE_DEFENSE_MAP.get(cwe_id, {})

    remediation_notes = data.get(
        "patch_strategy", "Apply defensive validation and input sanitization"
    )
    patched_code = _apply_cwe_patch_heuristics(cwe_id, code)

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


def handle_generate_caldera_playbook(params: Dict[str, Any]) -> Dict[str, Any]:
    """Generates automated Caldera ability YAML for MITRE ATT&CK technique."""
    tech_id = params.get("tech_id", "").strip().upper()
    platform = params.get("platform", "linux").strip().lower()
    if not tech_id:
        return {"status": "error", "message": "Missing required parameter 'tech_id'"}

    from security.taxonomy import generate_caldera_ability

    yaml_ability = generate_caldera_ability(tech_id=tech_id, platform=platform)
    return {
        "status": "success",
        "tech_id": tech_id,
        "platform": platform,
        "caldera_ability_yaml": yaml_ability,
    }


def handle_generate_sigma_rule(params: Dict[str, Any]) -> Dict[str, Any]:
    """Generates SIEM Sigma detection rule draft for MITRE ATT&CK technique."""
    tech_id = params.get("tech_id", "").strip().upper()
    title = params.get("title")
    if not tech_id:
        return {"status": "error", "message": "Missing required parameter 'tech_id'"}

    from security.taxonomy import generate_sigma_rule

    sigma_yaml = generate_sigma_rule(tech_id=tech_id, title=title)
    return {
        "status": "success",
        "tech_id": tech_id,
        "sigma_rule_yaml": sigma_yaml,
    }


TOOL_HANDLERS: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]] = {
    "generate_semgrep_rule": handle_generate_semgrep_rule,
    "synthesize_secure_patch": handle_synthesize_secure_patch,
    "check_threat_coverage": handle_check_threat_coverage,
    "generate_caldera_playbook": handle_generate_caldera_playbook,
    "generate_sigma_rule": handle_generate_sigma_rule,
}


def main() -> None:
    """MCP standard input/output transport loop."""
    run_mcp_server(
        server_name="arxiv-security-threat-defense",
        tools_manifest=TOOLS_MANIFEST,
        tool_handlers=TOOL_HANDLERS,
    )


if __name__ == "__main__":
    main()
