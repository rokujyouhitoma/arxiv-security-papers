#!/usr/bin/env python3
"""
Unit tests for Security Knowledge Ontology (SKO) Schema and Taxonomy Registry.
"""

from ontology.extractor import OntologyExtractor
from ontology.schema import (
    AttackTechniqueEntity,
    DefenseMechanismEntity,
    EntityType,
    PaperEntity,
    Predicate,
    SecurityOntologySchema,
    TargetAssetEntity,
    VulnerabilityEntity,
)
from ontology.taxonomy import TaxonomyRegistry


def test_ontology_entities_creation() -> None:
    paper = PaperEntity(
        id="Paper:2608.01234",
        entity_type=EntityType.PAPER,
        name="Adversarial LLM Attacks",
        arxiv_id="2608.01234",
        title_ja="LLMへの敵対的攻撃",
    )
    assert paper.id == "Paper:2608.01234"
    assert paper.entity_type == EntityType.PAPER

    attack = AttackTechniqueEntity(
        id="AttackTechnique:Prompt_Injection",
        entity_type=EntityType.ATTACK_TECHNIQUE,
        name="Prompt Injection",
        technique_id="T1059",
    )
    assert attack.id == "AttackTechnique:Prompt_Injection"
    assert attack.technique_id == "T1059"

    vuln = VulnerabilityEntity(
        id="Vulnerability:CWE-79",
        entity_type=EntityType.VULNERABILITY,
        name="CWE-79",
        cwe_id="CWE-79",
    )
    assert vuln.cwe_id == "CWE-79"

    defense = DefenseMechanismEntity(
        id="DefenseMechanism:ZKP",
        entity_type=EntityType.DEFENSE_MECHANISM,
        name="Zero-Knowledge Proofs",
        category="ZKP",
    )
    assert defense.category == "ZKP"

    asset = TargetAssetEntity(
        id="TargetAsset:LLM",
        entity_type=EntityType.TARGET_ASSET,
        name="LLM",
        asset_type="LLM",
    )
    assert asset.asset_type == "LLM"


def test_predicate_inverses_and_validation() -> None:
    assert Predicate.DISCLOSES.inverse == "DISCLOSED_IN"
    assert Predicate.EXPLOITS.inverse == "EXPLOITED_BY"
    assert Predicate.MITIGATES.inverse == "MITIGATED_BY"
    assert Predicate.PATCHES.inverse == "PATCHED_BY"
    assert Predicate.PROPOSES.inverse == "PROPOSED_IN"

    # Schema validation
    assert SecurityOntologySchema.validate_triple(EntityType.PAPER, Predicate.DISCLOSES)
    assert SecurityOntologySchema.validate_triple(EntityType.PAPER, Predicate.PROPOSES)
    assert SecurityOntologySchema.validate_triple(
        EntityType.ATTACK_TECHNIQUE, Predicate.EXPLOITS
    )
    assert SecurityOntologySchema.validate_triple(
        EntityType.DEFENSE_MECHANISM, Predicate.MITIGATES
    )

    # Invalid relationship check
    assert not SecurityOntologySchema.validate_triple(
        EntityType.PAPER, Predicate.EXPLOITS
    )


def test_taxonomy_registry_normalization() -> None:
    # LLM synonyms
    res1 = TaxonomyRegistry.normalize_term("jailbreak")
    assert res1 is not None
    assert res1[0] == "AttackTechnique:Prompt_Injection"

    res2 = TaxonomyRegistry.normalize_term("adversarial prompt")
    assert res2 is not None
    assert res2[0] == "AttackTechnique:Prompt_Injection"

    # Crypto / Side-channel
    res3 = TaxonomyRegistry.normalize_term("power analysis")
    assert res3 is not None
    assert res3[0] == "AttackTechnique:Side_Channel_Analysis"

    # CWE regex
    res4 = TaxonomyRegistry.normalize_term("Analysis of CWE-89 in web apps")
    assert res4 is not None
    assert res4[0] == "Vulnerability:CWE-89"


def test_ontology_extractor_from_markdown() -> None:
    sample_md = """---
type: security-paper
title: "Breaking LLM Guards with Prompt Injection and Mitigations via ZKP"
description: "プロンプトインジェクション攻撃の実証とZKPによる防御"
tags:
  - prompt injection
  - zkp
  - llm
  - CWE-79
---
# Breaking LLM Guards

We demonstrate prompt injection against LLM models targeting CWE-79.
We propose a novel ZKP defense mechanism.
"""
    entities, triples = OntologyExtractor.extract_from_okf("2608.99999", sample_md)

    # Check extracted entities
    entity_ids = {e.id for e in entities}
    assert "Paper:2608.99999" in entity_ids
    assert "AttackTechnique:Prompt_Injection" in entity_ids
    assert "Vulnerability:CWE-79" in entity_ids
    assert "DefenseMechanism:Zero_Knowledge_Proof" in entity_ids
    assert "TargetAsset:Large_Language_Model" in entity_ids

    # Check extracted triples
    triple_tuples = {(t.subject_id, t.predicate.value, t.object_id) for t in triples}
    assert (
        "Paper:2608.99999",
        "ANALYZES",
        "AttackTechnique:Prompt_Injection",
    ) in triple_tuples
    assert ("Paper:2608.99999", "DISCLOSES", "Vulnerability:CWE-79") in triple_tuples
    assert (
        "Paper:2608.99999",
        "PROPOSES",
        "DefenseMechanism:Zero_Knowledge_Proof",
    ) in triple_tuples
    assert (
        "DefenseMechanism:Zero_Knowledge_Proof",
        "MITIGATES",
        "AttackTechnique:Prompt_Injection",
    ) in triple_tuples
