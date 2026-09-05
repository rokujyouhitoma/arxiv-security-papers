#!/usr/bin/env python3
"""
Unit and integration tests for MITRE ATT&CK Mitigation mapping and Defense Signatures.
Tests CTIStorage, MITRECTIRegistry, and MCP threat_defense_server integration (Issue 152).
"""

import pytest

from domain.security.cti.registry import MITRECTIRegistry
from domain.security.cti.storage import CTICatalogStorage
from mcp.threat_defense_server import (
    handle_generate_sigma_rule,
    handle_get_mitigations_for_threat,
)


def test_cti_storage_get_mitigations_for_technique() -> None:
    """Verifies that CTICatalogStorage resolves mitigations mapped to techniques."""
    storage = CTICatalogStorage()
    if not storage.count_summary().get("techniques", 0):
        pytest.skip("CTI catalog database is unpopulated in this environment.")

    # T1059 Command and Scripting Interpreter usually has M1038 / M1049 mitigations
    mitigations = storage.get_mitigations_for_technique("T1059")
    assert isinstance(mitigations, list)
    if mitigations:
        m0 = mitigations[0]
        assert "mitigation_id" in m0
        assert "name" in m0
        assert "description" in m0
        assert m0["mitigation_id"].startswith("M")


def test_cti_storage_subtechnique_mitigation_inheritance() -> None:
    """Verifies that subtechniques inherit or retrieve parent technique mitigations."""
    storage = CTICatalogStorage()
    if not storage.count_summary().get("techniques", 0):
        pytest.skip("CTI catalog database is unpopulated in this environment.")

    # Subtechnique T1059.001 (PowerShell) should resolve T1059.001 or parent T1059 mitigations
    mits = storage.get_mitigations_for_technique("T1059.001")
    assert isinstance(mits, list)
    assert len(mits) > 0
    mit_ids = [m["mitigation_id"] for m in mits]
    assert any(mid.startswith("M") for mid in mit_ids)


def test_registry_get_mitigations_with_fallback() -> None:
    """Verifies that MITRECTIRegistry returns mitigations even from builtin fallback."""
    registry = MITRECTIRegistry.get_instance()
    mits_t1059 = registry.get_mitigations_for_technique("T1059")
    assert isinstance(mits_t1059, list)
    assert len(mits_t1059) > 0

    mits_t1190 = registry.get_mitigations_for_technique("T1190")
    assert isinstance(mits_t1190, list)
    assert len(mits_t1190) > 0


def test_mcp_handle_get_mitigations_for_threat() -> None:
    """Verifies the new MCP tool get_mitigations_for_threat."""
    # 1. Success case
    resp = handle_get_mitigations_for_threat({"technique_id": "T1059"})
    assert resp["status"] == "success"
    assert resp["technique_id"] == "T1059"
    assert "technique_name" in resp
    assert resp["mitigation_count"] >= 1
    assert isinstance(resp["mitigations"], list)

    # 2. Missing parameter error
    err_resp = handle_get_mitigations_for_threat({})
    assert err_resp["status"] == "error"
    assert "Missing required parameter" in err_resp["message"]


def test_mcp_handle_generate_sigma_rule_includes_mitigations() -> None:
    """Verifies that generate_sigma_rule enriches rule output with recommended mitigations."""
    resp = handle_generate_sigma_rule({"tech_id": "T1059"})
    assert resp["status"] == "success"
    assert "sigma_rule_yaml" in resp
    assert "mitigations" in resp
    assert isinstance(resp["mitigations"], list)
    assert len(resp["mitigations"]) > 0
