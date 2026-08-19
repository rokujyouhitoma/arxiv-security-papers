#!/usr/bin/env python3
"""Taxonomy, Threat Models & Defense Knowledge Base Package."""

from .cwe import CWE_DEFENSE_MAP, get_cwe_recipe
from .mitre import MITRE_TECHNIQUES_MAP, extract_mitre_techniques
from .stride import STRIDE_CATEGORIES_MAP, extract_stride_categories

__all__ = [
    "CWE_DEFENSE_MAP",
    "MITRE_TECHNIQUES_MAP",
    "STRIDE_CATEGORIES_MAP",
    "extract_mitre_techniques",
    "extract_stride_categories",
    "get_cwe_recipe",
]
