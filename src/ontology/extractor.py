#!/usr/bin/env python3
"""
Ontology Fact Triple Extractor.
Extracts canonical entities and relationship triples from Google OKF v0.2 Markdown files.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Set, Tuple

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
    def parse_okf_frontmatter(cls, markdown_text: str) -> Dict[str, Any]:
        """Parses basic YAML frontmatter keys from markdown without external YAML library."""
        meta: Dict[str, Any] = {}
        fm_match = cls.FRONTMATTER_PATTERN.search(markdown_text)
        if not fm_match:
            return meta

        raw_lines = fm_match.group(1).splitlines()
        current_list_key = ""
        current_list: List[str] = []

        for line in raw_lines:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            if stripped.startswith("- ") and current_list_key:
                current_list.append(stripped[2:].strip().strip("\"'"))
                meta[current_list_key] = current_list
                continue

            if ":" in stripped:
                k, v = stripped.split(":", 1)
                k = k.strip()
                v = v.strip().strip("\"'")
                if not v:
                    current_list_key = k
                    current_list = []
                else:
                    current_list_key = ""
                    meta[k] = v

        return meta

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
        tags = meta.get("tags", [])
        if isinstance(tags, str):
            tags = [t.strip() for t in tags.split(",") if t.strip()]

        # 1. Create Paper Entity
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

        # 2. Extract concepts from tags, title, and description
        corpus_text = f"{title} {desc} {' '.join(tags)} {markdown_content[:2000]}"
        words_and_phrases = set(tags + [title, desc])

        # Find CWEs, CVEs, MITRE in corpus
        for match in TaxonomyRegistry.CWE_PATTERN.finditer(corpus_text):
            cwe_id = match.group(1).upper()
            vuln_id = f"Vulnerability:{cwe_id}"
            if vuln_id not in seen_entity_ids:
                vuln = VulnerabilityEntity(
                    id=vuln_id,
                    entity_type=EntityType.VULNERABILITY,
                    name=cwe_id,
                    cwe_id=cwe_id,
                )
                entities.append(vuln)
                seen_entity_ids.add(vuln_id)
            triples.append(
                Triple(
                    subject_id=paper.id,
                    predicate=Predicate.DISCLOSES,
                    object_id=vuln_id,
                )
            )

        # Check domain dictionary terms
        for phrase in list(words_and_phrases) + corpus_text.lower().split():
            norm = TaxonomyRegistry.normalize_term(phrase)
            if not norm:
                continue
            canonical_id, ent_type, display_name = norm
            if canonical_id == paper.id:
                continue

            if canonical_id not in seen_entity_ids:
                if ent_type == "AttackTechnique":
                    ent: BaseEntity = AttackTechniqueEntity(
                        id=canonical_id,
                        entity_type=EntityType.ATTACK_TECHNIQUE,
                        name=display_name,
                        technique_id=canonical_id.split(":")[-1],
                    )
                elif ent_type == "DefenseMechanism":
                    ent = DefenseMechanismEntity(
                        id=canonical_id,
                        entity_type=EntityType.DEFENSE_MECHANISM,
                        name=display_name,
                        defense_id=canonical_id.split(":")[-1],
                    )
                elif ent_type == "TargetAsset":
                    ent = TargetAssetEntity(
                        id=canonical_id,
                        entity_type=EntityType.TARGET_ASSET,
                        name=display_name,
                        asset_type=display_name,
                    )
                else:
                    continue

                entities.append(ent)
                seen_entity_ids.add(canonical_id)

            # Generate Paper -> Entity triple
            if ent_type == "AttackTechnique":
                triples.append(
                    Triple(
                        subject_id=paper.id,
                        predicate=Predicate.ANALYZES,
                        object_id=canonical_id,
                    )
                )
            elif ent_type == "DefenseMechanism":
                triples.append(
                    Triple(
                        subject_id=paper.id,
                        predicate=Predicate.PROPOSES,
                        object_id=canonical_id,
                    )
                )
            elif ent_type == "TargetAsset":
                # Link attacks to target assets
                for e in entities:
                    if isinstance(e, AttackTechniqueEntity):
                        triples.append(
                            Triple(
                                subject_id=e.id,
                                predicate=Predicate.TARGETS,
                                object_id=canonical_id,
                            )
                        )

        # Link Defense -> AttackTechnique (MITIGATES) and Defense -> Vulnerability (PATCHES) if both exist
        defenses = [e for e in entities if isinstance(e, DefenseMechanismEntity)]
        attacks = [e for e in entities if isinstance(e, AttackTechniqueEntity)]
        vulns = [e for e in entities if isinstance(e, VulnerabilityEntity)]

        for d in defenses:
            for a in attacks:
                triples.append(
                    Triple(
                        subject_id=d.id, predicate=Predicate.MITIGATES, object_id=a.id
                    )
                )
            for v in vulns:
                triples.append(
                    Triple(subject_id=d.id, predicate=Predicate.PATCHES, object_id=v.id)
                )

        # Deduplicate triples
        unique_triples: List[Triple] = []
        seen_triples: Set[Tuple[str, str, str]] = set()
        for t in triples:
            key = (t.subject_id, t.predicate.value, t.object_id)
            if key not in seen_triples and t.subject_id != t.object_id:
                seen_triples.add(key)
                unique_triples.append(t)

        return entities, unique_triples
