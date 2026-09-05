#!/usr/bin/env python3
"""
Unit and Integration Tests for MITRE ATT&CK CTI Ingestion Pipeline.
Tests STIX parsing, SQLite catalog storage, Registry fallback,
and integration with taxonomy, ontology seeder, and MCP tools.
Pure Python, Zero External Dependencies.
"""

import os
import tempfile
from typing import Any, Dict

from graph.engine import PropertyGraphEngine
from mcp.threat_defense_server import handle_search_mitre_cti
from ontology.seeder import seed_ontology_from_cti
from security.cti.parser import STIXCTIParser
from security.cti.registry import MITRECTIRegistry
from security.cti.storage import CTICatalogStorage
from security.cti.sync import CTISyncManager
from security.taxonomy.mitre import (
    extract_mitre_techniques,
    generate_caldera_ability,
    generate_sigma_rule,
    get_technique_meta,
)

SAMPLE_STIX_BUNDLE: Dict[str, Any] = {
    "type": "bundle",
    "id": "bundle--test-cti-001",
    "spec_version": "2.0",
    "objects": [
        {
            "type": "x-mitre-tactic",
            "id": "x-mitre-tactic--ta0002",
            "name": "Execution",
            "x_mitre_shortname": "execution",
            "description": "Adversary tries to run malicious code.",
            "external_references": [
                {
                    "source_name": "mitre-attack",
                    "external_id": "TA0002",
                    "url": "https://attack.mitre.org/tactics/TA0002",
                }
            ],
        },
        {
            "type": "attack-pattern",
            "id": "attack-pattern--t1059",
            "name": "Command and Scripting Interpreter",
            "description": "Adversaries abuse command and script interpreters.",
            "x_mitre_platforms": ["Linux", "macOS", "Windows"],
            "kill_chain_phases": [
                {"kill_chain_name": "mitre-attack", "phase_name": "execution"}
            ],
            "external_references": [
                {
                    "source_name": "mitre-attack",
                    "external_id": "T1059",
                    "url": "https://attack.mitre.org/techniques/T1059",
                }
            ],
        },
        {
            "type": "attack-pattern",
            "id": "attack-pattern--t1059-001",
            "name": "PowerShell",
            "description": "Adversaries abuse PowerShell commands and scripts.",
            "x_mitre_is_subtechnique": True,
            "x_mitre_platforms": ["Windows"],
            "kill_chain_phases": [
                {"kill_chain_name": "mitre-attack", "phase_name": "execution"}
            ],
            "external_references": [
                {
                    "source_name": "mitre-attack",
                    "external_id": "T1059.001",
                    "url": "https://attack.mitre.org/techniques/T1059/001",
                }
            ],
        },
        {
            "type": "course-of-action",
            "id": "course-of-action--m1038",
            "name": "Execution Prevention",
            "description": "Block execution of untrusted software or scripts.",
            "external_references": [
                {
                    "source_name": "mitre-attack",
                    "external_id": "M1038",
                    "url": "https://attack.mitre.org/mitigations/M1038",
                }
            ],
        },
        {
            "type": "relationship",
            "id": "relationship--rel-subtech",
            "relationship_type": "subtechnique-of",
            "source_ref": "attack-pattern--t1059-001",
            "target_ref": "attack-pattern--t1059",
        },
        {
            "type": "relationship",
            "id": "relationship--rel-mitigate",
            "relationship_type": "mitigates",
            "source_ref": "course-of-action--m1038",
            "target_ref": "attack-pattern--t1059",
        },
        {
            "type": "attack-pattern",
            "id": "attack-pattern--revoked",
            "name": "Revoked Old Technique",
            "revoked": True,
            "external_references": [
                {"source_name": "mitre-attack", "external_id": "T9999"}
            ],
        },
    ],
}


