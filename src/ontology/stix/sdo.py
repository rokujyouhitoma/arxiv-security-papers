#!/usr/bin/env python3
"""
OASIS STIX 2.1 Specification-Compliant SDO (STIX Domain Objects).
Pure Python dataclasses for attack-pattern, vulnerability, course-of-action,
threat-actor, and identity.
"""

from __future__ import annotations

import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional


def generate_stix_id(type_name: str, seed: Optional[str] = None) -> str:
    """Generates RFC 4122 compliant STIX 2.1 ID: type--UUID."""
    if seed:
        uid = str(uuid.uuid5(uuid.NAMESPACE_DNS, seed))
    else:
        uid = str(uuid.uuid4())
    return f"{type_name}--{uid}"


def get_current_stix_timestamp() -> str:
    """Returns ISO 8601 UTC timestamp format per STIX 2.1 standard."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


@dataclass
class STIXDomainObject:
    """Base class for all STIX 2.1 Domain Objects."""

    type: str
    id: str
    created: str
    modified: str
    spec_version: str = "2.1"
    labels: List[str] = field(default_factory=list)
    confidence: int = 80
    external_references: List[Dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        """Serializes SDO to compliant STIX dictionary."""
        return {k: v for k, v in asdict(self).items() if v is not None}


@dataclass
class AttackPatternSDO(STIXDomainObject):
    """STIX 2.1 attack-pattern object (e.g. MITRE ATT&CK technique)."""

    name: str = ""
    description: str = ""
    aliases: List[str] = field(default_factory=list)
    kill_chain_phases: List[Dict[str, str]] = field(default_factory=list)


@dataclass
class VulnerabilitySDO(STIXDomainObject):
    """STIX 2.1 vulnerability object (e.g. CVE or CWE identifier)."""

    name: str = ""
    description: str = ""


@dataclass
class CourseOfActionSDO(STIXDomainObject):
    """STIX 2.1 course-of-action object (e.g. defensive countermeasure, patch, mitigation)."""

    name: str = ""
    description: str = ""
    action_type: str = ""


@dataclass
class IdentitySDO(STIXDomainObject):
    """STIX 2.1 identity object (e.g. author, university, research lab)."""

    name: str = ""
    identity_class: str = "organization"
    contact_information: str = ""
