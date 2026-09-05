#!/usr/bin/env python3
"""
MITRE ATT&CK CTI Registry.
Unified query interface with in-memory caching and resilient offline fallback
to builtin core technique definitions.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import os
from typing import Any, Dict, List, Optional

from .storage import CTICatalogStorage

# Core builtin fallback dictionary when SQLite catalog is not yet populated
BUILTIN_FALLBACK_TECHNIQUES: Dict[str, Dict[str, Any]] = {
    "T1059": {
        "technique_id": "T1059",
        "name": "Command and Scripting Interpreter",
        "description": "Adversaries may abuse command and script interpreters to execute commands.",
        "tactics": ["execution"],
        "platforms": ["Linux", "macOS", "Windows"],
        "keywords": ["command execution", "code injection", "scripting", "powershell"],
    },
    "T1078": {
        "technique_id": "T1078",
        "name": "Valid Accounts",
        "description": "Adversaries may obtain and abuse credentials of existing accounts.",
        "tactics": [
            "defense-evasion",
            "initial-access",
            "persistence",
            "privilege-escalation",
        ],
        "platforms": ["Linux", "macOS", "Windows", "Cloud"],
        "keywords": [
            "valid accounts",
            "credential stuffing",
            "impersonation",
            "stolen credentials",
        ],
    },
    "T1190": {
        "technique_id": "T1190",
        "name": "Exploit Public-Facing Application",
        "description": "Adversaries may attempt to exploit vulnerabilities in Internet-facing programs.",
        "tactics": ["initial-access"],
        "platforms": ["Linux", "macOS", "Windows", "Network"],
        "keywords": [
            "exploit public-facing application",
            "vulnerability",
            "remote code execution",
            "rce",
            "cve",
        ],
    },
    "T1499": {
        "technique_id": "T1499",
        "name": "Endpoint Denial of Service",
        "description": "Adversaries may perform Endpoint DoS to degrade or block service availability.",
        "tactics": ["impact"],
        "platforms": ["Linux", "macOS", "Windows"],
        "keywords": ["denial of service", "flooding", "ddos", "resource exhaustion"],
    },
    "T1566": {
        "technique_id": "T1566",
        "name": "Phishing",
        "description": "Adversaries may send phishing messages to gain initial access.",
        "tactics": ["initial-access"],
        "platforms": ["Linux", "macOS", "Windows"],
        "keywords": ["phishing", "smishing", "social engineering", "spearphishing"],
    },
    "T1574": {
        "technique_id": "T1574",
        "name": "Hijack Execution Flow",
        "description": "Adversaries may execute malicious payloads by hijacking execution flow.",
        "tactics": ["persistence", "privilege-escalation"],
        "platforms": ["Linux", "macOS", "Windows"],
        "keywords": [
            "hijacking",
            "dll sideloading",
            "backdoor",
            "path traversal",
            "library injection",
        ],
    },
    "T1587": {
        "technique_id": "T1587",
        "name": "Develop Capabilities",
        "description": "Adversaries may build capabilities to support targeting operations.",
        "tactics": ["resource-development"],
        "platforms": ["PRE"],
        "keywords": ["exploit generation", "malware synthesis", "payload development"],
    },
}

BUILTIN_FALLBACK_MITIGATIONS: Dict[str, List[Dict[str, Any]]] = {
    "T1059": [
        {
            "mitigation_id": "M1038",
            "name": "Execution Prevention",
            "description": "Block execution of untrusted scripts and binaries.",
            "external_url": "https://attack.mitre.org/mitigations/M1038/",
            "stix_id": "course-of-action--m1038",
        },
        {
            "mitigation_id": "M1049",
            "name": "Antivirus/Antimalware",
            "description": "Use signatures to detect malicious scripts.",
            "external_url": "https://attack.mitre.org/mitigations/M1049/",
            "stix_id": "course-of-action--m1049",
        },
    ],
    "T1190": [
        {
            "mitigation_id": "M1050",
            "name": "Exploit Protection",
            "description": "Use exploit mitigation features to protect public-facing applications.",
            "external_url": "https://attack.mitre.org/mitigations/M1050/",
            "stix_id": "course-of-action--m1050",
        },
        {
            "mitigation_id": "M1041",
            "name": "Network Segmentation",
            "description": "Segment public-facing systems from critical networks.",
            "external_url": "https://attack.mitre.org/mitigations/M1041/",
            "stix_id": "course-of-action--m1041",
        },
    ],
    "T1078": [
        {
            "mitigation_id": "M1032",
            "name": "Multi-factor Authentication",
            "description": "Require MFA for accounts with access to sensitive resources.",
            "external_url": "https://attack.mitre.org/mitigations/M1032/",
            "stix_id": "course-of-action--m1032",
        },
    ],
}


class MITRECTIRegistry:
    """Unified Registry for MITRE ATT&CK with persistent SQLite backend and offline fallback."""

    _instance: Optional[MITRECTIRegistry] = None

    def __init__(self, storage: Optional[CTICatalogStorage] = None) -> None:
        self.storage = storage or CTICatalogStorage()
        self._cache: Dict[str, Dict[str, Any]] = {}
        self._is_populated: Optional[bool] = None

    @classmethod
    def get_instance(cls) -> MITRECTIRegistry:
        """Singleton accessor."""
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def is_populated(self) -> bool:
        """Checks if the SQLite catalog contains indexed techniques."""
        if self._is_populated is None:
            if not os.path.exists(self.storage.db_path):
                self._is_populated = False
            else:
                counts = self.storage.count_summary()
                self._is_populated = counts.get("techniques", 0) > 0
        return self._is_populated

    def _enrich_technique_keywords(self, tech: Dict[str, Any], key: str) -> None:
        fallback = BUILTIN_FALLBACK_TECHNIQUES.get(key)
        if fallback and "keywords" in fallback:
            tech["keywords"] = list(fallback["keywords"])
        elif "keywords" not in tech and "name" in tech:
            tech["keywords"] = [tech["name"].lower()]

    def get_technique(self, technique_id: str) -> Optional[Dict[str, Any]]:
        """Retrieves technique metadata by ID (e.g. 'T1059' or 'T1059.001')."""
        key = technique_id.upper()
        if key in self._cache:
            return self._cache[key]

        if self.is_populated():
            tech = self.storage.get_technique(key)
            if tech:
                self._enrich_technique_keywords(tech, key)
                self._cache[key] = tech
                return tech

        # Fallback to builtin definitions
        fallback = BUILTIN_FALLBACK_TECHNIQUES.get(key)
        if fallback:
            self._cache[key] = fallback
            return fallback
        return None

    def get_all_techniques(self) -> Dict[str, Dict[str, Any]]:
        """Retrieves all techniques (from SQLite or fallback)."""
        if self.is_populated():
            all_techs = self.storage.get_all_techniques()
            if all_techs:
                for k, t in all_techs.items():
                    self._enrich_technique_keywords(t, k)
                self._cache.update(all_techs)
                return all_techs

        return dict(BUILTIN_FALLBACK_TECHNIQUES)

    @staticmethod
    def _matches_builtin_tech(tech: Dict[str, Any], q: str) -> bool:
        if q in tech["name"].lower() or q in tech["technique_id"].lower():
            return True
        return any(q in kw for kw in tech.get("keywords", []))

    def _search_builtin_fallback(self, query: str, limit: int) -> List[Dict[str, Any]]:
        q = query.lower()
        matched: List[Dict[str, Any]] = []
        for tech in BUILTIN_FALLBACK_TECHNIQUES.values():
            if self._matches_builtin_tech(tech, q):
                matched.append(tech)
                if len(matched) >= limit:
                    break
        return matched

    def search(self, query: str, limit: int = 15) -> List[Dict[str, Any]]:
        """Searches techniques by ID, name, or keywords."""
        if not query or not query.strip():
            return []

        if self.is_populated():
            results = self.storage.search_techniques(query, limit=limit)
            if results:
                return results

        return self._search_builtin_fallback(query, limit)

    def get_mitigations_for_technique(self, technique_id: str) -> List[Dict[str, Any]]:
        """Finds defensive mitigations for a given technique ID."""
        key = technique_id.upper()
        if self.is_populated():
            mits = self.storage.get_mitigations_for_technique(key)
            if mits:
                return mits
        parent_key = key.split(".")[0] if "." in key else key
        return BUILTIN_FALLBACK_MITIGATIONS.get(parent_key, [])

    def get_tactics(self) -> List[Dict[str, Any]]:
        """Returns all tactics."""
        if self.is_populated():
            tactics = self.storage.get_all_tactics()
            if tactics:
                return tactics

        # Minimal default tactics fallback
        return [
            {
                "tactic_id": "TA0001",
                "shortname": "initial-access",
                "name": "Initial Access",
            },
            {"tactic_id": "TA0002", "shortname": "execution", "name": "Execution"},
            {"tactic_id": "TA0003", "shortname": "persistence", "name": "Persistence"},
            {
                "tactic_id": "TA0004",
                "shortname": "privilege-escalation",
                "name": "Privilege Escalation",
            },
            {
                "tactic_id": "TA0005",
                "shortname": "defense-evasion",
                "name": "Defense Evasion",
            },
            {
                "tactic_id": "TA0006",
                "shortname": "credential-access",
                "name": "Credential Access",
            },
            {"tactic_id": "TA0007", "shortname": "discovery", "name": "Discovery"},
            {
                "tactic_id": "TA0008",
                "shortname": "lateral-movement",
                "name": "Lateral Movement",
            },
            {"tactic_id": "TA0009", "shortname": "collection", "name": "Collection"},
            {
                "tactic_id": "TA0010",
                "shortname": "exfiltration",
                "name": "Exfiltration",
            },
            {
                "tactic_id": "TA0011",
                "shortname": "command-and-control",
                "name": "Command and Control",
            },
            {"tactic_id": "TA0040", "shortname": "impact", "name": "Impact"},
        ]
