#!/usr/bin/env python3
"""
Edge Inference Rule Ontology Master (EIROM) Registry.
Provides rule loading, indexing, caching, validation, and SHA-256 integrity hashing.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import hashlib
import json
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .rule_schema import EdgeInferenceRule

logger = logging.getLogger(__name__)

DEFAULT_RULES_PATH = Path(__file__).parent / "rules" / "master_rules.json"
MAX_RULES_FILE_BYTES = 5 * 1024 * 1024
BUILTIN_RULESET_VERSION = "2026.09.1"

BUILTIN_FALLBACK_RULES: List[Dict[str, Any]] = [
    {
        "rule_id": "RULE-EDGE-PAPER-TECH-REGEX-01",
        "name": "Direct Technique ID Match",
        "description": "Matches explicit MITRE ATT&CK technique IDs (e.g. T1190) in paper title, abstract, or text.",
        "source_label": "Paper",
        "target_label": "AttackTechnique",
        "edge_label": "TARGETS",
        "condition_type": "regex",
        "condition_spec": {"pattern": r"\b(T\d{4}(?:\.\d{3})?)\b"},
        "base_confidence": 1.0,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "combined",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-TECH-TITLE-02",
        "name": "Title Technique Name Affinity",
        "description": "Matches technique name directly inside paper title indicating strong topical affinity.",
        "source_label": "Paper",
        "target_label": "AttackTechnique",
        "edge_label": "TARGETS",
        "condition_type": "lexical",
        "condition_spec": {"target_field": "title", "min_matches": 1},
        "base_confidence": 0.8,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "title",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-TECH-KEYWORD-03",
        "name": "Title Important Keyphrase Match",
        "description": "Matches technique-specific keywords or keyphrases in the paper title.",
        "source_label": "Paper",
        "target_label": "AttackTechnique",
        "edge_label": "TARGETS",
        "condition_type": "lexical",
        "condition_spec": {"target_field": "title", "weight_per_keyword": 0.5},
        "base_confidence": 0.5,
        "confidence_tier": "MEDIUM",
        "evidence_spec": {
            "target_field": "title",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-TECH-ABSTRACT-04",
        "name": "Abstract Lexical Scoring",
        "description": "Scores technique keywords and names found in abstract or full text context.",
        "source_label": "Paper",
        "target_label": "AttackTechnique",
        "edge_label": "TARGETS",
        "condition_type": "semantic_threshold",
        "condition_spec": {"min_threshold": 0.4, "abstract_weight": 0.25},
        "base_confidence": 0.5,
        "confidence_tier": "MEDIUM",
        "evidence_spec": {
            "target_field": "abstract",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-CWE-REGEX-01",
        "name": "Direct CWE Weakness Identification",
        "description": "Matches explicit Common Weakness Enumeration IDs (e.g. CWE-79) in paper text.",
        "source_label": "Paper",
        "target_label": "CWE",
        "edge_label": "EXPLOITS_VULNERABILITY",
        "condition_type": "regex",
        "condition_spec": {"pattern": r"\bCWE-\d{1,5}\b"},
        "base_confidence": 1.0,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "combined",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-TECH-STACK-01",
        "name": "Target Technology Stack Identification",
        "description": "Identifies target technology, platform, or architecture analyzed by the paper.",
        "source_label": "Paper",
        "target_label": "Technology",
        "edge_label": "TARGETS_ASSET",
        "condition_type": "lexical",
        "condition_spec": {
            "target_field": "combined",
            "categories": ["os", "cloud", "firmware", "protocol"],
        },
        "base_confidence": 0.7,
        "confidence_tier": "MEDIUM",
        "evidence_spec": {
            "target_field": "combined",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-DEFENSE-01",
        "name": "Proposed Defense Method Identification",
        "description": "Detects novel algorithmic or architectural security defense proposals.",
        "source_label": "Paper",
        "target_label": "DefenseMethod",
        "edge_label": "PROPOSES_DEFENSE",
        "condition_type": "lexical",
        "condition_spec": {"target_field": "title", "focus": "defensive"},
        "base_confidence": 0.8,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "title",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-TECH-MITIGATE-AXIOM-01",
        "name": "ATT&CK Mitigation Axiom",
        "description": "Axiomatic relation linking MITRE Course of Action (Mitigation) to AttackTechnique.",
        "source_label": "Mitigation",
        "target_label": "AttackTechnique",
        "edge_label": "MITIGATES",
        "condition_type": "catalog_axiom",
        "condition_spec": {"catalog": "mitre-attack", "relation": "mitigates"},
        "base_confidence": 1.0,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "catalog",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-TECH-CWE-AXIOM-02",
        "name": "CAPEC/CWE Exploitation Axiom",
        "description": "Axiomatic relation linking AttackTechnique to underlying software weakness (CWE).",
        "source_label": "AttackTechnique",
        "target_label": "CWE",
        "edge_label": "EXPLOITS_VULNERABILITY",
        "condition_type": "catalog_axiom",
        "condition_spec": {"catalog": "capec-cwe-mapping", "relation": "exploits"},
        "base_confidence": 0.9,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "catalog",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-MITIGATION-CONTROL-01",
        "name": "Mitigation to NIST/CIS Control Mapping",
        "description": "Maps mitigation concepts to enterprise compliance security controls.",
        "source_label": "Mitigation",
        "target_label": "Control",
        "edge_label": "IMPLEMENTS_CONTROL",
        "condition_type": "catalog_axiom",
        "condition_spec": {"frameworks": ["NIST_SP_800_53", "CIS_Controls"]},
        "base_confidence": 0.85,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "catalog",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-FOCUS-OFFENSIVE-01",
        "name": "Offensive Context Modifier",
        "description": "Applies offensive context modifier when paper explores offensive attack exploitation.",
        "source_label": "Paper",
        "target_label": "AttackTechnique",
        "edge_label": "TARGETS",
        "condition_type": "context_ratio",
        "condition_spec": {"focus_direction": "offensive", "dominant_factor": 2},
        "base_confidence": 0.75,
        "confidence_tier": "MEDIUM",
        "evidence_spec": {
            "target_field": "combined",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-FOCUS-DEFENSIVE-02",
        "name": "Defensive Context Modifier",
        "description": "Applies defensive context modifier when paper proposes mitigation and countermeasures.",
        "source_label": "Paper",
        "target_label": "DefenseMethod",
        "edge_label": "PROPOSES_DEFENSE",
        "condition_type": "context_ratio",
        "condition_spec": {"focus_direction": "defensive", "dominant_factor": 2},
        "base_confidence": 0.75,
        "confidence_tier": "MEDIUM",
        "evidence_spec": {
            "target_field": "combined",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-PRECONDITION-01",
        "name": "Threat Model Precondition Requirement",
        "description": "Infers threat model and access requirements (Remote, Local, Physical, White-box).",
        "source_label": "Paper",
        "target_label": "Precondition",
        "edge_label": "REQUIRES_PRECONDITION",
        "condition_type": "lexical",
        "condition_spec": {"target_field": "combined", "min_matches": 1},
        "base_confidence": 0.85,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "combined",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-DEFENSE-DETECTION-BLOCKS-01",
        "name": "Detection Rule Blocks Attack Technique",
        "description": "Links concrete detection rules (Semgrep, Sigma, YARA) to blocked attack techniques.",
        "source_label": "DetectionRule",
        "target_label": "AttackTechnique",
        "edge_label": "BLOCKS",
        "condition_type": "catalog_axiom",
        "condition_spec": {"rule_engine": "siem_edr"},
        "base_confidence": 0.9,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "rule_syntax",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-GAP-IDENTIFIES-01",
        "name": "Research Gap Identification",
        "description": "Infers unaddressed open challenges, scalability bottlenecks, and residual risks.",
        "source_label": "Paper",
        "target_label": "ResearchGap",
        "edge_label": "IDENTIFIES_GAP",
        "condition_type": "lexical",
        "condition_spec": {"target_field": "combined", "min_matches": 1},
        "base_confidence": 0.8,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "combined",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
    {
        "rule_id": "RULE-EDGE-PAPER-VENUE-PRESENTED-01",
        "name": "Academic Venue Provenance Attribution",
        "description": "Attributes academic prestige, tier, and peer-review venue provenance.",
        "source_label": "Paper",
        "target_label": "PublicationVenue",
        "edge_label": "PRESENTED_AT",
        "condition_type": "catalog_axiom",
        "condition_spec": {"venue_registry": "core_rankings"},
        "base_confidence": 1.0,
        "confidence_tier": "HIGH",
        "evidence_spec": {
            "target_field": "comment",
            "max_snippet_length": 120,
            "case_sensitive": False,
        },
        "version": BUILTIN_RULESET_VERSION,
        "is_active": True,
    },
]


def _validate_rules_file_meta(target: Path) -> None:
    """Validates regular file, .json extension, and bounded file size."""
    if not target.is_file():
        raise ValueError(f"Rules path is not a regular file: {target}")
    if target.suffix.lower() != ".json":
        raise ValueError(f"Rules file must have .json extension: {target}")
    if target.stat().st_size > MAX_RULES_FILE_BYTES:
        raise ValueError(
            f"Rules file exceeds max allowed bytes ({MAX_RULES_FILE_BYTES}): {target}"
        )


def _resolve_rules_path(path: Optional[str]) -> Path:
    """Resolves and validates rules JSON path."""
    target = Path(path).resolve() if path is not None else DEFAULT_RULES_PATH.resolve()
    if not target.exists():
        raise FileNotFoundError(f"Rules file not found at: {target}")
    _validate_rules_file_meta(target)
    return target


def _read_json_file(file_path: Path) -> object:
    """Reads and decodes UTF-8 JSON file safely."""
    with open(file_path, "r", encoding="utf-8") as f:
        data: object = json.load(f)
    return data


def _ensure_rule_dicts(rule_list: List[object]) -> List[Dict[str, Any]]:
    """Validates that every rule entry is a dictionary."""
    validated: List[Dict[str, Any]] = []
    for idx, item in enumerate(rule_list):
        if not isinstance(item, dict):
            raise ValueError(f"Rule entry at index {idx} must be a JSON object.")
        validated.append(item)
    return validated


def _extract_rules_payload(raw_data: object) -> Tuple[str, List[Dict[str, Any]]]:
    """Validates top-level JSON structure and extracts version + rule list."""
    if not isinstance(raw_data, dict):
        raise ValueError("Rules master JSON root must be a JSON object.")
    rule_list = raw_data.get("rules")
    if not isinstance(rule_list, list) or not rule_list:
        raise ValueError("Expected non-empty 'rules' list in JSON master file.")
    version = str(raw_data.get("version", BUILTIN_RULESET_VERSION))
    return version, _ensure_rule_dicts(rule_list)


def _build_validated_rules(rule_list: List[Dict[str, Any]]) -> List[EdgeInferenceRule]:
    """Constructs validated rules while rejecting duplicate rule_id entries."""
    built: List[EdgeInferenceRule] = []
    seen_ids: set[str] = set()
    for item in rule_list:
        try:
            rule = EdgeInferenceRule.from_dict(item)
        except TypeError as err:
            raise ValueError(f"Invalid rule entry format: {err}") from err
        if rule.rule_id in seen_ids:
            raise ValueError(f"Duplicate rule_id detected: '{rule.rule_id}'")
        seen_ids.add(rule.rule_id)
        built.append(rule)
    return built


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
        strict: bool = False,
    ) -> None:
        self._rules: Dict[str, EdgeInferenceRule] = {}
        self._pair_index: Dict[Tuple[str, str], List[str]] = {}
        self._ruleset_hash: str = ""
        self._loaded_source: str = "uninitialized"
        self._is_fallback: bool = False
        self._ruleset_version: str = ""

        if auto_load:
            self._initialize_rules(custom_path, strict)

    @property
    def loaded_source(self) -> str:
        """Returns provenance descriptor of the currently loaded ruleset."""
        return self._loaded_source

    @property
    def is_fallback(self) -> bool:
        """Returns True if registry fell back to built-in rules."""
        return self._is_fallback

    @property
    def ruleset_version(self) -> str:
        """Returns version string of the currently loaded ruleset."""
        return self._ruleset_version

    def _initialize_rules(self, custom_path: Optional[str], strict: bool) -> None:
        """Initializes rules fail-closed for explicit paths or strict mode."""
        if custom_path is not None or strict:
            self.load_from_json(custom_path)
            return
        try:
            self.load_from_json(None)
        except FileNotFoundError as err:
            logger.warning(
                "Default EIROM master file unavailable (%s); using built-in fallback rules.",
                err,
            )
            self.load_builtin_rules()

    def clear(self) -> None:
        """Clears all registered rules and index."""
        self._rules.clear()
        self._pair_index.clear()
        self._ruleset_hash = ""
        self._loaded_source = "uninitialized"
        self._is_fallback = False
        self._ruleset_version = ""

    def register_rule(self, rule: EdgeInferenceRule) -> None:
        """Registers a validated EdgeInferenceRule and updates index."""
        self._rules[rule.rule_id] = rule
        pair_key = (rule.source_label, rule.target_label)
        if pair_key not in self._pair_index:
            self._pair_index[pair_key] = []
        if rule.rule_id not in self._pair_index[pair_key]:
            self._pair_index[pair_key].append(rule.rule_id)
        self._ruleset_hash = ""

    def _replace_rules(
        self,
        rules: List[EdgeInferenceRule],
        source: str,
        version: str,
        is_fallback: bool,
    ) -> None:
        """Atomically swaps validated rules and records provenance metadata."""
        self.clear()
        for rule in rules:
            self.register_rule(rule)
        self._loaded_source = source
        self._ruleset_version = version
        self._is_fallback = is_fallback
        self.compute_ruleset_hash()

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
        """Loads and validates rules from JSON file atomically."""
        target_path = _resolve_rules_path(path)
        raw_data = _read_json_file(target_path)
        version, rule_dicts = _extract_rules_payload(raw_data)
        validated = _build_validated_rules(rule_dicts)
        self._replace_rules(
            validated,
            source=f"json:{target_path}",
            version=version,
            is_fallback=False,
        )

    def load_builtin_rules(self) -> None:
        """Loads fallback built-in axiomatic rules matching the SSOT master."""
        validated = _build_validated_rules(BUILTIN_FALLBACK_RULES)
        self._replace_rules(
            validated,
            source="builtin_fallback",
            version=BUILTIN_RULESET_VERSION,
            is_fallback=True,
        )
