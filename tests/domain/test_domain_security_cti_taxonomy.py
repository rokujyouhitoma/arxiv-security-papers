#!/usr/bin/env python3
"""
Unit tests for Domain Security Layer (Issue 151).
Verifies that CTI and Taxonomy reside in domain.security and that
backward-compatibility shims in security.cti and security.taxonomy
seamlessly preserve object identity, typing, and functions.
"""

import security.cti as legacy_cti
import security.taxonomy as legacy_taxonomy
from domain.security import SecurityPapersDomainPlugin, create_security_plugin
from domain.security.cti import (
    CTICatalogStorage,
    CTISyncManager,
    MITRECTIRegistry,
    STIXCTIParser,
)
from domain.security.taxonomy import (
    CWE_DEFENSE_MAP,
    MITRE_TECHNIQUES_MAP,
    STRIDE_CATEGORIES_MAP,
    extract_mitre_techniques,
    extract_stride_categories,
    generate_caldera_ability,
    generate_sigma_rule,
    get_cwe_recipe,
    get_technique_meta,
)


def test_domain_security_plugin_cti_access() -> None:
    """Verifies that SecurityPapersDomainPlugin exposes the CTI Registry."""
    plugin = create_security_plugin()
    assert isinstance(plugin, SecurityPapersDomainPlugin)
    reg = plugin.get_cti_registry()
    assert reg is MITRECTIRegistry.get_instance()
    assert reg.get_technique("T1059") is not None


def test_domain_cti_exports_and_shim_identity() -> None:
    """Verifies that legacy security.cti shims point directly to domain.security.cti."""
    assert legacy_cti.CTICatalogStorage is CTICatalogStorage
    assert legacy_cti.CTISyncManager is CTISyncManager
    assert legacy_cti.MITRECTIRegistry is MITRECTIRegistry
    assert legacy_cti.STIXCTIParser is STIXCTIParser


def test_domain_taxonomy_exports_and_shim_identity() -> None:
    """Verifies that legacy security.taxonomy shims point directly to domain.security.taxonomy."""
    assert legacy_taxonomy.CWE_DEFENSE_MAP is CWE_DEFENSE_MAP
    assert legacy_taxonomy.MITRE_TECHNIQUES_MAP is MITRE_TECHNIQUES_MAP
    assert legacy_taxonomy.STRIDE_CATEGORIES_MAP is STRIDE_CATEGORIES_MAP
    assert legacy_taxonomy.extract_mitre_techniques is extract_mitre_techniques
    assert legacy_taxonomy.extract_stride_categories is extract_stride_categories
    assert legacy_taxonomy.generate_caldera_ability is generate_caldera_ability
    assert legacy_taxonomy.generate_sigma_rule is generate_sigma_rule
    assert legacy_taxonomy.get_cwe_recipe is get_cwe_recipe
    assert legacy_taxonomy.get_technique_meta is get_technique_meta


def test_domain_cti_and_taxonomy_functionality() -> None:
    """Verifies domain taxonomy and CTI functions operate correctly."""
    recipe = get_cwe_recipe("CWE-89")
    assert recipe is not None
    assert recipe["name"] == "SQL Injection"

    stride_cats = extract_stride_categories(
        "adversary executed spoofing and ddos attack"
    )
    assert "Spoofing" in stride_cats
    assert "Denial of Service" in stride_cats

    techniques = extract_mitre_techniques("Adversary used T1059 for command execution")
    assert "T1059" in techniques

    meta = get_technique_meta("T1059")
    assert meta["name"] == "Command and Scripting Interpreter"
