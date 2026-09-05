#!/usr/bin/env python3
"""
MITRE ATT&CK STIX 2.0 / 2.1 JSON Bundle Parser.
Extracts tactics, techniques, mitigations, and relationships from OASIS STIX format.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Set, Tuple


class STIXCTIParser:
    """Parses MITRE ATT&CK STIX 2.0/2.1 Bundles into structured catalog dictionaries."""

    MITRE_SOURCES = {
        "mitre-attack",
        "mitre-enterprise-attack",
        "mitre-mobile-attack",
        "mitre-ics-attack",
    }

    def __init__(self) -> None:
        self.stix_to_mitre_id: Dict[str, str] = {}
        self.tactics: List[Dict[str, Any]] = []
        self.techniques: List[Dict[str, Any]] = []
        self.mitigations: List[Dict[str, Any]] = []
        self.raw_relationships: List[Dict[str, Any]] = []

    def parse_bundle(self, bundle_dict: Dict[str, Any]) -> Tuple[
        List[Dict[str, Any]],
        List[Dict[str, Any]],
        List[Dict[str, Any]],
        List[Tuple[str, str, str]],
    ]:
        """
        Parses a full STIX bundle dictionary.
        Returns (tactics, techniques, mitigations, resolved_relationships).
        """
        objects = bundle_dict.get("objects", [])
        self._reset()

        # Pass 1: Parse entities and build STIX ID -> MITRE ID index
        for obj in objects:
            self._parse_entity(obj)

        # Pass 2: Resolve relationships using mapped MITRE IDs
        resolved_rels = self._resolve_relationships()

        return self.tactics, self.techniques, self.mitigations, resolved_rels

    def _reset(self) -> None:
        self.stix_to_mitre_id.clear()
        self.tactics.clear()
        self.techniques.clear()
        self.mitigations.clear()
        self.raw_relationships.clear()

    @staticmethod
    def _is_active(obj: Dict[str, Any]) -> bool:
        if obj.get("revoked") is True:
            return False
        return not bool(obj.get("x_mitre_deprecated"))

    def _parse_entity(self, obj: Dict[str, Any]) -> None:
        """Dispatches object parsing by STIX type."""
        if not self._is_active(obj):
            return

        handlers = {
            "x-mitre-tactic": self._parse_tactic,
            "attack-pattern": self._parse_technique,
            "course-of-action": self._parse_mitigation,
        }
        obj_type = obj.get("type", "")
        handler = handlers.get(obj_type)
        if handler:
            handler(obj)
        elif obj_type == "relationship":
            self.raw_relationships.append(obj)

    def _parse_tactic(self, obj: Dict[str, Any]) -> None:
        mitre_id = self._extract_mitre_id(obj)
        shortname = obj.get("x_mitre_shortname", "")
        if not shortname:
            return

        tactic_id = mitre_id or f"TA-{shortname}"
        stix_id = obj.get("id", "")
        if stix_id:
            self.stix_to_mitre_id[stix_id] = tactic_id

        self.tactics.append(
            {
                "tactic_id": tactic_id,
                "shortname": shortname.lower(),
                "name": obj.get("name", ""),
                "description": obj.get("description", ""),
                "external_url": self._extract_mitre_url(obj),
            }
        )

    @staticmethod
    def _extract_tactics(phases: List[Dict[str, Any]]) -> List[str]:
        tactics: List[str] = []
        for phase in phases:
            phase_name = phase.get("phase_name")
            if phase_name:
                tactics.append(phase_name.lower())
        return sorted(list(set(tactics)))

    def _parse_technique(self, obj: Dict[str, Any]) -> None:
        mitre_id = self._extract_mitre_id(obj)
        if not mitre_id:
            return

        stix_id = obj.get("id", "")
        if stix_id:
            self.stix_to_mitre_id[stix_id] = mitre_id

        is_sub = bool(obj.get("x_mitre_is_subtechnique", False))
        parent_id = mitre_id.split(".")[0] if is_sub and "." in mitre_id else None
        tactics = self._extract_tactics(obj.get("kill_chain_phases", []))

        self.techniques.append(
            {
                "technique_id": mitre_id,
                "name": obj.get("name", ""),
                "description": obj.get("description", ""),
                "is_subtechnique": is_sub,
                "parent_technique_id": parent_id,
                "platforms": obj.get("x_mitre_platforms", []),
                "tactics": sorted(list(set(tactics))),
                "external_url": self._extract_mitre_url(obj),
                "stix_id": stix_id,
            }
        )

    def _parse_mitigation(self, obj: Dict[str, Any]) -> None:
        mitre_id = self._extract_mitre_id(obj)
        if not mitre_id:
            return

        stix_id = obj.get("id", "")
        if stix_id:
            self.stix_to_mitre_id[stix_id] = mitre_id

        self.mitigations.append(
            {
                "mitigation_id": mitre_id,
                "name": obj.get("name", ""),
                "description": obj.get("description", ""),
                "external_url": self._extract_mitre_url(obj),
                "stix_id": stix_id,
            }
        )

    def _resolve_relationships(self) -> List[Tuple[str, str, str]]:
        """Resolves raw STIX ID relationships into MITRE ID triples."""
        resolved: Set[Tuple[str, str, str]] = set()
        allowed_rel_types = {"subtechnique-of", "mitigates"}

        for rel in self.raw_relationships:
            rel_type = rel.get("relationship_type", "")
            if rel_type not in allowed_rel_types:
                continue

            src_stix = rel.get("source_ref", "")
            tgt_stix = rel.get("target_ref", "")
            src_mitre = self.stix_to_mitre_id.get(src_stix)
            tgt_mitre = self.stix_to_mitre_id.get(tgt_stix)

            if src_mitre and tgt_mitre:
                resolved.add((src_mitre, tgt_mitre, rel_type))

        return sorted(list(resolved))

    def _extract_mitre_id(self, obj: Dict[str, Any]) -> Optional[str]:
        for ref in obj.get("external_references", []):
            if ref.get("source_name") in self.MITRE_SOURCES:
                ext_id = ref.get("external_id")
                if ext_id and isinstance(ext_id, str):
                    return ext_id.strip()
        return None

    def _extract_mitre_url(self, obj: Dict[str, Any]) -> Optional[str]:
        for ref in obj.get("external_references", []):
            if ref.get("source_name") in self.MITRE_SOURCES:
                url = ref.get("url")
                if url and isinstance(url, str):
                    return url.strip()
        return None
