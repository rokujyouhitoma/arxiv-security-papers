#!/usr/bin/env python3
"""
Property Graph Data Structures.
Defines Vertex, Edge, Path, and Graph Metadata.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple


def _safe_parse_json_props(raw: Any) -> Dict[str, Any]:
    """Safely decodes JSON properties string into a dictionary."""
    if not raw:
        return {}
    try:
        loaded = json.loads(str(raw))
        return loaded if isinstance(loaded, dict) else {}
    except (ValueError, TypeError):
        return {}


def _get_field(row: Tuple[Any, ...] | List[Any], idx: int, default: Any = "") -> Any:
    """Safely gets field from row if within bounds and not None."""
    return row[idx] if len(row) > idx and row[idx] is not None else default


@dataclass
class Vertex:
    """Represents a Graph Vertex (Node) with typed properties."""

    id: str
    label: str = "Vertex"  # e.g. Paper, AttackTechnique, Vulnerability
    properties: Dict[str, Any] = field(default_factory=dict)

    def get(self, key: str, default: Any = None) -> Any:
        return self.properties.get(key, default)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "label": self.label,
            "properties": self.properties,
        }

    def to_db_tuple(self) -> Tuple[str, str, str, str]:
        """Serializes vertex for relational vertices table insertion."""
        name = str(self.properties.get("name") or self.id)
        props_json = json.dumps(self.properties, ensure_ascii=False)
        return (self.id, self.label, name, props_json)

    @classmethod
    def from_db_row(cls, row: Tuple[Any, ...] | List[Any]) -> Vertex:
        """Deserializes vertex from relational vertices table row."""
        v_id = str(_get_field(row, 0, ""))
        v_label = str(_get_field(row, 1, "Vertex"))
        v_name = str(_get_field(row, 2, ""))
        props = _safe_parse_json_props(_get_field(row, 3, None))
        if v_name and "name" not in props:
            props["name"] = v_name
        return cls(id=v_id, label=v_label, properties=props)


@dataclass
class Edge:
    """Represents a Directed Graph Edge with typed label, weight, and properties."""

    src_id: str
    dst_id: str
    label: str = "RELATED"  # e.g. EXPLOITS, MITIGATES, DISCLOSES
    weight: float = 1.0
    properties: Dict[str, Any] = field(default_factory=dict)

    @property
    def id(self) -> str:
        return f"{self.src_id}-[{self.label}]->{self.dst_id}"

    def get(self, key: str, default: Any = None) -> Any:
        return self.properties.get(key, default)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "src_id": self.src_id,
            "dst_id": self.dst_id,
            "label": self.label,
            "weight": self.weight,
            "properties": self.properties,
        }

    def to_db_tuple(self) -> Tuple[str, str, str, str, float, float, str]:
        """Serializes edge for relational edges table insertion."""
        conf = self.get_confidence()
        props_json = json.dumps(self.properties, ensure_ascii=False)
        return (
            self.id,
            self.src_id,
            self.dst_id,
            self.label,
            conf,
            float(self.weight),
            props_json,
        )

    @classmethod
    def from_db_row(cls, row: Tuple[Any, ...] | List[Any]) -> Edge:
        """Deserializes edge from relational edges table row."""
        src_id = str(_get_field(row, 1, ""))
        dst_id = str(_get_field(row, 2, ""))
        label = str(_get_field(row, 3, "RELATED"))
        conf = float(_get_field(row, 4, 1.0))
        weight = float(_get_field(row, 5, 1.0))
        props = _safe_parse_json_props(_get_field(row, 6, None))
        if "confidence" not in props:
            props["confidence"] = conf
        return cls(
            src_id=src_id,
            dst_id=dst_id,
            label=label,
            weight=weight,
            properties=props,
        )

    def get_confidence(self, default: Optional[float] = None) -> float:
        """Retrieves numerical confidence score from properties or weight."""
        fallback = default if default is not None else self.weight
        val = self.properties.get("confidence", fallback)
        try:
            return float(val)
        except (ValueError, TypeError):
            return 0.0

    def get_confidence_tier(self) -> str:
        """Determines confidence tier (HIGH, MEDIUM, LOW)."""
        tier = self.properties.get("confidence_tier")
        if tier:
            return str(tier).upper()
        conf = self.get_confidence()
        if conf >= 0.8:
            return "HIGH"
        if conf >= 0.5:
            return "MEDIUM"
        return "LOW"

    def is_high_confidence(self, threshold: float = 0.8) -> bool:
        """Checks if confidence meets high threshold."""
        return self.get_confidence() >= threshold

    def has_rule(self, rule_id: str) -> bool:
        """Checks if a rule ID was applied to this edge."""
        if self.properties.get("primary_rule_id") == rule_id:
            return True
        applied = self.properties.get("applied_rules", [])
        return isinstance(applied, list) and rule_id in applied

    def get_primary_rule(self) -> Optional[str]:
        """Returns primary inference rule ID if present."""
        rule = self.properties.get("primary_rule_id")
        return str(rule) if rule else None

    def get_evidences(self) -> List[Dict[str, Any]]:
        """Returns structured inference evidences."""
        ev = self.properties.get("evidences", [])
        return list(ev) if isinstance(ev, list) else []


@dataclass
class Path:
    """Represents an ordered sequence of vertices and edges in a traversal."""

    objects: List[Any] = field(
        default_factory=list
    )  # Alternating Vertex, Edge, Vertex...
    labels: List[List[str]] = field(
        default_factory=list
    )  # Step labels associated with each step

    def extend(self, obj: Any, step_labels: Optional[List[str]] = None) -> Path:
        """Returns a new Path extended by obj."""
        new_objs = list(self.objects) + [obj]
        new_labels = list(self.labels) + [step_labels or []]
        return Path(objects=new_objs, labels=new_labels)

    def to_list(self) -> List[Any]:
        return list(self.objects)
