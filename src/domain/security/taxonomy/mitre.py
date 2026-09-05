#!/usr/bin/env python3
"""
MITRE ATT&CK Framework Mapping & Extraction Engine.
Maps academic security paper keywords and attack techniques to MITRE Enterprise ATT&CK matrix.
"""

import re
from typing import Any, Dict, List, Optional

from domain.security.cti.registry import MITRECTIRegistry

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


EXPLICIT_TECHNIQUE_RE = re.compile(r"\b(T\d{4}(?:\.\d{3})?)\b", re.IGNORECASE)


def get_technique_meta(tech_id: str) -> Dict[str, Any]:
    """Retrieves technique metadata from CTI Registry or local fallback map."""
    registry = MITRECTIRegistry.get_instance()
    cti_meta = registry.get_technique(tech_id)
    if cti_meta:
        tactics = cti_meta.get("tactics", [])
        primary_tactic = tactics[0] if tactics else "execution"
        return {
            "name": cti_meta.get("name", "Unknown Technique"),
            "tactic": primary_tactic,
            "description": cti_meta.get("description", ""),
            "platforms": cti_meta.get("platforms", []),
        }

    tech_meta = MITRE_TECHNIQUES_MAP.get(
        tech_id.upper(),
        {"name": "Generic Security Technique", "tactic": "Execution"},
    )
    return tech_meta


def _extract_explicit_ids(text: str) -> List[str]:
    return [m.group(1).upper() for m in EXPLICIT_TECHNIQUE_RE.finditer(text)]


def _extract_keyword_techniques(lower_text: str) -> List[str]:
    found: List[str] = []
    for tech_id, meta in MITRE_TECHNIQUES_MAP.items():
        kws = meta.get("keywords", [])
        if any(kw in lower_text for kw in kws):
            found.append(tech_id)
    return found


def extract_mitre_techniques(text: str) -> List[str]:
    """
    Extracts matching MITRE ATT&CK technique IDs from given text.
    Combines explicit technique ID regex matching and keyword taxonomy matching.
    """
    if not text:
        return []

    explicit = _extract_explicit_ids(text)
    keyword_matched = _extract_keyword_techniques(text.lower())
    return sorted(list(set(explicit + keyword_matched)))


def generate_caldera_ability(tech_id: str, platform: str = "linux") -> str:
    """
    Generates an automated Caldera attack emulation ability (YAML format)
    aligned with MITRE ATT&CK technique ID (DSN-16 / DSN-08).
    """
    tech_meta = get_technique_meta(tech_id)
    name = tech_meta.get("name", "Unknown Technique")
    tactic = str(tech_meta.get("tactic", "execution")).lower().replace(" ", "-")

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
    tech_meta = get_technique_meta(tech_id)
    name = tech_meta.get("name", "Unknown Technique")
    rule_title = title or f"Detection of {name} Activity"
    tactic_tag = str(tech_meta.get("tactic", "execution")).lower().replace(" ", "_")

    return f"""title: "{rule_title}"
id: sigma-{tech_id.lower()}-detection
status: experimental
description: "Detects anomalous activities and adversary execution matching MITRE ATT&CK {tech_id} ({name})."
references:
  - "https://attack.mitre.org/techniques/{tech_id}/"
tags:
  - "attack.{tech_id.lower()}"
  - "attack.{tactic_tag}"
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
