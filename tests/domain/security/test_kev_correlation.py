#!/usr/bin/env python3
"""
Comprehensive unit and integration tests for CISA KEV dynamic correlation.
Verifies registry lookups, offline fallbacks, ontology extraction, RDF Turtle serialization,
and MCP threat defense tools (Issue #197).
"""

from __future__ import annotations

from domain.security.cti.kev import BUILTIN_KEV_FALLBACK, CISAKEVRegistry
from domain.security.cti.storage import CTICatalogStorage
from mcp.threat_defense_server import (
    handle_check_cve_kev_status,
    handle_list_active_exploited_papers,
)
from ontology.extractor import OntologyExtractor
from ontology.schema import EntityType, Predicate, VulnerabilityEntity
from ontology.turtle_engine import serialize_vulnerability_entity


class TestCISAKEVRegistry:
    """Tests for CISAKEVRegistry catalog lookups and SSRF validation."""

    def test_builtin_fallback_lookup(self) -> None:
        storage = CTICatalogStorage(db_path=":memory:")
        registry = CISAKEVRegistry(storage=storage, auto_seed=True)

        entry = registry.lookup("CVE-2021-44228")
        assert entry is not None
        assert entry.cve_id == "CVE-2021-44228"
        assert entry.vendor_project == "Apache"
        assert entry.product == "Log4j"
        assert entry.is_ransomware_related is True
        assert "JNDI" in entry.short_description

    def test_case_insensitive_and_nonexistent_lookup(self) -> None:
        registry = CISAKEVRegistry(storage=CTICatalogStorage(db_path=":memory:"))
        assert registry.lookup("cve-2017-0144") is not None
        assert registry.lookup("CVE-2099-00000") is None
        assert registry.lookup("") is None

    def test_search_and_ransomware_filter(self) -> None:
        registry = CISAKEVRegistry(storage=CTICatalogStorage(db_path=":memory:"))
        results = registry.search(query="Spring", limit=10)
        assert any(r.cve_id == "CVE-2022-22965" for r in results)

        ransomware_entries = registry.search(ransomware_only=True, limit=50)
        assert len(ransomware_entries) > 0
        for r in ransomware_entries:
            assert r.is_ransomware_related is True

    def test_ssrf_feed_url_validation(self) -> None:
        assert (
            CISAKEVRegistry.validate_feed_url(
                "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
            )
            is True
        )
        assert (
            CISAKEVRegistry.validate_feed_url(
                "http://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
            )
            is False
        )
        assert (
            CISAKEVRegistry.validate_feed_url(
                "https://malicious.attacker.com/evil.json"
            )
            is False
        )
        assert CISAKEVRegistry.validate_feed_url("file:///etc/passwd") is False

    def test_stats_metrics(self) -> None:
        registry = CISAKEVRegistry(storage=CTICatalogStorage(db_path=":memory:"))
        stats = registry.get_stats()
        assert stats["total_kev_vulnerabilities"] >= len(BUILTIN_KEV_FALLBACK)
        assert stats["ransomware_associated_count"] >= 1


class TestOntologyKEVCorrelation:
    """Tests for OKF paper CVE extraction and KEV binding."""

    SAMPLE_OKF_MARKDOWN = """---
title: "Analyzing Enterprise Logging Vulnerabilities"
description: "Empirical study of remote code execution in Log4j and legacy SMB protocols."
tags:
  - java-security
  - log4j
---
# Introduction
We evaluate the exploitation mechanisms of CVE-2021-44228 (Log4Shell) and CVE-2017-0144 (EternalBlue).
Additionally, we examine an unconfirmed proof-of-concept CVE-2025-11111 for academic comparison.
"""

    def test_extract_cve_entities_with_kev(self) -> None:
        entities, triples = OntologyExtractor.extract_from_okf(
            "2112.00001", self.SAMPLE_OKF_MARKDOWN
        )

        vuln_entities = [e for e in entities if isinstance(e, VulnerabilityEntity)]
        vuln_map = {v.cve_id: v for v in vuln_entities}

        assert "CVE-2021-44228" in vuln_map
        log4j_vuln = vuln_map["CVE-2021-44228"]
        assert log4j_vuln.is_known_exploited is True
        assert log4j_vuln.severity == "Critical"
        assert log4j_vuln.known_ransomware_campaign_use == "Known"
        assert log4j_vuln.cisa_date_added == "2021-12-10"

        assert "CVE-2025-11111" in vuln_map
        unconfirmed_vuln = vuln_map["CVE-2025-11111"]
        assert unconfirmed_vuln.is_known_exploited is False
        assert unconfirmed_vuln.severity == "High"

        verifies_triples = [t for t in triples if t.predicate == Predicate.VERIFIES_CVE]
        verified_targets = {t.object_id for t in verifies_triples}
        assert "Vulnerability:CVE-2021-44228" in verified_targets
        assert "Vulnerability:CVE-2017-0144" in verified_targets
        assert "Vulnerability:CVE-2025-11111" not in verified_targets


class TestTurtleKEVSerialization:
    """Tests for W3C Turtle RDF output containing KEV properties."""

    def test_serialize_vulnerability_with_kev(self) -> None:
        vuln = VulnerabilityEntity(
            id="Vulnerability:CVE-2021-44228",
            entity_type=EntityType.VULNERABILITY,
            name="Apache Log4j Remote Code Execution",
            cve_id="CVE-2021-44228",
            severity="Critical",
            is_known_exploited=True,
            cisa_date_added="2021-12-10",
            cisa_due_date="2021-12-24",
            known_ransomware_campaign_use="Known",
            cisa_required_action="Apply updates per vendor instructions.",
        )
        ttl = serialize_vulnerability_entity(vuln)
        assert "sec:Vulnerability_CVE-2021-44228" in ttl
        assert "sec:isKnownExploited true" in ttl
        assert 'sec:cisaDueDate "2021-12-24"^^xsd:date' in ttl
        assert 'sec:knownRansomwareCampaignUse "Known"' in ttl
        assert "Apply updates per vendor instructions." in ttl


class TestMCPThreatDefenseKEVTools:
    """Tests for MCP KEV query and paper correlation tools."""

    def test_check_cve_kev_status_success(self) -> None:
        res = handle_check_cve_kev_status({"cve_id": "CVE-2021-44228"})
        assert res["status"] == "success"
        assert res["is_known_exploited"] is True
        assert res["cve_id"] == "CVE-2021-44228"
        assert res["product"] == "Log4j"
        assert res["is_ransomware_related"] is True

    def test_check_cve_kev_status_missing(self) -> None:
        res = handle_check_cve_kev_status({"cve_id": "CVE-1999-99999"})
        assert res["status"] == "success"
        assert res["is_known_exploited"] is False

    def test_check_cve_kev_status_empty(self) -> None:
        res = handle_check_cve_kev_status({"cve_id": ""})
        assert res["status"] == "error"

    def test_list_active_exploited_papers(self) -> None:
        res = handle_list_active_exploited_papers({"ransomware_only": True, "limit": 5})
        assert res["status"] == "success"
        assert res["ransomware_only"] is True
        assert len(res["results"]) > 0
        first_cve = res["results"][0]
        assert "cve_id" in first_cve
        assert "linked_papers" in first_cve
