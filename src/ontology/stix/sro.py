#!/usr/bin/env python3
"""
OASIS STIX 2.1 Specification-Compliant SRO (STIX Relationship Objects).
Defines structural predicates (mitigates, targets, exploits, indicates, attributed-to)
linking SDO entities.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Dict

from .sdo import generate_stix_id, get_current_stix_timestamp

VALID_RELATIONSHIPS = {
    "mitigates",
    "targets",
    "exploits",
    "indicates",
    "attributed-to",
    "cites",
    "derived-from",
}


@dataclass
class RelationshipSRO:
    """STIX 2.1 relationship object connecting two STIX objects."""

    relationship_type: str
    source_ref: str
    target_ref: str
    type: str = "relationship"
    spec_version: str = "2.1"
    id: str = ""
    created: str = ""
    modified: str = ""
    confidence: int = 80
    description: str = ""

    def __post_init__(self) -> None:
        if not self.id:
            seed = f"{self.relationship_type}:{self.source_ref}:{self.target_ref}"
            self.id = generate_stix_id("relationship", seed=seed)
        ts = get_current_stix_timestamp()
        if not self.created:
            self.created = ts
        if not self.modified:
            self.modified = ts

    def to_dict(self) -> Dict[str, Any]:
        """Serializes SRO to compliant STIX dictionary."""
        return {k: v for k, v in asdict(self).items() if v is not None}
