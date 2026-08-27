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
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )

from mcp.papers_server import handle_search_security_papers
from mcp.tech_radar_server import (
    handle_get_technology_radar,
    handle_predict_emerging_threats,
)
from mcp.threat_defense_server import (
    handle_check_threat_coverage,
    handle_generate_semgrep_rule,
    handle_synthesize_secure_patch,
)

# ---------------------------------------------------------------------------
# Phase 1: Two-Stage Compact Retrieval Tests
# ---------------------------------------------------------------------------


def test_phase1_compact_search_reduces_token_payload(monkeypatch):
    """Verify compact mode returns stripped summary fields to conserve AI context."""

    # Mock get_vector_engine
    class MockEngine:
        def search(self, query, top_k=5, category=None):
            return [
                {
                    "id": "2608.12345",
                    "title": "Quantum Resistance in Lattice Cryptography",
                    "title_ja": "格子暗号における耐量子性",
                    "category": "cryptography",
                    "tags": ["crypto", "pqc", "lattice"],
                    "score": 0.9523,
                    "description": "Short executive summary.",
                    "abstract": "A very long abstract text that consumes hundreds of tokens...",
                    "content": "Full extracted paper markdown with thousands of characters...",
                }
            ]

    monkeypatch.setattr("mcp.papers_server.get_vector_engine", lambda: MockEngine())

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
    assert "content" not in doc  # Stripped for token savings


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
    defenses = [
        "pickle-free",
        "ast-guard",
        "zero-dependency",
        "commonpath-traversal-guard",
    ]
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
    res = handle_predict_emerging_threats(
        {"min_severity": "HIGH", "offset": 0, "limit": 2}
    )
    assert res["status"] == "success"
    assert res["threat_count"] <= 2
    assert "pagination" in res
    assert res["pagination"]["limit"] == 2
    for threat in res["forecasts"]:
        assert threat["severity"] in ("CRITICAL", "HIGH")
        assert "threat_id" in threat
        assert "mitigation" in threat


def test_phase4_emerging_threat_patches():
    """Verify Slopsquatting (CWE-1357) and EOP (CWE-693) patch generation."""
    code_slop = "import some_hallucinated_package"
    res_slop = handle_synthesize_secure_patch({"code": code_slop, "cwe_id": "CWE-1357"})
    assert res_slop["status"] == "success"
    assert "pin dependencies with hashes" in res_slop["suggested_patch"]

    code_eop = "import torch\nweights = torch.load('model.pt')"
    res_eop = handle_synthesize_secure_patch({"code": code_eop, "cwe_id": "CWE-693"})
    assert res_eop["status"] == "success"
    assert "safetensors" in res_eop["suggested_patch"]


def test_papers_hybrid_search_and_prompt(monkeypatch):
    """Verify hybrid search pagination and audit prompt generation."""
    from mcp.papers_server import handle_get_prompt, handle_search_papers_hybrid

    class MockEngine:
        def search_hybrid_pipeline(self, query, facets=None, top_k=10):
            return {
                "results": [
                    {
                        "id": f"2608.0000{i}",
                        "title": f"Paper {i}",
                        "title_ja": f"論文 {i}",
                        "category": "cs.CR",
                        "score": 0.9 - i * 0.05,
                        "description": "Abstract snippet",
                    }
                    for i in range(5)
                ]
            }

    monkeypatch.setattr("mcp.papers_server.get_vector_engine", lambda: MockEngine())

    res = handle_search_papers_hybrid({"query": "zero trust", "offset": 1, "limit": 2})
    assert res["status"] == "success"
    assert len(res["results"]) == 2
    assert res["pagination"]["offset"] == 1
    assert res["pagination"]["limit"] == 2
    assert res["pagination"]["has_more"] is True

    prompt_res = handle_get_prompt(
        "audit_code_with_papers", {"code": "eval(user_input)", "language": "python"}
    )
    assert "description" in prompt_res
    assert len(prompt_res["messages"]) == 1
