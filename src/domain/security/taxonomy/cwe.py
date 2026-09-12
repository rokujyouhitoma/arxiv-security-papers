#!/usr/bin/env python3
"""
CWE (Common Weakness Enumeration) Taxonomy & Defense Knowledge Base.
Provides academic and industry proven mitigation recipes and Semgrep detection patterns.
"""

from typing import Any, Dict, Optional

CWE_DEFENSE_MAP: Dict[str, Dict[str, Any]] = {
    "CWE-94": {
        "name": "Code Injection",
        "description": "Improper Control of Generation of Code ('Code Injection')",
        "semgrep_pattern": "eval($...X) | exec($...X) | compile($...X)",
        "secure_alternative": "ast.parse() validation with strict node inspection or safe arithmetic parsing",
        "patch_strategy": "Replace dynamic eval/exec with AST-based whitelist parser or literal_eval",
        "mitre_technique": "T1059.006 (Python Command and Scripting Interpreter)",
        "secure_coding_patterns": [
            "import ast\ntree = ast.parse(expr, mode='eval')",
            "import json\ndata = json.loads(untrusted_payload)",
        ],
    },
    "CWE-89": {
        "name": "SQL Injection",
        "description": "Improper Neutralization of Special Elements used in an SQL Command",
        "semgrep_pattern": '$CURSOR.execute(f"...{$VAR}...") | $CURSOR.execute("..." + $VAR)',
        "secure_alternative": "Parameterized queries: cursor.execute('SELECT * FROM t WHERE id = ?', (var,))",
        "patch_strategy": "Convert f-strings and string concatenations into parameterized query tuples",
        "mitre_technique": "T1190 (Exploit Public-Facing Application)",
        "secure_coding_patterns": [
            "cursor.execute('SELECT * FROM users WHERE id = ?', (user_id,))",
            "cursor.execute('INSERT INTO logs (msg) VALUES (?)', (message,))",
        ],
    },
    "CWE-502": {
        "name": "Deserialization of Untrusted Data",
        "description": "Deserialization of Untrusted Data (Pickle / PyYAML unsafe load)",
        "semgrep_pattern": "pickle.loads($...X) | yaml.load($...X, Loader=yaml.Loader)",
        "secure_alternative": "json.loads() or yaml.safe_load() / safetensors",
        "patch_strategy": "Replace pickle with json or protobuf/safetensors for model weights",
        "mitre_technique": "T1587.001 (Develop Capabilities: Malware/Payload)",
        "secure_coding_patterns": [
            "import json\ndata = json.loads(payload)",
            "import yaml\ndata = yaml.safe_load(payload)",
        ],
    },
    "CWE-22": {
        "name": "Path Traversal",
        "description": "Improper Limitation of a Pathname to a Restricted Directory ('Path Traversal')",
        "semgrep_pattern": "open(os.path.join($BASE, $USER_INPUT))",
        "secure_alternative": "os.path.commonpath([base_dir, resolved_path]) == base_dir",
        "patch_strategy": "Resolve realpath and enforce strict commonpath prefix verification",
        "mitre_technique": "T1083 (File and Directory Discovery)",
        "secure_coding_patterns": [
            (
                "real_path = os.path.realpath(os.path.join(base_dir, user_input))\n"
                "if os.path.commonpath([base_dir, real_path]) != base_dir:\n"
                "    raise PermissionError('Path Traversal')"
            ),
        ],
    },
    "CWE-79": {
        "name": "Cross-site Scripting (XSS)",
        "description": "Improper Neutralization of Input During Web Page Generation",
        "semgrep_pattern": "innerHTML = $USER_INPUT | document.write($USER_INPUT)",
        "secure_alternative": "textContent = sanitized_input or html.escape()",
        "patch_strategy": "Replace innerHTML with textContent or strict DOM sanitizer",
        "mitre_technique": "T1189 (Drive-by Compromise)",
        "secure_coding_patterns": [
            "import html\nsafe_text = html.escape(untrusted_str)",
            "element.textContent = untrusted_str",
        ],
    },
    "CWE-78": {
        "name": "OS Command Injection",
        "description": "Improper Neutralization of Special Elements used in an OS Command",
        "semgrep_pattern": "os.system($...X) | subprocess.Popen($...X, shell=True)",
        "secure_alternative": "subprocess.run(['cmd', arg], shell=False, check=True)",
        "patch_strategy": "Use argument list without shell=True and validate strict whitelisting",
        "mitre_technique": "T1059 (Command and Scripting Interpreter)",
        "secure_coding_patterns": [
            "import subprocess\nsubprocess.run(['ls', '-l', safe_target], check=True)",
        ],
    },
    "CWE-1357": {
        "name": "Slopsquatting & Dependency Confusion",
        "description": "Reliance on Uncontrolled Component with LLM Hallucinated Package Names",
        "semgrep_pattern": "import $HALLUCINATED_PKG | from $HALLUCINATED_PKG import $...X",
        "secure_alternative": "Private registry pin and zero-dependency verified namespace allow-list",
        "patch_strategy": "Lock approved dependency hashes and enforce verified registry namespace",
        "mitre_technique": "T1195.001 (Supply Chain Compromise: Compromise Software Dependencies)",
        "secure_coding_patterns": [
            "# Lock approved dependencies in requirements.txt with sha256 hashes",
            "from security.validation import is_safe_package_name",
        ],
    },
    "CWE-693": {
        "name": "Exception-Oriented Programming (EOP) Model Poisoning",
        "description": "Protection Mechanism Failure via Opcode Mismatch and Control Flow Hijacking",
        "semgrep_pattern": "torch.load($...X) | pickle.load($...X)",
        "secure_alternative": "safetensors.torch.load_file(path) or onnx.load(path)",
        "patch_strategy": "Convert model checkpoint serialization to SafeTensors zero-code-execution format",
        "mitre_technique": "T1587.001 (Develop Capabilities: Malware/Payload)",
        "secure_coding_patterns": [
            "from safetensors.torch import load_file\nweights = load_file(model_path)",
        ],
    },
}


