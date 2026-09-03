from typing import Any, Callable, Dict, List, cast

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
    {
        "name": "graphrag_query",
        "description": (
            "Perform GraphRAG (Graph-Augmented Retrieval) over Security Knowledge Graph (SKO). "
            "Combines keyword/vector candidate identification with 2-hop causal subgraph expansion."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": (
                        "Natural language question or security topic query "
                        "e.g. 'zero trust mesh side-channel'"
                    ),
                },
                "top_k_papers": {
                    "type": "integer",
                    "description": "Number of seed papers to discover (default: 3)",
                },
                "max_hops": {
                    "type": "integer",
                    "description": "Graph neighborhood expansion radius (default: 2)",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "get_attack_defense_chain",
        "description": (
            "Find multi-hop attack-defense causal chains: (Threat) <--[MITIGATES]-- (Defense) <--[PROPOSES]-- (Paper) "
            "to discover verified academic countermeasures for a given attack technique or CVE."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "keyword": {
                    "type": "string",
                    "description": "Target MITRE technique ID, CVE, or attack name e.g. 'T1059', 'Command Injection'",
                },
            },
            "required": ["keyword"],
        },
    },
    {
        "name": "get_blast_radius",
        "description": (
            "Calculate downstream blast radius and impacted entities/systems from a vulnerable component or attack."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "entity_id": {
                    "type": "string",
                    "description": "Target root entity ID e.g. 'CVE-2026-9999', 'TargetAsset:Kubernetes'",
                },
                "max_depth": {
                    "type": "integer",
                    "description": "Maximum traversal depth (default: 3)",
                },
            },
            "required": ["entity_id"],
        },
    },
    {
        "name": "model_stride_threats",
        "description": (
            "Analyze IaC (Terraform, CloudFormation) or OpenAPI/Swagger schemas for STRIDE security threats "
            "and correlate with academic mitigations and CWE taxonomy."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "schema_type": {
                    "type": "string",
                    "description": "Schema format e.g. 'openapi', 'terraform', 'cloudformation'",
                },
                "schema_content": {
                    "type": "string",
                    "description": "Raw JSON, YAML, or HCL configuration text to model",
                },
            },
            "required": ["schema_type", "schema_content"],
        },
    },
    {
        "name": "synthesize_detection_signature",
        "description": (
            "Synthesize verified detection signatures (Semgrep YAML, Sigma SIEM, YARA) from academic threat patterns "
            "with in-memory AST syntax validation and ReDoS static checking."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "rule_type": {
                    "type": "string",
                    "description": "Target rule format: 'semgrep', 'sigma', or 'yara'",
                },
                "rule_name": {
                    "type": "string",
                    "description": "Rule identifier or name",
                },
                "target_vulnerability": {
                    "type": "string",
                    "description": "Target CWE or vulnerability identifier e.g. 'CWE-89'",
                },
                "pattern_or_code": {
                    "type": "string",
                    "description": "Detection pattern, code snippet, or match string",
                },
                "log_source": {
                    "type": "string",
                    "description": "Optional log source for Sigma rules (default: 'process_creation')",
                },
            },
            "required": [
                "rule_type",
                "rule_name",
                "target_vulnerability",
                "pattern_or_code",
            ],
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


def _patch_eval(code: str) -> str:
    return (
        "import ast\n" + code.replace("eval(", "ast.literal_eval(")
        if "eval(" in code
        else code
    )


def _patch_sql(code: str) -> str:
    if 'f"' in code:
        return (
            "# TODO: Ensure parameterized tuples: cursor.execute(query, (params,))\n"
            + code
        )
    return code


def _apply_cwe_patch_heuristics(cwe_id: str, code: str) -> str:
    """Applies heuristic code transformations based on target CWE vulnerability."""
    patch_map: Dict[str, Callable[[str], str]] = {
        "CWE-502": lambda c: _patch_pickle(c) if "pickle." in c else c,
        "CWE-693": _patch_safetensors,
        "CWE-1357": lambda c: "# Enforce verified package imports and pin dependencies with hashes\n"
        + c,
        "CWE-94": _patch_eval,
        "CWE-89": _patch_sql,
    }
    patcher = patch_map.get(cwe_id)
    return patcher(code) if patcher else code


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


def _get_coverage_rating(score: float) -> str:
    if score >= 0.8:
        return "A+ (Excellent)"
    if score >= 0.5:
        return "B (Moderate)"
    return "C (Needs Attention)"


def _check_defense_item(
    key: str, cwe_desc: str, mitre: str, nist: str, defenses: List[str]
) -> tuple[Dict[str, Any], int]:
    active = any(key in d for d in defenses)
    item = {
        "defense_key": key,
        "protects_against": cwe_desc,
        "mitre_technique": mitre,
        "nist_control": nist,
        "status": "ENFORCED" if active else "MISSING",
    }
    return item, 1 if active else 0


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
        item, add_val = _check_defense_item(key, cwe_desc, mitre, nist, defenses)
        matched += add_val
        breakdown.append(item)

    coverage_score = round(matched / total_key_defenses, 4)

    return {
        "status": "success",
        "coverage_score": coverage_score,
        "coverage_percentage": f"{int(coverage_score * 100)}%",
        "rating": _get_coverage_rating(coverage_score),
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


def _get_graphrag_pipeline() -> Any:
    from graph.engine import PropertyGraphEngine
    from graph.graphrag import GraphRAGPipeline

    engine = PropertyGraphEngine()
    return GraphRAGPipeline(engine)


def handle_graphrag_query(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handles GraphRAG query execution with causal expansion."""
    query = params.get("query", "").strip()
    if not query:
        return {"status": "error", "message": "Missing required parameter 'query'"}
    top_k = int(params.get("top_k_papers", 3))
    max_hops = int(params.get("max_hops", 2))

    pipeline = _get_graphrag_pipeline()
    res = pipeline.query_graphrag(
        query_text=query, top_k_papers=top_k, max_hops=max_hops
    )
    return {"status": "success", **res}


def handle_get_attack_defense_chain(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handles multi-hop attack-defense causal chain discovery."""
    keyword = params.get("keyword", "").strip()
    if not keyword:
        return {"status": "error", "message": "Missing required parameter 'keyword'"}

    pipeline = _get_graphrag_pipeline()
    chains = pipeline.find_defense_chains(technique_or_vuln_keyword=keyword)
    return {
        "status": "success",
        "keyword": keyword,
        "chain_count": len(chains),
        "chains": chains,
    }


def handle_get_blast_radius(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handles blast radius impact analysis from root entity."""
    entity_id = params.get("entity_id", "").strip()
    if not entity_id:
        return {"status": "error", "message": "Missing required parameter 'entity_id'"}
    max_depth = int(params.get("max_depth", 3))

    pipeline = _get_graphrag_pipeline()
    res = pipeline.calculate_blast_radius(entity_id=entity_id, max_depth=max_depth)
    return {"status": "success", **res}


def handle_model_stride_threats(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handles automated STRIDE threat modeling against IaC and OpenAPI schemas."""
    schema_type = params.get("schema_type", "").strip()
    schema_content = params.get("schema_content", "").strip()
    if not schema_type or not schema_content:
        return {
            "status": "error",
            "message": "Missing required parameters 'schema_type' or 'schema_content'",
        }

    from .tools.threat_modeler import ThreatModeler

    modeler = ThreatModeler()
    return modeler.analyze(schema_type, schema_content)


def _dispatch_signature_gen(
    gen: Any,
    rule_type: str,
    rule_name: str,
    cwe_id: str,
    pattern: str,
    log_source: str,
) -> Dict[str, Any]:
    """Dispatches signature generation based on rule_type."""
    if rule_type == "semgrep":
        return cast(
            Dict[str, Any],
            gen.generate_semgrep(rule_id=rule_name, cwe_id=cwe_id, pattern=pattern),
        )
    if rule_type == "sigma":
        return cast(
            Dict[str, Any],
            gen.generate_sigma(
                title=rule_name,
                log_source=log_source,
                detection_fields={"CommandLine|contains": pattern},
            ),
        )
    if rule_type == "yara":
        return cast(
            Dict[str, Any],
            gen.generate_yara(
                rule_name=rule_name, strings_dict={"target_str": pattern}
            ),
        )
    return {
        "status": "error",
        "message": f"Unsupported rule_type '{rule_type}' (must be 'semgrep', 'sigma', or 'yara')",
    }


def handle_synthesize_detection_signature(params: Dict[str, Any]) -> Dict[str, Any]:
    """Handles dynamic detection signature synthesis across Semgrep, Sigma, and YARA."""
    rule_type = params.get("rule_type", "").strip().lower()
    rule_name = params.get("rule_name", "").strip()
    cwe_id = params.get("target_vulnerability", "").strip()
    pattern = params.get("pattern_or_code", "").strip()
    log_source = params.get("log_source", "process_creation").strip()

    if not (rule_type and rule_name and pattern):
        return {
            "status": "error",
            "message": "Missing required parameters for signature synthesis",
        }

    from .tools.signature_generator import SignatureGenerator

    gen = SignatureGenerator()
    return _dispatch_signature_gen(
        gen, rule_type, rule_name, cwe_id, pattern, log_source
    )


TOOL_HANDLERS: Dict[str, Callable[[Dict[str, Any]], Dict[str, Any]]] = {
    "generate_semgrep_rule": handle_generate_semgrep_rule,
    "synthesize_secure_patch": handle_synthesize_secure_patch,
    "check_threat_coverage": handle_check_threat_coverage,
    "generate_caldera_playbook": handle_generate_caldera_playbook,
    "generate_sigma_rule": handle_generate_sigma_rule,
    "graphrag_query": handle_graphrag_query,
    "get_attack_defense_chain": handle_get_attack_defense_chain,
    "get_blast_radius": handle_get_blast_radius,
    "model_stride_threats": handle_model_stride_threats,
    "synthesize_detection_signature": handle_synthesize_detection_signature,
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