def test_stix_parser() -> None:
    parser = STIXCTIParser()
    tactics, techniques, mitigations, rels = parser.parse_bundle(SAMPLE_STIX_BUNDLE)

    assert len(tactics) == 1
    assert tactics[0]["tactic_id"] == "TA0002"
    assert tactics[0]["shortname"] == "execution"

    assert len(techniques) == 2
    tech_ids = {t["technique_id"] for t in techniques}
    assert "T1059" in tech_ids
    assert "T1059.001" in tech_ids
    assert "T9999" not in tech_ids  # Revoked should be filtered out

    sub = next(t for t in techniques if t["technique_id"] == "T1059.001")
    assert sub["is_subtechnique"] is True
    assert sub["parent_technique_id"] == "T1059"

    assert len(mitigations) == 1
    assert mitigations[0]["mitigation_id"] == "M1038"

    assert len(rels) == 2
    assert ("T1059.001", "T1059", "subtechnique-of") in rels
    assert ("M1038", "T1059", "mitigates") in rels


def test_storage_and_sync() -> None:
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        db_path = tmp.name

    try:
        storage = CTICatalogStorage(db_path=db_path)
        sync_mgr = CTISyncManager(storage=storage)

        summary = sync_mgr.sync_from_bundle(SAMPLE_STIX_BUNDLE)
        assert summary["tactics"] == 1
        assert summary["techniques"] == 2
        assert summary["mitigations"] == 1
        assert summary["relationships"] == 2

        counts = storage.count_summary()
        assert counts["techniques"] == 2
        assert counts["mitigations"] == 1

        tech = storage.get_technique("T1059.001")
        assert tech is not None
        assert tech["name"] == "PowerShell"
        assert tech["is_subtechnique"] is True
        assert tech["parent_technique_id"] == "T1059"

        all_techs = storage.get_all_techniques()
        assert len(all_techs) == 2

        by_tactic = storage.get_techniques_by_tactic("execution")
        assert len(by_tactic) == 2

        mits = storage.get_mitigations_for_technique("T1059")
        assert len(mits) == 1
        assert mits[0]["mitigation_id"] == "M1038"

        search_res = storage.search_techniques("powershell")
        assert len(search_res) >= 1
        assert search_res[0]["technique_id"] == "T1059.001"
    finally:
        if os.path.exists(db_path):
            os.remove(db_path)


def test_registry_fallback() -> None:
    non_existent_db = "/tmp/test_non_existent_catalog_db_9999.db"
    if os.path.exists(non_existent_db):
        os.remove(non_existent_db)

    storage = CTICatalogStorage(db_path=non_existent_db)
    # Empty DB
    registry = MITRECTIRegistry(storage=storage)
    assert not registry.is_populated()

    # Should fallback to builtin definitions
    tech = registry.get_technique("T1059")
    assert tech is not None
    assert tech["name"] == "Command and Scripting Interpreter"

    all_t = registry.get_all_techniques()
    assert "T1059" in all_t
    assert "T1190" in all_t

    searched = registry.search("phishing")
    assert any(s["technique_id"] == "T1566" for s in searched)

    if os.path.exists(non_existent_db):
        os.remove(non_existent_db)


def test_mitre_taxonomy_integration() -> None:
    meta = get_technique_meta("T1059")
    assert meta["name"] == "Command and Scripting Interpreter"

    extracted = extract_mitre_techniques(
        "We observed adversary executing T1059.001 powershell commands and credential stuffing."
    )
    assert "T1059.001" in extracted
    assert "T1078" in extracted

    caldera = generate_caldera_ability("T1059")
    assert "Emulate Command and Scripting Interpreter" in caldera
    assert 'tactic: "execution"' in caldera

    sigma = generate_sigma_rule("T1190")
    assert "attack.t1190" in sigma


def test_ontology_seeder_integration() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        engine = PropertyGraphEngine(workspace_dir=tmp_dir, memory_only=True)
        v_count, e_count = seed_ontology_from_cti(engine, limit=10)
        assert v_count > 0
        stats = engine.stats()
        assert stats["vertex_count"] > 0


def test_mcp_search_mitre_cti() -> None:
    res = handle_search_mitre_cti({"query": "T1059"})
    assert res["status"] == "success"
    assert res["count"] >= 1
    assert any(r["technique_id"] == "T1059" for r in res["results"])

    empty_res = handle_search_mitre_cti({"query": ""})
    assert empty_res["status"] == "error"


def test_attack_technique_extractor_cti_integration() -> None:
    from ontology.primus.ate import AttackTechniqueExtractor

    recs = AttackTechniqueExtractor.extract_techniques(
        "Attackers used credential stuffing against login portals."
    )
    ids = [r.mapped_id for r in recs]
    assert "T1078" in ids
