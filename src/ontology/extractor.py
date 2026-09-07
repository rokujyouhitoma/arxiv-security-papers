#!/usr/bin/env python3
"""
Ontology Fact Triple Extractor.
Extracts canonical entities and relationship triples from Google OKF v0.2 Markdown files.
"""

from __future__ import annotations

import re
from dataclasses import asdict
from typing import TYPE_CHECKING, Any, Dict, List, Optional, Sequence, Set, Tuple

if TYPE_CHECKING:
    from graph.engine import PropertyGraphEngine

from domain.security.cti.kev import CISAKEVRegistry, KEVEntry

from .extended_extractor import ExtendedExtractor
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
    CVE_PATTERN = re.compile(r"\bCVE-(?:1999|20\d{2})-\d{4,7}\b", re.IGNORECASE)
    _kev_registry: Optional[CISAKEVRegistry] = None

    @classmethod
    def get_kev_registry(cls) -> CISAKEVRegistry:
        """Lazily initializes and caches the default CISAKEVRegistry instance."""
        if cls._kev_registry is None:
            cls._kev_registry = CISAKEVRegistry()
        return cls._kev_registry

    @classmethod
    def _parse_list_item(
        cls,
        stripped: str,
        current_list_key: str,
        current_list: List[str],
        meta: Dict[str, Any],
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
        cls,
        stripped: str,
        current_list_key: str,
        current_list: List[str],
        meta: Dict[str, Any],
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
        return cls._handle_frontmatter_content(
            stripped, current_list_key, current_list, meta
        )

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
    def _create_vulnerability_from_cve(
        cls,
        cve_id: str,
        vuln_id: str,
        kev_entry: Optional[KEVEntry],
    ) -> VulnerabilityEntity:
        """Creates a typed VulnerabilityEntity from CVE ID and optional KEV entry."""
        if kev_entry is not None:
            return VulnerabilityEntity(
                id=vuln_id,
                entity_type=EntityType.VULNERABILITY,
                name=kev_entry.vulnerability_name or cve_id,
                description=kev_entry.short_description
                or f"CISA KEV確認済み悪用脆弱性 ({cve_id})",
                cve_id=cve_id,
                severity="Critical",
                is_known_exploited=True,
                cisa_date_added=kev_entry.date_added,
                cisa_due_date=kev_entry.due_date,
                known_ransomware_campaign_use=kev_entry.known_ransomware_campaign_use,
                cisa_required_action=kev_entry.required_action,
            )
        return VulnerabilityEntity(
            id=vuln_id,
            entity_type=EntityType.VULNERABILITY,
            name=cve_id,
            description=f"CVE脆弱性 ({cve_id})",
            cve_id=cve_id,
            severity="High",
            is_known_exploited=False,
        )

    @classmethod
    def _append_cve_triples(
        cls,
        paper_id: str,
        vuln_id: str,
        kev_entry: Optional[KEVEntry],
        triples: List[Triple],
    ) -> None:
        """Appends VERIFIES_CVE and DISCLOSES triples for CVE vulnerability."""
        if kev_entry is not None:
            triples.append(
                Triple(
                    subject_id=paper_id,
                    predicate=Predicate.VERIFIES_CVE,
                    object_id=vuln_id,
                    weight=1.0,
                )
            )
        triples.append(
            Triple(
                subject_id=paper_id,
                predicate=Predicate.DISCLOSES,
                object_id=vuln_id,
                weight=0.9 if kev_entry is not None else 0.8,
            )
        )

    @classmethod
    def _extract_cve_entities(
        cls,
        corpus_text: str,
        paper_id: str,
        seen_ids: Set[str],
        entities: List[BaseEntity],
        triples: List[Triple],
        kev_registry: Optional[CISAKEVRegistry] = None,
    ) -> None:
        """Extracts CVE vulnerabilities, correlates with CISA KEV catalog, and links triples."""
        registry = kev_registry or cls.get_kev_registry()
        for match in cls.CVE_PATTERN.finditer(corpus_text):
            cve_id = match.group(0).upper()
            vuln_id = f"Vulnerability:{cve_id}"
            kev_entry = registry.lookup(cve_id)
            if vuln_id not in seen_ids:
                entities.append(
                    cls._create_vulnerability_from_cve(cve_id, vuln_id, kev_entry)
                )
                seen_ids.add(vuln_id)
            cls._append_cve_triples(paper_id, vuln_id, kev_entry, triples)

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
        cls,
        d_id: str,
        attacks: List[BaseEntity],
        vulns: List[BaseEntity],
        triples: List[Triple],
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
        cls,
        clean_id: str,
        markdown_content: str,
        kev_registry: Optional[CISAKEVRegistry] = None,
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
        cls._extract_cve_entities(
            corpus_text,
            paper.id,
            seen_entity_ids,
            entities,
            triples,
            kev_registry=kev_registry,
        )
        cls._extract_taxonomy_terms(
            tokens, paper.id, seen_entity_ids, entities, triples
        )
        cls._link_defense_mitigations(entities, triples)
        cls._extract_extended_knowledge(
            clean_id, corpus_text, meta, paper.id, seen_entity_ids, entities, triples
        )

        return entities, cls._deduplicate_triples(triples)

    @classmethod
    def _categorize_entities(
        cls, entities: Sequence[BaseEntity]
    ) -> Dict[EntityType, List[BaseEntity]]:
        """Groups entities by their EntityType."""
        grouped: Dict[EntityType, List[BaseEntity]] = {}
        for ent in entities:
            grouped.setdefault(ent.entity_type, []).append(ent)
        return grouped

    @classmethod
    def _extract_base_extensions(
        cls,
        clean_id: str,
        corpus_text: str,
        meta: Dict[str, Any],
        paper_id: str,
    ) -> Tuple[List[BaseEntity], List[Triple]]:
        """Extracts preconditions, research gaps, detection rules/PoCs, and venue."""
        p_ents, p_trips = ExtendedExtractor.extract_preconditions(
            clean_id, corpus_text, paper_id
        )
        g_ents, g_trips = ExtendedExtractor.extract_research_gaps(
            clean_id, corpus_text, paper_id
        )
        r_ents, r_trips = ExtendedExtractor.extract_rules_and_pocs(
            clean_id, corpus_text, paper_id
        )
        v_ents, v_trips = ExtendedExtractor.extract_venue(
            clean_id, meta, corpus_text, paper_id
        )
        all_ents = list(p_ents) + list(g_ents) + list(r_ents) + list(v_ents)
        all_trips = p_trips + g_trips + r_trips + v_trips
        return all_ents, all_trips

    @classmethod
    def _extract_relational_extensions(
        cls,
        clean_id: str,
        corpus_text: str,
        meta: Dict[str, Any],
        paper_id: str,
        entities: List[BaseEntity],
        base_ents: List[BaseEntity],
    ) -> Tuple[List[BaseEntity], List[Triple]]:
        """Extracts impact/causality, claims/evidence, and incidents."""
        by_type = cls._categorize_entities(entities)
        p_ents = [e for e in base_ents if e.entity_type == EntityType.PRECONDITION]
        tech_ents = by_type.get(EntityType.ATTACK_TECHNIQUE, [])
        def_ents = by_type.get(EntityType.DEFENSE_MECHANISM, [])
        vuln_ents = by_type.get(EntityType.VULNERABILITY, [])

        imp_ents, imp_trips = ExtendedExtractor.extract_impacts_and_causality(
            clean_id, corpus_text, paper_id, tech_ents, def_ents, p_ents
        )
        ce_ents, ce_trips = ExtendedExtractor.extract_claims_and_evidence(
            clean_id, corpus_text, meta, paper_id, tech_ents
        )
        inc_ents, inc_trips = ExtendedExtractor.extract_incidents(
            clean_id, corpus_text, paper_id, tech_ents, vuln_ents
        )
        all_ents = list(imp_ents) + list(ce_ents) + list(inc_ents)
        all_trips = imp_trips + ce_trips + inc_trips
        return all_ents, all_trips

    @classmethod
    def _append_deduped_entities(
        cls,
        new_ents: List[BaseEntity],
        seen_entity_ids: Set[str],
        entities: List[BaseEntity],
    ) -> None:
        """Appends unseen entities to the main entities list."""
        for ent in new_ents:
            if ent.id not in seen_entity_ids:
                entities.append(ent)
                seen_entity_ids.add(ent.id)

    @classmethod
    def _extract_extended_knowledge(
        cls,
        clean_id: str,
        corpus_text: str,
        meta: Dict[str, Any],
        paper_id: str,
        seen_entity_ids: Set[str],
        entities: List[BaseEntity],
        triples: List[Triple],
    ) -> None:
        """Extracts extended entities and attaches them to entities and triples."""
        base_ents, base_trips = cls._extract_base_extensions(
            clean_id, corpus_text, meta, paper_id
        )
        rel_ents, rel_trips = cls._extract_relational_extensions(
            clean_id, corpus_text, meta, paper_id, entities, base_ents
        )
        cls._append_deduped_entities(base_ents + rel_ents, seen_entity_ids, entities)
        triples.extend(base_trips + rel_trips)

    @classmethod
    def ingest_paper_to_graph(
        cls,
        clean_id: str,
        markdown_content: str,
        engine: PropertyGraphEngine,
        confidence: float = 1.0,
        tier: str = "gold",
        kev_registry: Optional[CISAKEVRegistry] = None,
    ) -> Tuple[int, int]:
        """Extracts entities and triples from OKF and merges them into PropertyGraphEngine."""
        entities, triples = cls.extract_from_okf(
            clean_id, markdown_content, kev_registry=kev_registry
        )
        for ent in entities:
            props = asdict(ent)
            props["tier"] = tier
            engine.add_vertex(
                vertex_id=ent.id,
                label=ent.entity_type.value,
                properties=props,
            )
        for trip in triples:
            edge_props = {
                "confidence": confidence,
                "tier": tier,
                "provenance": f"okf:{clean_id}",
            }
            engine.add_edge(
                src_id=trip.subject_id,
                dst_id=trip.object_id,
                label=trip.predicate.value,
                weight=trip.weight,
                properties=edge_props,
            )
        return len(entities), len(triples)