def get_cwe_recipe(cwe_id: str) -> Optional[Dict[str, Any]]:
    """Returns CWE defense definition and remediation recipe."""
    normalized = cwe_id.upper()
    if not normalized.startswith("CWE-"):
        normalized = f"CWE-{normalized}"
    return CWE_DEFENSE_MAP.get(normalized)


def _extract_first_mitigation(mitigations: Any) -> str:
    if isinstance(mitigations, list) and mitigations:
        first = mitigations[0]
        if isinstance(first, dict):
            return str(first.get("description", "") or "Refer to MITRE CWE guidance.")
    return "Refer to MITRE CWE guidance."


def _build_dynamic_cwe_definition(
    cwe_record: Dict[str, Any], normalized: str
) -> Dict[str, Any]:
    mitigations = cwe_record.get("mitigations") or []
    return {
        "name": cwe_record.get("name", normalized),
        "description": cwe_record.get("description", ""),
        "semgrep_pattern": "",
        "secure_alternative": _extract_first_mitigation(mitigations),
        "patch_strategy": "Apply defensive coding and mitigations recommended by MITRE CWE.",
        "mitre_technique": "",
        "is_top25": cwe_record.get("is_top25", False),
        "top25_rank": cwe_record.get("top25_rank"),
        "abstraction": cwe_record.get("abstraction", "Base"),
        "mitigations": mitigations,
        "secure_coding_patterns": [],
    }


def _normalize_cwe_key(cwe_id: str) -> str:
    s = cwe_id.strip().upper()
    return s if s.startswith("CWE-") or not s else f"CWE-{s}"


def _fetch_storage_cwe(storage: Any, normalized: str) -> Optional[Dict[str, Any]]:
    try:
        from domain.security.cti.storage import CTICatalogStorage

        inst: CTICatalogStorage = (
            storage if isinstance(storage, CTICatalogStorage) else CTICatalogStorage()
        )
        return inst.get_cwe(normalized)
    except Exception:
        return None


def get_cwe_definition(
    cwe_id: str, storage: Optional[Any] = None
) -> Optional[Dict[str, Any]]:
    """Hybrid resolver for CWE definitions.

    Prefers static high-fidelity defense recipes in CWE_DEFENSE_MAP,
    falling back to dynamic cti_catalog_db records stored via CweSpider.
    """
    recipe = get_cwe_recipe(cwe_id)
    if recipe is not None:
        return recipe

    normalized = _normalize_cwe_key(cwe_id)
    if not normalized:
        return None

    cwe_record = _fetch_storage_cwe(storage, normalized)
    if cwe_record:
        return _build_dynamic_cwe_definition(cwe_record, normalized)

    return None


_CWE_TRIE: Optional[Any] = None


def _get_cwe_trie() -> Any:
    global _CWE_TRIE
    if _CWE_TRIE is None:
        from core.structures.radix_trie import RadixTrie

        trie: RadixTrie[Dict[str, Any]] = RadixTrie()
        for c_id, meta in CWE_DEFENSE_MAP.items():
            trie.insert(c_id, meta)
        _CWE_TRIE = trie
    return _CWE_TRIE


def search_cwe_by_prefix(prefix: str, limit: int = 10) -> list[Dict[str, Any]]:
    """Search CWE definitions by prefix (e.g. 'CWE-7', '79') using Radix Trie."""
    norm_prefix = prefix.upper()
    if not norm_prefix.startswith("CWE-") and not "CWE-".startswith(norm_prefix):
        norm_prefix = f"CWE-{norm_prefix}"
    trie = _get_cwe_trie()
    matched = trie.find_by_prefix(norm_prefix, limit=limit)
    return [{"id": k, **v} for k, v in matched]
