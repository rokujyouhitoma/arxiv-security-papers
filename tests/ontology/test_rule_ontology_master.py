#!/usr/bin/env python3
"""
Unit tests for Edge Inference Rule Ontology Master (EIROM).
Tests rule schema validation, ReDoS resistance, registry loading,
pair querying, hash integrity, and inference engine attribution.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

import pytest

import ontology.rule_registry as rule_registry_mod
from domain.security.cti import InferredTechnique, TechniqueInferenceEngine
from ontology import (
    ConfidenceTier,
    EdgeInferenceRule,
    EdgeInferenceRuleRegistry,
    EvidenceExtractionSpec,
    RuleConditionType,
)
from ontology.rule_registry import DEFAULT_RULES_PATH


class TestRuleSchema:
    """Tests for rule schema, enums, evidence specs, and validation invariants."""

    def test_confidence_tier_from_score(self) -> None:
        assert ConfidenceTier.from_score(0.95) == ConfidenceTier.HIGH
        assert ConfidenceTier.from_score(0.80) == ConfidenceTier.HIGH
        assert ConfidenceTier.from_score(0.75) == ConfidenceTier.MEDIUM
        assert ConfidenceTier.from_score(0.50) == ConfidenceTier.MEDIUM
        assert ConfidenceTier.from_score(0.49) == ConfidenceTier.LOW
        assert ConfidenceTier.from_score(0.0) == ConfidenceTier.LOW

    def test_evidence_extraction_spec_serialization(self) -> None:
        spec = EvidenceExtractionSpec(
            target_field="abstract",
            max_snippet_length=150,
            case_sensitive=True,
        )
        d = spec.to_dict()
        assert d["target_field"] == "abstract"
        assert d["max_snippet_length"] == 150
        assert d["case_sensitive"] is True

        restored = EvidenceExtractionSpec.from_dict(d)
        assert restored == spec

    def test_valid_edge_inference_rule(self) -> None:
        rule = EdgeInferenceRule(
            rule_id="RULE-TEST-01",
            name="Test Rule",
            description="Test rule description",
            source_label="Paper",
            target_label="AttackTechnique",
            edge_label="TARGETS",
            condition_type=RuleConditionType.REGEX,
            condition_spec={"pattern": r"\bT1190\b"},
            base_confidence=0.9,
            confidence_tier=ConfidenceTier.HIGH,
        )
        assert rule.rule_id == "RULE-TEST-01"
        assert rule.is_active is True

        d = rule.to_dict()
        restored = EdgeInferenceRule.from_dict(d)
        assert restored.rule_id == rule.rule_id
        assert restored.base_confidence == rule.base_confidence

    def test_invalid_rule_id_format(self) -> None:
        with pytest.raises(ValueError, match="Invalid rule_id"):
            EdgeInferenceRule(
                rule_id="INVALID-01",
                name="Bad ID",
                description="desc",
                source_label="Paper",
                target_label="AttackTechnique",
                edge_label="TARGETS",
                condition_type=RuleConditionType.LEXICAL,
                condition_spec={},
                base_confidence=0.5,
                confidence_tier=ConfidenceTier.MEDIUM,
            )

    def test_invalid_confidence_bounds(self) -> None:
        with pytest.raises(ValueError, match="Confidence score"):
            EdgeInferenceRule(
                rule_id="RULE-TEST-BOUNDS",
                name="Out of bounds",
                description="desc",
                source_label="Paper",
                target_label="AttackTechnique",
                edge_label="TARGETS",
                condition_type=RuleConditionType.LEXICAL,
                condition_spec={},
                base_confidence=1.5,
                confidence_tier=ConfidenceTier.HIGH,
            )

    def test_missing_regex_pattern(self) -> None:
        with pytest.raises(ValueError, match="missing 'pattern' spec"):
            EdgeInferenceRule(
                rule_id="RULE-TEST-NOPATTERN",
                name="No pattern",
                description="desc",
                source_label="Paper",
                target_label="AttackTechnique",
                edge_label="TARGETS",
                condition_type=RuleConditionType.REGEX,
                condition_spec={},
                base_confidence=0.8,
                confidence_tier=ConfidenceTier.HIGH,
            )

    def test_redos_pattern_rejection(self) -> None:
        with pytest.raises(ValueError, match="Suspect ReDoS pattern detected"):
            EdgeInferenceRule(
                rule_id="RULE-TEST-REDOS",
                name="ReDoS Attack Pattern",
                description="desc",
                source_label="Paper",
                target_label="AttackTechnique",
                edge_label="TARGETS",
                condition_type=RuleConditionType.REGEX,
                condition_spec={"pattern": r"([a-zA-Z]+)*"},
                base_confidence=0.8,
                confidence_tier=ConfidenceTier.HIGH,
            )


class TestRuleRegistry:
    """Tests for EdgeInferenceRuleRegistry loading, indexing, and hashing."""

    def test_load_standard_master_rules(self) -> None:
        registry = EdgeInferenceRuleRegistry(auto_load=True)
        rules = registry.get_all_rules()
        assert len(rules) == 16

        rule_ids = {r.rule_id for r in rules}
        assert "RULE-EDGE-PAPER-TECH-REGEX-01" in rule_ids
        assert "RULE-EDGE-PAPER-CWE-REGEX-01" in rule_ids
        assert "RULE-EDGE-TECH-MITIGATE-AXIOM-01" in rule_ids
        assert "RULE-EDGE-PAPER-PRECONDITION-01" in rule_ids
        assert "RULE-EDGE-DEFENSE-DETECTION-BLOCKS-01" in rule_ids
        assert "RULE-EDGE-PAPER-GAP-IDENTIFIES-01" in rule_ids
        assert "RULE-EDGE-PAPER-VENUE-PRESENTED-01" in rule_ids

    def test_get_rules_for_pair(self) -> None:
        registry = EdgeInferenceRuleRegistry(auto_load=True)
        paper_tech_rules = registry.get_rules_for_pair("Paper", "AttackTechnique")
        assert len(paper_tech_rules) >= 4

        labels = {r.edge_label for r in paper_tech_rules}
        assert "TARGETS" in labels

        unknown_pair = registry.get_rules_for_pair("UnknownSource", "UnknownTarget")
        assert unknown_pair == []

    def test_compute_ruleset_hash_integrity(self) -> None:
        registry = EdgeInferenceRuleRegistry(auto_load=True)
        h1 = registry.compute_ruleset_hash()
        assert len(h1) == 64

        h2 = registry.compute_ruleset_hash()
        assert h1 == h2

        # Register a new rule and verify hash changes
        new_rule = EdgeInferenceRule(
            rule_id="RULE-EDGE-CUSTOM-TEST-01",
            name="Custom Test",
            description="desc",
            source_label="Paper",
            target_label="Technology",
            edge_label="TEST",
            condition_type=RuleConditionType.LEXICAL,
            condition_spec={},
            base_confidence=0.6,
            confidence_tier=ConfidenceTier.MEDIUM,
        )
        registry.register_rule(new_rule)
        h3 = registry.compute_ruleset_hash()
        assert h3 != h1

    def test_builtin_fallback(self) -> None:
        registry = EdgeInferenceRuleRegistry(auto_load=False)
        registry.load_builtin_rules()
        assert len(registry.get_all_rules()) == 16
        assert registry.is_fallback is True
        assert registry.loaded_source == "builtin_fallback"
        assert registry.get_rule("RULE-EDGE-PAPER-TECH-REGEX-01") is not None
        assert registry.get_rule("RULE-EDGE-PAPER-VENUE-PRESENTED-01") is not None

    def test_master_rules_json_and_builtin_fallback_parity(self) -> None:
        json_registry = EdgeInferenceRuleRegistry(
            auto_load=True, custom_path=str(DEFAULT_RULES_PATH), strict=True
        )
        builtin_registry = EdgeInferenceRuleRegistry(auto_load=False)
        builtin_registry.load_builtin_rules()

        json_dicts = [
            r.to_dict()
            for r in sorted(json_registry.get_all_rules(), key=lambda r: r.rule_id)
        ]
        builtin_dicts = [
            r.to_dict()
            for r in sorted(builtin_registry.get_all_rules(), key=lambda r: r.rule_id)
        ]
        assert len(json_dicts) == 16
        assert json_dicts == builtin_dicts
        assert (
            json_registry.compute_ruleset_hash()
            == builtin_registry.compute_ruleset_hash()
        )

    def test_default_load_provenance(self) -> None:
        registry = EdgeInferenceRuleRegistry(auto_load=True)
        assert registry.is_fallback is False
        assert registry.loaded_source.startswith("json:")
        assert registry.ruleset_version == "2026.09.1"

    def test_custom_path_fail_closed_and_atomic_load(self, tmp_path: Path) -> None:
        with pytest.raises(FileNotFoundError):
            EdgeInferenceRuleRegistry(
                auto_load=True,
                custom_path=str(tmp_path / "does_not_exist.json"),
            )

        non_json = tmp_path / "rules.txt"
        non_json.write_text('{"rules": []}', encoding="utf-8")
        with pytest.raises(ValueError, match=r"\.json"):
            EdgeInferenceRuleRegistry(auto_load=True, custom_path=str(non_json))

        # Verify atomic preservation when load_from_json fails on existing registry
        registry = EdgeInferenceRuleRegistry(auto_load=True)
        original_hash = registry.compute_ruleset_hash()
        assert len(registry.get_all_rules()) == 16

        invalid_payloads = [
            "{not-valid-json",
            "[]",
            json.dumps({"version": "2026.09.1", "rules": []}),
            json.dumps(
                {
                    "version": "2026.09.1",
                    "rules": [
                        {
                            "rule_id": "RULE-DUP-01",
                            "name": "One",
                            "description": "d",
                            "source_label": "Paper",
                            "target_label": "CWE",
                            "edge_label": "EXPLOITS_VULNERABILITY",
                            "condition_type": "lexical",
                            "condition_spec": {},
                            "base_confidence": 0.5,
                            "confidence_tier": "MEDIUM",
                        },
                        {
                            "rule_id": "RULE-DUP-01",
                            "name": "Two",
                            "description": "d",
                            "source_label": "Paper",
                            "target_label": "CWE",
                            "edge_label": "EXPLOITS_VULNERABILITY",
                            "condition_type": "lexical",
                            "condition_spec": {},
                            "base_confidence": 0.5,
                            "confidence_tier": "MEDIUM",
                        },
                    ],
                }
            ),
            json.dumps(
                {
                    "version": "2026.09.1",
                    "rules": [
                        {
                            "rule_id": "RULE-REDOS-01",
                            "name": "Bad Regex",
                            "description": "d",
                            "source_label": "Paper",
                            "target_label": "CWE",
                            "edge_label": "EXPLOITS_VULNERABILITY",
                            "condition_type": "regex",
                            "condition_spec": {"pattern": r"([a-z]+)*"},
                            "base_confidence": 0.8,
                            "confidence_tier": "HIGH",
                        }
                    ],
                }
            ),
        ]

        for idx, payload in enumerate(invalid_payloads):
            bad_file = tmp_path / f"bad_{idx}.json"
            bad_file.write_text(payload, encoding="utf-8")
            with pytest.raises(ValueError):
                registry.load_from_json(str(bad_file))
            assert len(registry.get_all_rules()) == 16
            assert registry.compute_ruleset_hash() == original_hash

    def test_default_path_corrupt_fails_closed(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        corrupt_default = tmp_path / "master_rules.json"
        corrupt_default.write_text("{corrupt", encoding="utf-8")
        monkeypatch.setattr(rule_registry_mod, "DEFAULT_RULES_PATH", corrupt_default)

        with pytest.raises(ValueError):
            EdgeInferenceRuleRegistry(auto_load=True, strict=False)

    def test_default_path_missing_fallback_with_warning_and_strict_mode(
        self,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
        caplog: pytest.LogCaptureFixture,
    ) -> None:
        missing_default = tmp_path / "missing_master_rules.json"
        monkeypatch.setattr(rule_registry_mod, "DEFAULT_RULES_PATH", missing_default)

        with caplog.at_level(logging.WARNING, logger="ontology.rule_registry"):
            registry = EdgeInferenceRuleRegistry(auto_load=True, strict=False)

        assert registry.is_fallback is True
        assert registry.loaded_source == "builtin_fallback"
        assert len(registry.get_all_rules()) == 16
        assert any("built-in fallback rules" in rec.message for rec in caplog.records)

        with pytest.raises(FileNotFoundError):
            EdgeInferenceRuleRegistry(auto_load=True, strict=True)


class TestTechniqueInferenceRuleAttribution:
    """Tests for TechniqueInferenceEngine rule attribution output."""

    def test_direct_regex_rule_attribution(self) -> None:
        engine = TechniqueInferenceEngine(min_confidence=0.4)
        title = "Novel Analysis of T1190"
        text = "Abstract describing attacks on public web services."

        results = engine.infer(title=title, text=text)
        assert len(results) > 0

        t1190 = next(r for r in results if r.technique_id == "T1190")
        assert "RULE-EDGE-PAPER-TECH-REGEX-01" in t1190.applied_rules
        assert t1190.primary_rule_id == "RULE-EDGE-PAPER-TECH-REGEX-01"

    def test_title_and_keyword_rule_attribution(self) -> None:
        engine = TechniqueInferenceEngine(min_confidence=0.4)
        title = "Phishing and Credential Harvesting in Modern Clouds"
        text = "We evaluate social engineering vectors and user awareness."

        results = engine.infer(title=title, text=text)
        assert len(results) > 0

        t1566 = next(r for r in results if r.technique_id == "T1566")
        assert t1566.primary_rule_id in (
            "RULE-EDGE-PAPER-TECH-TITLE-02",
            "RULE-EDGE-PAPER-TECH-KEYWORD-03",
        )
        assert any(
            r in t1566.applied_rules
            for r in [
                "RULE-EDGE-PAPER-TECH-TITLE-02",
                "RULE-EDGE-PAPER-TECH-KEYWORD-03",
                "RULE-EDGE-PAPER-TECH-ABSTRACT-04",
            ]
        )

    def test_offensive_modifier_rule_attribution(self) -> None:
        engine = TechniqueInferenceEngine(min_confidence=0.4)
        title = "Exploiting Remote Code Execution and RCE Vulnerabilities"
        text = "We present an offensive proof of concept attack weaponizing zero-day payloads."

        results = engine.infer(title=title, text=text)
        assert len(results) > 0

        top = results[0]
        assert top.research_focus == "offensive"
        assert "RULE-EDGE-FOCUS-OFFENSIVE-01" in top.applied_rules

    def test_serialization_contains_applied_rules(self) -> None:
        tech = InferredTechnique(
            technique_id="T1190",
            technique_name="Exploit Public-Facing Application",
            tactic="initial-access",
            confidence=1.0,
            matched_keywords=["T1190"],
            research_focus="offensive",
            applied_rules=[
                "RULE-EDGE-PAPER-TECH-REGEX-01",
                "RULE-EDGE-FOCUS-OFFENSIVE-01",
            ],
            primary_rule_id="RULE-EDGE-PAPER-TECH-REGEX-01",
        )
        d = tech.to_dict()
        assert d["primary_rule_id"] == "RULE-EDGE-PAPER-TECH-REGEX-01"
        assert len(d["applied_rules"]) == 2
        assert "RULE-EDGE-FOCUS-OFFENSIVE-01" in d["applied_rules"]

    def test_disabled_direct_regex_rule_skips_match(self) -> None:
        registry = EdgeInferenceRuleRegistry(auto_load=True)
        disabled_regex = EdgeInferenceRule(
            rule_id="RULE-EDGE-PAPER-TECH-REGEX-01",
            name="Disabled Direct Regex",
            description="Disabled rule for testing",
            source_label="Paper",
            target_label="AttackTechnique",
            edge_label="TARGETS",
            condition_type=RuleConditionType.REGEX,
            condition_spec={"pattern": r"\b(T\d{4}(?:\.\d{3})?)\b"},
            base_confidence=1.0,
            confidence_tier=ConfidenceTier.HIGH,
            is_active=False,
        )
        registry.register_rule(disabled_regex)
        engine = TechniqueInferenceEngine(min_confidence=0.4, rule_registry=registry)

        results = engine.infer(
            title="Study referencing T1190 directly",
            text="No catalog keywords present in this summary.",
        )
        assert results == []

    def test_custom_registry_weights_and_focus_rule_applied(self) -> None:
        registry = EdgeInferenceRuleRegistry(auto_load=True)
        custom_kw_rule = EdgeInferenceRule(
            rule_id="RULE-EDGE-PAPER-TECH-KEYWORD-03",
            name="Custom Keyword Weight Rule",
            description="Boosted keyword weight",
            source_label="Paper",
            target_label="AttackTechnique",
            edge_label="TARGETS",
            condition_type=RuleConditionType.LEXICAL,
            condition_spec={"target_field": "title", "weight_per_keyword": 0.9},
            base_confidence=0.9,
            confidence_tier=ConfidenceTier.HIGH,
            evidence_spec=EvidenceExtractionSpec(
                target_field="title",
                max_snippet_length=40,
                case_sensitive=False,
            ),
            is_active=True,
        )
        disabled_focus = EdgeInferenceRule(
            rule_id="RULE-EDGE-FOCUS-OFFENSIVE-01",
            name="Offensive Context Modifier",
            description="Disabled offensive modifier",
            source_label="Paper",
            target_label="AttackTechnique",
            edge_label="TARGETS",
            condition_type=RuleConditionType.CONTEXT_RATIO,
            condition_spec={"focus_direction": "offensive", "dominant_factor": 2},
            base_confidence=0.75,
            confidence_tier=ConfidenceTier.MEDIUM,
            is_active=False,
        )
        registry.register_rule(custom_kw_rule)
        registry.register_rule(disabled_focus)

        engine = TechniqueInferenceEngine(min_confidence=0.4, rule_registry=registry)
        results = engine.infer(
            title="Exploiting RCE Vulnerabilities with Offensive PoC Payload",
            text="We demonstrate an attack weaponizing payload delivery.",
        )
        assert len(results) > 0
        t1190 = next(r for r in results if r.technique_id == "T1190")
        assert t1190.confidence == pytest.approx(0.9)
        assert "RULE-EDGE-FOCUS-OFFENSIVE-01" not in t1190.applied_rules
        kw_ev = next(
            ev
            for ev in t1190.evidences
            if ev.rule_id == "RULE-EDGE-PAPER-TECH-KEYWORD-03"
        )
        assert kw_ev.rule_name == "Custom Keyword Weight Rule"
        assert kw_ev.score_contribution == pytest.approx(0.9)
        assert len(kw_ev.snippet) <= 40
