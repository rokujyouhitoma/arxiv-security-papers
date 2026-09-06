#!/usr/bin/env python3
"""
Taxonomy and Synonym Normalization Registry.
Normalizes raw terms against international cybersecurity standards
(MITRE ATT&CK, CWE, CVE, NIST SP 800-53, and STRIDE).
"""

from __future__ import annotations

import re
from typing import Dict, Optional, Tuple


class TaxonomyRegistry:
    """
    Standardizes security domain terminology into canonical ontology URIs.
    Eliminates spelling variations, acronym divergence, and slang.
    """

    # Canonical Entity Mappings
    SYNONYM_MAPPINGS: Dict[str, Tuple[str, str, str]] = {
        # Format: raw_key -> (Canonical ID, EntityType, DisplayName)
        # --- LLM / AI Security ---
        "prompt injection": (
            "AttackTechnique:Prompt_Injection",
            "AttackTechnique",
            "Prompt Injection",
        ),
        "jailbreak": (
            "AttackTechnique:Prompt_Injection",
            "AttackTechnique",
            "Prompt Injection",
        ),
        "jailbreaking": (
            "AttackTechnique:Prompt_Injection",
            "AttackTechnique",
            "Prompt Injection",
        ),
        "adversarial prompt": (
            "AttackTechnique:Prompt_Injection",
            "AttackTechnique",
            "Prompt Injection",
        ),
        "indirect prompt injection": (
            "AttackTechnique:Prompt_Injection",
            "AttackTechnique",
            "Prompt Injection",
        ),
        "model extraction": (
            "AttackTechnique:Model_Stealing",
            "AttackTechnique",
            "Model Extraction Attack",
        ),
        "data poisoning": (
            "AttackTechnique:Data_Poisoning",
            "AttackTechnique",
            "Data Poisoning Attack",
        ),
        "backdoor attack": (
            "AttackTechnique:Backdoor_Trigger",
            "AttackTechnique",
            "Backdoor Attack",
        ),
        "membership inference": (
            "AttackTechnique:Membership_Inference",
            "AttackTechnique",
            "Membership Inference",
        ),
        # --- Cryptography & Side-Channels ---
        "side-channel": (
            "AttackTechnique:Side_Channel_Analysis",
            "AttackTechnique",
            "Side-Channel Analysis",
        ),
        "side channel": (
            "AttackTechnique:Side_Channel_Analysis",
            "AttackTechnique",
            "Side-Channel Analysis",
        ),
        "power analysis": (
            "AttackTechnique:Side_Channel_Analysis",
            "AttackTechnique",
            "Side-Channel Analysis",
        ),
        "fault injection": (
            "AttackTechnique:Fault_Injection",
            "AttackTechnique",
            "Fault Injection Attack",
        ),
        "spectre": (
            "AttackTechnique:Transient_Execution",
            "AttackTechnique",
            "Spectre Transient Execution",
        ),
        "meltdown": (
            "AttackTechnique:Transient_Execution",
            "AttackTechnique",
            "Meltdown Transient Execution",
        ),
        "post-quantum": (
            "DefenseMechanism:Post_Quantum_Crypto",
            "DefenseMechanism",
            "Post-Quantum Cryptography",
        ),
        "lattice-based": (
            "DefenseMechanism:Post_Quantum_Crypto",
            "DefenseMechanism",
            "Post-Quantum Cryptography",
        ),
        "zero-knowledge": (
            "DefenseMechanism:Zero_Knowledge_Proof",
            "DefenseMechanism",
            "Zero-Knowledge Proofs",
        ),
        "zk-snark": (
            "DefenseMechanism:Zero_Knowledge_Proof",
            "DefenseMechanism",
            "Zero-Knowledge Proofs",
        ),
        "zkp": (
            "DefenseMechanism:Zero_Knowledge_Proof",
            "DefenseMechanism",
            "Zero-Knowledge Proofs",
        ),
        # --- Supply Chain & Code Security ---
        "supply chain": (
            "AttackTechnique:Supply_Chain_Tampering",
            "AttackTechnique",
            "Supply Chain Tampering",
        ),
        "privilege escalation": (
            "AttackTechnique:Privilege_Escalation",
            "AttackTechnique",
            "Privilege Escalation",
        ),
        "data exfiltration": (
            "AttackTechnique:Data_Exfiltration",
            "AttackTechnique",
            "Data Exfiltration",
        ),
        "arbitrary code execution": (
            "AttackTechnique:Code_Execution",
            "AttackTechnique",
            "Arbitrary Code Execution",
        ),
        "typosquatting": (
            "AttackTechnique:Supply_Chain_Tampering",
            "AttackTechnique",
            "Supply Chain Tampering",
        ),
        "dependency confusion": (
            "AttackTechnique:Supply_Chain_Tampering",
            "AttackTechnique",
            "Supply Chain Tampering",
        ),
        "malicious package": (
            "AttackTechnique:Supply_Chain_Tampering",
            "AttackTechnique",
            "Supply Chain Tampering",
        ),
        # --- Vulnerabilities (CWE) ---
        "sql injection": (
            "Vulnerability:CWE-89",
            "Vulnerability",
            "CWE-89: SQL Injection",
        ),
        "sqli": ("Vulnerability:CWE-89", "Vulnerability", "CWE-89: SQL Injection"),
        "xss": (
            "Vulnerability:CWE-79",
            "Vulnerability",
            "CWE-79: Cross-site Scripting",
        ),
        "cross-site scripting": (
            "Vulnerability:CWE-79",
            "Vulnerability",
            "CWE-79: Cross-site Scripting",
        ),
        "buffer overflow": (
            "Vulnerability:CWE-120",
            "Vulnerability",
            "CWE-120: Buffer Overflow",
        ),
        "use after free": (
            "Vulnerability:CWE-416",
            "Vulnerability",
            "CWE-416: Use After Free",
        ),
        "deserialization": (
            "Vulnerability:CWE-502",
            "Vulnerability",
            "CWE-502: Deserialization of Untrusted Data",
        ),
        # --- Target Assets ---
        "llm": (
            "TargetAsset:Large_Language_Model",
            "TargetAsset",
            "Large Language Model (LLM)",
        ),
        "large language model": (
            "TargetAsset:Large_Language_Model",
            "TargetAsset",
            "Large Language Model (LLM)",
        ),
        "smart contract": (
            "TargetAsset:Smart_Contract",
            "TargetAsset",
            "Smart Contract / EVM",
        ),
        "firmware": (
            "TargetAsset:Embedded_Firmware",
            "TargetAsset",
            "Embedded Firmware / IoT",
        ),
        "iot": (
            "TargetAsset:IoT_Device",
            "TargetAsset",
            "Internet of Things (IoT) Device",
        ),
        "tpm": (
            "TargetAsset:Hardware_Security_Module",
            "TargetAsset",
            "TPM / Hardware Security Module",
        ),
    }

    # MITRE ATT&CK ID regex pattern (e.g. T1059, T1059.001)
    MITRE_PATTERN = re.compile(r"\b(T\d{4}(?:\.\d{3})?)\b", re.IGNORECASE)
    # CWE regex pattern (e.g. CWE-79, CWE-120)
    CWE_PATTERN = re.compile(r"\b(CWE-\d+)\b", re.IGNORECASE)
    # CVE regex pattern (e.g. CVE-2024-12345)
    CVE_PATTERN = re.compile(r"\b(CVE-\d{4}-\d{4,7})\b", re.IGNORECASE)
    # NIST SP 800-53 Control regex pattern (e.g. AC-3, SI-10)
    NIST_PATTERN = re.compile(r"\b([A-Z]{2}-\d+(?:\(\d+\))?)\b")

    @classmethod
    def _match_pattern_id(cls, raw_term: str) -> Optional[Tuple[str, str, str]]:
        """Matches CWE, CVE, or MITRE ATT&CK patterns."""
        cwe_match = cls.CWE_PATTERN.search(raw_term)
        if cwe_match:
            cwe_id = cwe_match.group(1).upper()
            return f"Vulnerability:{cwe_id}", "Vulnerability", cwe_id

        cve_match = cls.CVE_PATTERN.search(raw_term)
        if cve_match:
            cve_id = cve_match.group(1).upper()
            return f"Vulnerability:{cve_id}", "Vulnerability", cve_id

        mitre_match = cls.MITRE_PATTERN.search(raw_term)
        if mitre_match:
            t_id = mitre_match.group(1).upper()
            return f"AttackTechnique:{t_id}", "AttackTechnique", f"MITRE {t_id}"
        return None

    @classmethod
    def _match_substring_synonym(cls, cleaned: str) -> Optional[Tuple[str, str, str]]:
        """Finds partial substring match in known synonym keys."""
        for key, val in cls.SYNONYM_MAPPINGS.items():
            if key in cleaned:
                return val
        return None

    @classmethod
    def normalize_term(cls, raw_term: str) -> Optional[Tuple[str, str, str]]:
        """
        Normalizes a raw keyword or phrase into (Canonical ID, EntityType, DisplayName).
        Returns None if no standard mapping is found.
        """
        if not raw_term:
            return None
        cleaned = raw_term.strip().lower()

        # 1. Direct dictionary match
        if cleaned in cls.SYNONYM_MAPPINGS:
            return cls.SYNONYM_MAPPINGS[cleaned]

        # 2. Pattern matches (CWE, CVE, MITRE)
        pattern_res = cls._match_pattern_id(raw_term)
        if pattern_res is not None:
            return pattern_res

        # 3. Partial substring matching
        return cls._match_substring_synonym(cleaned)
