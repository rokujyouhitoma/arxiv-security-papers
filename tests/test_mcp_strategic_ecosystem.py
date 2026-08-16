#!/usr/bin/env python3
"""
Unit tests for MCP Strategic Ecosystem Expansion (Phase 1, 2, 3 - DSN-12).
Verifies:
1. Phase 1: Two-Stage Compact retrieval & token optimization in mcp_server.py
2. Phase 2: Semgrep rule synthesis, secure patch generation, and threat coverage in threat_defense_mcp_server.py
3. Phase 3: Tech-Radar quadrants and emerging threat forecasting in tech_radar_mcp_server.py
"""

import os
import sys

if "src" not in sys.path:
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

import pytest
from mcp_server import handle_search_security_papers, handle_search_papers_hybrid
from threat_defense_mcp_server import (
    handle_generate_semgrep_rule,
    handle_synthesize_secure_patch,
    handle_check_threat_coverage,
)
from tech_radar_mcp_server import (
    handle_get_technology_radar,
    handle_predict_emerging_threats,
)


# ---------------------------------------------------------------------------
# Phase 1: Two-Stage Compact Retrieval Tests
# ---------------------------------------------------------------------------

def test_phase1_compact_search_reduces_token_payload(monkeypatch):
    """Verify compact mode returns stripped summary fields to conserve AI context."""
    # Mock get_vector_engine
    class MockEngine:
        def search(self, query, top_k=5, category=None):
            return [{
                "id": "2608.12345",
                "title": "Quantum Resistance in Lattice Cryptography",
                "title_ja": "格子暗号における耐量子性",
                "category": "cryptography",
                "tags": ["crypto", "pqc", "lattice"],
                "score": 0.9523,
                "description": "Short executive summary.",
                "abstract": "A very long abstract text that consumes hundreds of tokens...",
                "content": "Full extracted paper markdown with thousands of characters...",
            }]

    from mcp_server import get_vector_engine
    monkeypatch.setattr("mcp_server.get_vector_engine", lambda: MockEngine())

    # Compact search
    res = handle_search_security_papers({"query": "quantum", "compact": True})
    assert res["status"] == "success"
    assert res["compact"] is True
    assert len(res["results"]) == 1

    doc = res["results"][0]
    assert "id" in doc
    assert "title" in doc
    assert "summary" in doc
    assert "abstract" not in doc  # Stripped for token savings
    assert "content" not in doc   # Stripped for token savings


# ---------------------------------------------------------------------------
# Phase 2: Threat Defense & Patch Synthesis Tests
# ---------------------------------------------------------------------------

def test_phase2_generate_semgrep_rule():
    """Verify Semgrep YAML rule synthesis from CWE-502."""
    res = handle_generate_semgrep_rule({"cwe_id": "CWE-502"})
    assert res["status"] == "success"
    assert res["cwe_id"] == "CWE-502"
    yaml_text = res["semgrep_yaml"]
    assert "rules:" in yaml_text
    assert "CWE-502" in yaml_text
    assert "pickle.loads" in yaml_text or "yaml.load" in yaml_text


def test_phase2_synthesize_secure_patch_pickle():
    """Verify automated secure patch recommendation for unsafe pickle loading."""
    vuln_code = "import pickle\ndata = pickle.loads(raw_bytes)"
    res = handle_synthesize_secure_patch({"code": vuln_code, "cwe_id": "CWE-502"})
    assert res["status"] == "success"
    assert "json.loads" in res["suggested_patch"]
    assert "import json" in res["suggested_patch"]


def test_phase2_check_threat_coverage_scoring():
    """Verify MITRE/NIST defense coverage scoring."""
    defenses = ["pickle-free", "ast-guard", "zero-dependency", "commonpath-traversal-guard"]
    res = handle_check_threat_coverage({"declared_defenses": defenses})
    assert res["status"] == "success"
    assert res["coverage_score"] >= 0.8
    assert res["rating"] == "A+ (Excellent)"
    assert len(res["breakdown"]) == 5


# ---------------------------------------------------------------------------
# Phase 3: Tech-Radar & Threat Forecast Tests
# ---------------------------------------------------------------------------

def test_phase3_get_technology_radar_filtering():
    """Verify Tech-Radar extraction and ring categorization."""
    res = handle_get_technology_radar({"ring": "adopt"})
    assert res["status"] == "success"
    assert "adopt" in res["radar"]
    assert "trial" not in res["radar"]
    assert len(res["radar"]["adopt"]) >= 3

    # Check Markdown report generated
    assert "# 🛡️ Security Technology Radar" in res["markdown_report"]


def test_phase3_predict_emerging_threats():
    """Verify emerging threat prediction output."""
    res = handle_predict_emerging_threats({"min_severity": "HIGH"})
    assert res["status"] == "success"
    assert res["threat_count"] >= 3
    for threat in res["forecasts"]:
        assert threat["severity"] in ("CRITICAL", "HIGH")
        assert "threat_id" in threat
        assert "mitigation" in threat
