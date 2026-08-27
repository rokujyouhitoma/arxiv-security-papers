#!/usr/bin/env python3
"""
MITRE ATT&CK Framework Mapping & Extraction Engine.
Maps academic security paper keywords and attack techniques to MITRE Enterprise ATT&CK matrix.
"""

from typing import Any, Dict, List, Optional

MITRE_TECHNIQUES_MAP: Dict[str, Dict[str, Any]] = {
    "T1059": {
        "name": "Command and Scripting Interpreter",
        "tactic": "Execution",
        "keywords": [
            "command execution",
            "code injection",
            "scripting",
            "powershell",
            "python interpreter",
        ],
    },
    "T1078": {
        "name": "Valid Accounts",
        "tactic": "Defense Evasion / Initial Access",
        "keywords": [
            "valid accounts",
            "credential stuffing",
            "impersonation",
            "stolen credentials",
        ],
    },
    "T1190": {
        "name": "Exploit Public-Facing Application",
        "tactic": "Initial Access",
        "keywords": [
            "exploit public-facing application",
            "vulnerability",
            "remote code execution",
            "rce",
            "cve",
        ],
    },
    "T1499": {
        "name": "Endpoint Denial of Service",
        "tactic": "Impact",
        "keywords": [
            "denial of service",
            "flooding",
            "ddos",
            "resource exhaustion",
            "algorithmic complexity",
        ],
    },
    "T1566": {
        "name": "Phishing",
        "tactic": "Initial Access",
        "keywords": ["phishing", "smishing", "social engineering", "spearphishing"],
    },
    "T1574": {
        "name": "Hijack Execution Flow",
        "tactic": "Persistence / Privilege Escalation",
        "keywords": [
            "hijacking",
            "dll sideloading",
            "backdoor",
            "path traversal",
            "library injection",
        ],
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


def generate_caldera_ability(tech_id: str, platform: str = "linux") -> str:
    """
    Generates an automated Caldera attack emulation ability (YAML format)
    aligned with MITRE ATT&CK technique ID (DSN-16 / DSN-08).
    """
    tech_meta = MITRE_TECHNIQUES_MAP.get(
        tech_id.upper(),
        {"name": "Generic Security Technique", "tactic": "Execution"},
    )
    name = tech_meta.get("name", "Unknown Technique")
    tactic = tech_meta.get("tactic", "execution").lower().replace(" ", "-")

    return f"""---
- id: ability-{tech_id.lower()}-emulation
  name: "Emulate {name} ({tech_id})"
  description: "Automated adversary emulation for {name} ({tech_id}) generated from academic security research."
  tactic: "{tactic}"
  technique:
    attack_id: "{tech_id}"
    name: "{name}"
  platforms:
    {platform}:
      sh:
        command: "echo '[Caldera Emulation] Simulating {tech_id} ({name})' && exit 0"
        cleanup: "echo '[Caldera Cleanup] Done' && exit 0"
"""


def generate_sigma_rule(tech_id: str, title: Optional[str] = None) -> str:
    """
    Generates a SIEM detection rule draft in Sigma YAML format for a given ATT&CK technique ID (DSN-16).
    """
    tech_meta = MITRE_TECHNIQUES_MAP.get(
        tech_id.upper(),
        {"name": "Generic Attack Technique", "tactic": "Execution"},
    )
    name = tech_meta.get("name", "Unknown Technique")
    rule_title = title or f"Detection of {name} Activity"

    return f"""title: "{rule_title}"
id: sigma-{tech_id.lower()}-detection
status: experimental
description: "Detects anomalous activities and adversary execution matching MITRE ATT&CK {tech_id} ({name})."
references:
  - "https://attack.mitre.org/techniques/{tech_id}/"
tags:
  - "attack.{tech_id.lower()}"
  - "attack.{tech_meta.get('tactic', 'execution').lower().replace(' ', '_')}"
logsource:
  category: process_creation
  product: linux
detection:
  selection:
    CommandLine|contains:
      - "{name.lower()}"
  condition: selection
falsepositives:
  - "Legitimate administrative and maintenance tasks"
level: medium
"""
