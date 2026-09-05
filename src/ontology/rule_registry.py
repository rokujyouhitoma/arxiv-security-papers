#!/usr/bin/env python3
"""
Edge Inference Rule Ontology Master (EIROM) Registry.
Provides rule loading, indexing, caching, validation, and SHA-256 integrity hashing.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .rule_schema import EdgeInferenceRule

DEFAULT_RULES_PATH = Path(__file__).parent / "rules" / "master_rules.json"

BUILTIN_FALLBACK_RULES: List[Dict[str, Any]] = [
    {
        "rule_id": "RULE-EDGE-PAPER-TECH-REGEX-01",
        "name": "Direct Technique ID Match",
        "description": "Matches explicit MITRE ATT&CK technique IDs.",
        "source_label": "Paper",
        "target_label": "AttackTechnique",
        "edge_label": "TARGETS",
        "condition_type": "regex",
        "condition_spec": {"pattern": r"\b(T\d{4}(?:\.\d{3})?)\b"},
        "base_confidence": 1.0,
        "confidence_tier": "HIGH",
        "evidence_spec": {"target_field": "combined", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-TECH-TITLE-02",
        "name": "Title Technique Name Affinity",
        "description": "Matches technique name inside paper title.",
        "source_label": "Paper",
        "target_label": "AttackTechnique",
        "edge_label": "TARGETS",
        "condition_type": "lexical",
        "condition_spec": {"target_field": "title", "min_matches": 1},
        "base_confidence": 0.8,
        "confidence_tier": "HIGH",
        "evidence_spec": {"target_field": "title", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-TECH-KEYWORD-03",
        "name": "Title Important Keyphrase Match",
        "description": "Matches technique-specific keywords in title.",
        "source_label": "Paper",
        "target_label": "AttackTechnique",
        "edge_label": "TARGETS",
        "condition_type": "lexical",
        "condition_spec": {"target_field": "title", "weight_per_keyword": 0.5},
        "base_confidence": 0.5,
        "confidence_tier": "MEDIUM",
        "evidence_spec": {"target_field": "title", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-TECH-ABSTRACT-04",
        "name": "Abstract Lexical Scoring",
        "description": "Scores technique keywords in abstract or full text.",
        "source_label": "Paper",
        "target_label": "AttackTechnique",
        "edge_label": "TARGETS",
        "condition_type": "semantic_threshold",
        "condition_spec": {"min_threshold": 0.4, "abstract_weight": 0.25},
        "base_confidence": 0.5,
        "confidence_tier": "MEDIUM",
        "evidence_spec": {"target_field": "abstract", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-CWE-REGEX-01",
        "name": "Direct CWE Weakness Identification",
        "description": "Matches explicit CWE IDs in paper text.",
        "source_label": "Paper",
        "target_label": "CWE",
        "edge_label": "EXPLOITS_VULNERABILITY",
        "condition_type": "regex",
        "condition_spec": {"pattern": r"\bCWE-\d{1,5}\b"},
        "base_confidence": 1.0,
        "confidence_tier": "HIGH",
        "evidence_spec": {"target_field": "combined", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-TECH-STACK-01",
        "name": "Target Technology Stack Identification",
        "description": "Identifies target platform or architecture.",
        "source_label": "Paper",
        "target_label": "Technology",
        "edge_label": "TARGETS_ASSET",
        "condition_type": "lexical",
        "condition_spec": {"target_field": "combined"},
        "base_confidence": 0.7,
        "confidence_tier": "MEDIUM",
        "evidence_spec": {"target_field": "combined", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-DEFENSE-01",
        "name": "Proposed Defense Method Identification",
        "description": "Detects proposed security defense methods.",
        "source_label": "Paper",
        "target_label": "DefenseMethod",
        "edge_label": "PROPOSES_DEFENSE",
        "condition_type": "lexical",
        "condition_spec": {"target_field": "title", "focus": "defensive"},
        "base_confidence": 0.8,
        "confidence_tier": "HIGH",
        "evidence_spec": {"target_field": "title", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-TECH-MITIGATE-AXIOM-01",
        "name": "ATT&CK Mitigation Axiom",
        "description": "Axiom linking Mitigation to AttackTechnique.",
        "source_label": "Mitigation",
        "target_label": "AttackTechnique",
        "edge_label": "MITIGATES",
        "condition_type": "catalog_axiom",
        "condition_spec": {"catalog": "mitre-attack", "relation": "mitigates"},
        "base_confidence": 1.0,
        "confidence_tier": "HIGH",
        "evidence_spec": {"target_field": "catalog", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-TECH-CWE-AXIOM-02",
        "name": "CAPEC/CWE Exploitation Axiom",
        "description": "Axiom linking AttackTechnique to CWE.",
        "source_label": "AttackTechnique",
        "target_label": "CWE",
        "edge_label": "EXPLOITS_VULNERABILITY",
        "condition_type": "catalog_axiom",
        "condition_spec": {"catalog": "capec-cwe-mapping", "relation": "exploits"},
        "base_confidence": 0.9,
        "confidence_tier": "HIGH",
        "evidence_spec": {"target_field": "catalog", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-MITIGATION-CONTROL-01",
        "name": "Mitigation to NIST/CIS Control Mapping",
        "description": "Maps mitigation concepts to security controls.",
        "source_label": "Mitigation",
        "target_label": "Control",
        "edge_label": "IMPLEMENTS_CONTROL",
        "condition_type": "catalog_axiom",
        "condition_spec": {"frameworks": ["NIST_SP_800_53", "CIS_Controls"]},
        "base_confidence": 0.85,
        "confidence_tier": "HIGH",
        "evidence_spec": {"target_field": "catalog", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-FOCUS-OFFENSIVE-01",
        "name": "Offensive Context Modifier",
        "description": "Applies offensive context modifier.",
        "source_label": "Paper",
        "target_label": "AttackTechnique",
        "edge_label": "TARGETS",
        "condition_type": "context_ratio",
        "condition_spec": {"focus_direction": "offensive", "dominant_factor": 2},
        "base_confidence": 0.75,
        "confidence_tier": "MEDIUM",
        "evidence_spec": {"target_field": "combined", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-FOCUS-DEFENSIVE-02",
        "name": "Defensive Context Modifier",
        "description": "Applies defensive context modifier.",
        "source_label": "Paper",
        "target_label": "DefenseMethod",
        "edge_label": "PROPOSES_DEFENSE",
        "condition_type": "context_ratio",
        "condition_spec": {"focus_direction": "defensive", "dominant_factor": 2},
        "base_confidence": 0.75,
        "confidence_tier": "MEDIUM",
        "evidence_spec": {"target_field": "combined", "max_snippet_length": 120},
        "version": "2026.09.1",
        "is_active": True,
    },
]


def _read_json_file(file_path: Path) -> Dict[str, Any]:
    """Reads and decodes JSON file safely."""
    with open(file_path, "r", encoding="utf-8") as f:
        data: Dict[str, Any] = json.load(f)
    return data


def _calculate_dict_hash(data: List[Dict[str, Any]]) -> str:
    """Computes SHA-256 digest from sorted dictionary structures."""
    encoded = json.dumps(data, sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


class EdgeInferenceRuleRegistry:
    """
    Central registry for Edge Inference Rule Ontology Master (EIROM).
    Provides indexed retrieval by vertex pair, rule lookup, and integrity hashing.
    """

    def __init__(
        self,
        auto_load: bool = True,
        custom_path: Optional[str] = None,
    ) -> None:
        self._rules: Dict[str, EdgeInferenceRule] = {}
        self._pair_index: Dict[Tuple[str, str], List[str]] = {}
        self._ruleset_hash: str = ""

        if auto_load:
            self._initialize_rules(custom_path)

    def _initialize_rules(self, custom_path: Optional[str]) -> None:
        """Initializes rules from file with fallback to builtins."""
        try:
            self.load_from_json(custom_path)
        except (OSError, ValueError):
            self.load_builtin_rules()

    def clear(self) -> None:
        """Clears all registered rules and index."""
        self._rules.clear()
        self._pair_index.clear()
        self._ruleset_hash = ""

    def register_rule(self, rule: EdgeInferenceRule) -> None:
        """Registers a validated EdgeInferenceRule and updates index."""
        self._rules[rule.rule_id] = rule
        pair_key = (rule.source_label, rule.target_label)
        if pair_key not in self._pair_index:
            self._pair_index[pair_key] = []
        if rule.rule_id not in self._pair_index[pair_key]:
            self._pair_index[pair_key].append(rule.rule_id)
        self._ruleset_hash = ""

    def get_rule(self, rule_id: str) -> Optional[EdgeInferenceRule]:
        """Retrieves rule by ID."""
        return self._rules.get(rule_id)

    def get_rules_for_pair(
        self,
        source_label: str,
        target_label: str,
        active_only: bool = True,
    ) -> List[EdgeInferenceRule]:
        """Retrieves all rules applicable to source and target vertex labels."""
        rule_ids = self._pair_index.get((source_label, target_label), [])
        matched: List[EdgeInferenceRule] = []
        for rid in rule_ids:
            rule = self._rules.get(rid)
            if rule and (not active_only or rule.is_active):
                matched.append(rule)
        return matched

    def get_active_rules(self) -> List[EdgeInferenceRule]:
        """Returns all currently active rules."""
        return [r for r in self._rules.values() if r.is_active]

    def get_all_rules(self) -> List[EdgeInferenceRule]:
        """Returns all registered rules regardless of active status."""
        return list(self._rules.values())

    def compute_ruleset_hash(self) -> str:
        """Computes and caches SHA-256 fingerprint of the current rule set."""
        if not self._ruleset_hash:
            sorted_rules = sorted(self._rules.values(), key=lambda r: r.rule_id)
            dicts = [r.to_dict() for r in sorted_rules]
            self._ruleset_hash = _calculate_dict_hash(dicts)
        return self._ruleset_hash

    def load_from_json(self, path: Optional[str] = None) -> None:
        """Loads and validates rules from JSON file."""
        target_path = Path(path) if path else DEFAULT_RULES_PATH
        if not target_path.exists():
            raise FileNotFoundError(f"Rules file not found at: {target_path}")

        raw_data = _read_json_file(target_path)
        rule_list = raw_data.get("rules", [])
        if not isinstance(rule_list, list):
            raise ValueError("Expected 'rules' list in JSON master file.")

        self.clear()
        for item in rule_list:
            rule = EdgeInferenceRule.from_dict(item)
            self.register_rule(rule)
        self.compute_ruleset_hash()

    def load_builtin_rules(self) -> None:
        """Loads fallback built-in axiomatic rules."""
        self.clear()
        for item in BUILTIN_FALLBACK_RULES:
            rule = EdgeInferenceRule.from_dict(item)
            self.register_rule(rule)
        self.compute_ruleset_hash()
