#!/usr/bin/env python3
"""
Pure-Python OASIS STIX 2.1 SDO / SRO Data Model.
Provides deterministic UUIDv5 identifiers, AttackPattern, CourseOfAction,
Relationship, and Bundle data structures.
Zero External Dependencies (Standard Library only).
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

# OASIS STIX 2.1 Namespace UUID (RFC 4122)
STIX_NAMESPACE_UUID = uuid.UUID("00abedb4-aa42-466c-9c01-fedf7a7a5b9b")


def generate_stix_id(
    type_name: str,
    identifier: str,
    namespace: Optional[uuid.UUID] = None,
) -> str:
    """
    Generates a deterministic RFC 4122 UUIDv5 identifier for a STIX 2.1 object.
    Format: {type_name}--{uuid5}
    """
    ns = namespace or STIX_NAMESPACE_UUID
    name = f"{type_name}:{identifier}"
    generated_uuid = uuid.uuid5(ns, name)
    return f"{type_name}--{generated_uuid}"


@dataclass(frozen=True)
class AttackPattern:
    """STIX 2.1 Domain Object (SDO) for ATT&CK Techniques."""

    name: str
    id: str = ""
    description: str = ""
    external_references: List[Dict[str, Any]] = field(default_factory=list)
    kill_chain_phases: List[Dict[str, str]] = field(default_factory=list)
    spec_version: str = "2.1"
    type: str = "attack-pattern"

    def __post_init__(self) -> None:
        if not self.id:
            # Derive deterministic ID from name and references if available
            key = self._extract_key()
            generated = generate_stix_id("attack-pattern", key)
            object.__setattr__(self, "id", generated)

    def _extract_key(self) -> str:
        for ref in self.external_references:
            ext_id = ref.get("external_id")
            if ext_id:
                return str(ext_id)
        return self.name

    def to_dict(self) -> Dict[str, Any]:
        """Serializes AttackPattern to canonical STIX 2.1 dictionary."""
        d: Dict[str, Any] = {
            "type": self.type,
            "spec_version": self.spec_version,
            "id": self.id,
            "name": self.name,
        }
        if self.description:
            d["description"] = self.description
        if self.external_references:
            d["external_references"] = self.external_references
        if self.kill_chain_phases:
            d["kill_chain_phases"] = self.kill_chain_phases
        return d


@dataclass(frozen=True)
class CourseOfAction:
    """STIX 2.1 Domain Object (SDO) for Defenses & Mitigations."""

    name: str
    id: str = ""
    description: str = ""
    external_references: List[Dict[str, Any]] = field(default_factory=list)
    spec_version: str = "2.1"
    type: str = "course-of-action"

    def __post_init__(self) -> None:
        if not self.id:
            key = self._extract_key()
            generated = generate_stix_id("course-of-action", key)
            object.__setattr__(self, "id", generated)

    def _extract_key(self) -> str:
        for ref in self.external_references:
            ext_id = ref.get("external_id")
            if ext_id:
                return str(ext_id)
        return self.name

    def to_dict(self) -> Dict[str, Any]:
        """Serializes CourseOfAction to canonical STIX 2.1 dictionary."""
        d: Dict[str, Any] = {
            "type": self.type,
            "spec_version": self.spec_version,
            "id": self.id,
            "name": self.name,
        }
        if self.description:
            d["description"] = self.description
        if self.external_references:
            d["external_references"] = self.external_references
        return d


@dataclass(frozen=True)
class StixRelationship:
    """STIX 2.1 Relationship Object (SRO)."""

    relationship_type: str
    source_ref: str
    target_ref: str
    id: str = ""
    description: str = ""
    spec_version: str = "2.1"
    type: str = "relationship"

    def __post_init__(self) -> None:
        if not self.id:
            key = f"{self.relationship_type}:{self.source_ref}->{self.target_ref}"
            generated = generate_stix_id("relationship", key)
            object.__setattr__(self, "id", generated)

    def to_dict(self) -> Dict[str, Any]:
        """Serializes Relationship to canonical STIX 2.1 dictionary."""
        d: Dict[str, Any] = {
            "type": self.type,
            "spec_version": self.spec_version,
            "id": self.id,
            "relationship_type": self.relationship_type,
            "source_ref": self.source_ref,
            "target_ref": self.target_ref,
        }
        if self.description:
            d["description"] = self.description
        return d


@dataclass(frozen=True)
class StixBundle:
    """STIX 2.1 Bundle container for SDOs and SROs."""

    objects: List[Dict[str, Any]] = field(default_factory=list)
    id: str = ""
    type: str = "bundle"

    def __post_init__(self) -> None:
        if not self.id:
            # Deterministic Bundle ID based on contents or random uuid4 representation
            obj_ids = [
                str(o.get("id", "")) for o in self.objects if isinstance(o, dict)
            ]
            key = "|".join(sorted(obj_ids)) if obj_ids else "empty"
            generated = generate_stix_id("bundle", key)
            object.__setattr__(self, "id", generated)

    def to_dict(self) -> Dict[str, Any]:
        """Serializes Bundle to canonical STIX 2.1 dictionary."""
        return {
            "type": self.type,
            "id": self.id,
            "objects": self.objects,
        }

    def to_json(self, indent: int = 2) -> str:
        """Serializes Bundle to pretty JSON string."""
        return json.dumps(self.to_dict(), indent=indent, ensure_ascii=False)
