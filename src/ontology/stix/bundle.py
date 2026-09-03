#!/usr/bin/env python3
"""
OASIS STIX 2.1 Specification-Compliant JSON Bundle.
Aggregates SDOs and SROs into interoperable JSON bundles for MISP and OpenCTI.
"""

from __future__ import annotations

import json
import os
from typing import Any, Dict, List, Optional, Union

from .sdo import STIXDomainObject, generate_stix_id
from .sro import RelationshipSRO


class STIXBundle:
    """STIX 2.1 Bundle container."""

    def __init__(
        self,
        objects: Optional[
            List[Union[STIXDomainObject, RelationshipSRO, Dict[str, Any]]]
        ] = None,
        bundle_id: Optional[str] = None,
    ) -> None:
        self.type: str = "bundle"
        self.id: str = bundle_id or generate_stix_id("bundle")
        self.objects: List[Dict[str, Any]] = []
        if objects:
            for obj in objects:
                self.add_object(obj)

    def add_object(
        self, obj: Union[STIXDomainObject, RelationshipSRO, Dict[str, Any]]
    ) -> None:
        """Appends an SDO or SRO to the bundle payload."""
        if hasattr(obj, "to_dict"):
            self.objects.append(obj.to_dict())
        elif isinstance(obj, dict):
            self.objects.append(obj)
        else:
            raise TypeError(f"Unsupported STIX object type: {type(obj)}")

    @property
    def object_count(self) -> int:
        """Returns number of objects in the bundle."""
        return len(self.objects)

    def to_dict(self) -> Dict[str, Any]:
        """Serializes bundle to STIX 2.1 dictionary."""
        return {
            "type": self.type,
            "id": self.id,
            "objects": self.objects,
        }

    def to_json(self, indent: int = 2) -> str:
        """Renders bundle to formatted JSON string."""
        return json.dumps(self.to_dict(), indent=indent, ensure_ascii=False)

    def to_file(self, file_path: str) -> None:
        """Writes JSON bundle to disk."""
        os.makedirs(os.path.dirname(os.path.abspath(file_path)), exist_ok=True)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(self.to_json())
