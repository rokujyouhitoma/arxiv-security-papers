#!/usr/bin/env python3
"""
Ontology Fact Triple Extractor.
Extracts canonical entities and relationship triples from Google OKF v0.2 Markdown files.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Set, Tuple

from .schema import (
    AttackTechniqueEntity,
    BaseEntity,
    DefenseMechanismEntity,
    EntityType,
    PaperEntity,
    Predicate,
    TargetAssetEntity,
    Triple,
    VulnerabilityEntity,
)
from .taxonomy import TaxonomyRegistry


class OntologyExtractor:
    """
    Extracts structured entities and factual triples from paper metadata and OKF content.
    """

    FRONTMATTER_PATTERN = re.compile(r"^---\s*\n(.*?)\n---", re.DOTALL)

    @classmethod
    def _parse_list_item(
        cls, stripped: str, current_list_key: str, current_list: List[str], meta: Dict[str, Any]
    ) -> Tuple[str, List[str]]:
        """Parses a bulleted YAML list item."""
        current_list.append(stripped[2:].strip().strip("\"'"))
        meta[current_list_key] = current_list
        return current_list_key, current_list

    @classmethod
    def _parse_key_value(
        cls, stripped: str, meta: Dict[str, Any]
    ) -> Tuple[str, List[str]]:
        """Parses a YAML key-value pair."""
        k, v = stripped.split(":", 1)
        k = k.strip()
        v = v.strip().strip("\"'")
        if not v:
            return k, []
        meta[k] = v
        return "", []

    @classmethod
    def _handle_frontmatter_content(
        cls, stripped: str, current_list_key: str, current_list: List[str], meta: Dict[str, Any]
    ) -> Tuple[str, List[str]]:
        """Dispatches non-comment frontmatter line to list or kv parser."""
        if stripped.startswith("- ") and current_list_key:
            return cls._parse_list_item(stripped, current_list_key, current_list, meta)
        if ":" in stripped:
            return cls._parse_key_value(stripped, meta)
        return current_list_key, current_list

    @classmethod
    def _parse_frontmatter_line(
        cls,
        line: str,
        current_list_key: str,
        current_list: List[str],
        meta: Dict[str, Any],
    ) -> Tuple[str, List[str]]:
        """Parses a single frontmatter line into metadata dictionary."""
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            return current_list_key, current_list
        return cls._handle_frontmatter_content(stripped, current_list_key, current_list, meta)

    @classmethod
    def parse_okf_frontmatter(cls, markdown_text: str) -> Dict[str, Any]:
        """Parses basic YAML frontmatter keys from markdown without external YAML library."""
        meta: Dict[str, Any] = {}
        fm_match = cls.FRONTMATTER_PATTERN.search(markdown_text)
        if not fm_match:
            return meta

        current_list_key = ""
        current_list: List[str] = []
        for line in fm_match.group(1).splitlines():
            current_list_key, current_list = cls._parse_frontmatter_line(
                line, current_list_key, current_list, meta
            )
        return meta

    @classmethod
    def _extract_cwe_entities(
        cls,
        corpus_text: str,
        paper_id: str,
        seen_ids: Set[str],
        entities: List[BaseEntity],
        triples: List[Triple],
    ) -> None:
        """Extracts CWE vulnerabilities and DISCLOSES triples."""
        for match in TaxonomyRegistry.CWE_PATTERN.finditer(corpus_text):
            cwe_id = match.group(1).upper()
            vuln_id = f"Vulnerability:{cwe_id}"
            if vuln_id not in seen_ids:
                entities.append(
                    VulnerabilityEntity(
                        id=vuln_id,
                        entity_type=EntityType.VULNERABILITY,
                        name=cwe_id,
                        cwe_id=cwe_id,
                    )
                )
                seen_ids.add(vuln_id)
            triples.append(
                Triple(
                    subject_id=paper_id,
                    predicate=Predicate.DISCLOSES,
                    object_id=vuln_id,
                )
            )

    @classmethod
    def _create_entity_from_type(
        cls, canonical_id: str, ent_type: str, display_name: str
    ) -> Optional[BaseEntity]:
        """Factory for creating ontology entity from normalized taxonomy type."""
        raw_id = canonical_id.split(":")[-1]
        if ent_type == "AttackTechnique":
            return AttackTechniqueEntity(
                id=canonical_id,
                entity_type=EntityType.ATTACK_TECHNIQUE,
                name=display_name,
                technique_id=raw_id,
            )
        if ent_type == "DefenseMechanism":
            return DefenseMechanismEntity(
                id=canonical_id,
                entity_type=EntityType.DEFENSE_MECHANISM,
                name=display_name,
                defense_id=raw_id,
            )
        if ent_type == "TargetAsset":
            return TargetAssetEntity(
                id=canonical_id,
                entity_type=EntityType.TARGET_ASSET,
                name=display_name,
                asset_type=display_name,
            )
        return None

    @classmethod
    def _link_target_asset(
        cls, canonical_id: str, entities: List[BaseEntity], triples: List[Triple]
    ) -> None:
        """Links target assets to attack techniques."""
        for e in entities:
            if isinstance(e, AttackTechniqueEntity):
                triples.append(
                    Triple(
                        subject_id=e.id,
                        predicate=Predicate.TARGETS,
                        object_id=canonical_id,
                    )
                )

    @classmethod
    def _link_domain_entity(
        cls,
        canonical_id: str,
        ent_type: str,
        paper_id: str,
        entities: List[BaseEntity],
        triples: List[Triple],
    ) -> None:
        """Generates appropriate triples for domain entity."""
        if ent_type == "AttackTechnique":
            triples.append(
                Triple(
                    subject_id=paper_id,
                    predicate=Predicate.ANALYZES,
                    object_id=canonical_id,
                )
            )
        elif ent_type == "DefenseMechanism":
            triples.append(
                Triple(
                    subject_id=paper_id,
                    predicate=Predicate.PROPOSES,
                    object_id=canonical_id,
                )
            )
        elif ent_type == "TargetAsset":
            cls._link_target_asset(canonical_id, entities, triples)

    @classmethod
    def _process_single_term(
        cls,
        phrase: str,
        paper_id: str,
        seen_ids: Set[str],
        entities: List[BaseEntity],
        triples: List[Triple],
    ) -> None:
        """Processes a single term for taxonomy entity extraction and linking."""
        norm = TaxonomyRegistry.normalize_term(phrase)
        if not norm or norm[0] == paper_id:
            return
        canonical_id, ent_type, display_name = norm

        if canonical_id not in seen_ids:
            ent = cls._create_entity_from_type(canonical_id, ent_type, display_name)
            if ent is not None:
                entities.append(ent)
                seen_ids.add(canonical_id)

        cls._link_domain_entity(canonical_id, ent_type, paper_id, entities, triples)

    @classmethod
    def _extract_taxonomy_terms(
        cls,
        tokens: List[str],
        paper_id: str,
        seen_ids: Set[str],
        entities: List[BaseEntity],
        triples: List[Triple],
    ) -> None:
        """Extracts and links taxonomy terms from text tokens."""
        for phrase in tokens:
            cls._process_single_term(phrase, paper_id, seen_ids, entities, triples)

    @classmethod
    def _link_single_defense(
        cls, d_id: str, attacks: List[BaseEntity], vulns: List[BaseEntity], triples: List[Triple]
    ) -> None:
        """Links one defense mechanism to all attacks and vulnerabilities."""
        for a in attacks:
            triples.append(
                Triple(subject_id=d_id, predicate=Predicate.MITIGATES, object_id=a.id)
            )
        for v in vulns:
            triples.append(
                Triple(subject_id=d_id, predicate=Predicate.PATCHES, object_id=v.id)
            )

    @classmethod
    def _classify_defense_entities(
        cls, entities: List[BaseEntity]
    ) -> Tuple[List[BaseEntity], List[BaseEntity], List[BaseEntity]]:
        """Classifies entities into defenses, attacks, and vulnerabilities."""
        defenses: List[BaseEntity] = []
        attacks: List[BaseEntity] = []
        vulns: List[BaseEntity] = []
        for e in entities:
            if isinstance(e, DefenseMechanismEntity):
                defenses.append(e)
            elif isinstance(e, AttackTechniqueEntity):
                attacks.append(e)
            elif isinstance(e, VulnerabilityEntity):
                vulns.append(e)
        return defenses, attacks, vulns

    @classmethod
    def _link_defense_mitigations(
        cls, entities: List[BaseEntity], triples: List[Triple]
    ) -> None:
        """Links defense mechanisms to attacks and vulnerabilities."""
        defenses, attacks, vulns = cls._classify_defense_entities(entities)
        for d in defenses:
            cls._link_single_defense(d.id, attacks, vulns, triples)

    @classmethod
    def _deduplicate_triples(cls, triples: List[Triple]) -> List[Triple]:
        """Removes duplicate and self-referencing triples."""
        unique: List[Triple] = []
        seen: Set[Tuple[str, str, str]] = set()
        for t in triples:
            key = (t.subject_id, t.predicate.value, t.object_id)
            if key not in seen and t.subject_id != t.object_id:
                seen.add(key)
                unique.append(t)
        return unique

    @classmethod
    def extract_from_okf(
        cls, clean_id: str, markdown_content: str
    ) -> Tuple[List[BaseEntity], List[Triple]]:
        """
        Extracts Paper, AttackTechnique, Vulnerability, TargetAsset, DefenseMechanism
        entities and semantic triples from OKF markdown.
        """
        entities: List[BaseEntity] = []
        triples: List[Triple] = []
        seen_entity_ids: Set[str] = set()

        meta = cls.parse_okf_frontmatter(markdown_content)
        title = str(meta.get("title", clean_id))
        desc = str(meta.get("description", ""))
        raw_tags = meta.get("tags", [])
        tags = (
            [t.strip() for t in raw_tags.split(",") if t.strip()]
            if isinstance(raw_tags, str)
            else list(raw_tags)
        )

        paper = PaperEntity(
            id=f"Paper:{clean_id}",
            entity_type=EntityType.PAPER,
            name=title,
            arxiv_id=clean_id,
            title_ja=desc,
            title_en=title,
            description=desc,
        )
        entities.append(paper)
        seen_entity_ids.add(paper.id)

        corpus_text = f"{title} {desc} {' '.join(tags)} {markdown_content[:2000]}"
        tokens = list(set(tags + [title, desc])) + corpus_text.lower().split()

        cls._extract_cwe_entities(
            corpus_text, paper.id, seen_entity_ids, entities, triples
        )
        cls._extract_taxonomy_terms(
            tokens, paper.id, seen_entity_ids, entities, triples
        )
        cls._link_defense_mitigations(entities, triples)

        return entities, cls._deduplicate_triples(triples)
