#!/usr/bin/env python3
"""
MITRE ATT&CK Framework Mapping & Extraction Engine.
Maps academic security paper keywords and attack techniques to MITRE Enterprise ATT&CK matrix.
"""

from typing import Any, Dict, List

MITRE_TECHNIQUES_MAP: Dict[str, Dict[str, Any]] = {
    "T1059": {
        "name": "Command and Scripting Interpreter",
        "tactic": "Execution",
        "keywords": ["command execution", "code injection", "scripting", "powershell", "python interpreter"],
    },
    "T1078": {
        "name": "Valid Accounts",
        "tactic": "Defense Evasion / Initial Access",
        "keywords": ["valid accounts", "credential stuffing", "impersonation", "stolen credentials"],
    },
    "T1190": {
        "name": "Exploit Public-Facing Application",
        "tactic": "Initial Access",
        "keywords": ["exploit public-facing application", "vulnerability", "remote code execution", "rce", "cve"],
    },
    "T1499": {
        "name": "Endpoint Denial of Service",
        "tactic": "Impact",
        "keywords": ["denial of service", "flooding", "ddos", "resource exhaustion", "algorithmic complexity"],
    },
    "T1566": {
        "name": "Phishing",
        "tactic": "Initial Access",
        "keywords": ["phishing", "smishing", "social engineering", "spearphishing"],
    },
    "T1574": {
        "name": "Hijack Execution Flow",
        "tactic": "Persistence / Privilege Escalation",
        "keywords": ["hijacking", "dll sideloading", "backdoor", "path traversal", "library injection"],
    },
    "T1587": {
        "name": "Develop Capabilities",
        "tactic": "Resource Development",
        "keywords": ["exploit generation", "malware synthesis", "payload development"],
    },
}


def extract_mitre_techniques(text: str) -> List[str]:
    """Extracts matching MITRE ATT&CK technique IDs from given text."""
    if not text:
        return []

    lower_text = text.lower()
    found: List[str] = []
    for tech_id, meta in MITRE_TECHNIQUES_MAP.items():
        kws = meta.get("keywords", [])
        if any(kw in lower_text for kw in kws):
            found.append(tech_id)

    return sorted(list(set(found)))
