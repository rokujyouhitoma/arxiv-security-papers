#!/usr/bin/env python3
"""Backward-compatibility shim for domain.security.taxonomy."""

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

__all__ = [
    "CWE_DEFENSE_MAP",
    "MITRE_TECHNIQUES_MAP",
    "STRIDE_CATEGORIES_MAP",
    "extract_mitre_techniques",
    "extract_stride_categories",
    "generate_caldera_ability",
    "generate_sigma_rule",
    "get_cwe_recipe",
    "get_technique_meta",
]
