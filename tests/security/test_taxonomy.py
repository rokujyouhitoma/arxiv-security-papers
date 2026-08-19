#!/usr/bin/env python3
"""
Unit tests for MITRE ATT&CK, STRIDE, and CWE Taxonomies.
"""

import os
import sys

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    )

from security.taxonomy import (
    extract_mitre_techniques,
    extract_stride_categories,
    get_cwe_recipe,
)


def test_cwe_recipes_and_definitions():
    cwe_94 = get_cwe_recipe("CWE-94")
    assert cwe_94 is not None
    assert cwe_94["name"] == "Code Injection"
    assert "eval" in cwe_94["semgrep_pattern"]

    cwe_89 = get_cwe_recipe("89")  # Without prefix
    assert cwe_89 is not None
    assert cwe_89["name"] == "SQL Injection"


def test_extract_mitre_techniques():
    sample_text = "We analyzed remote code execution and exploit public-facing application vulnerabilities in IoT devices."
    techniques = extract_mitre_techniques(sample_text)
    assert "T1190" in techniques

    phishing_text = (
        "Spearphishing and social engineering attacks targeting enterprise users."
    )
    phishing_techs = extract_mitre_techniques(phishing_text)
    assert "T1566" in phishing_techs


def test_extract_stride_categories():
    sample_text = "The attack causes severe denial of service through resource exhaustion and memory corruption."
    stride = extract_stride_categories(sample_text)
    assert "Denial of Service" in stride
    assert "Tampering" in stride

    empty_stride = extract_stride_categories("")
    assert empty_stride == []
