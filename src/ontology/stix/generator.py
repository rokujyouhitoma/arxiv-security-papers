#!/usr/bin/env python3
"""
STIX 2.1 Threat Knowledge Graph Generation Pipeline.
Transforms academic paper metadata, OKF summaries, and extracted CTI taxonomies
into standard STIX 2.1 Bundles with SDOs and SROs.
"""

from __future__ import annotations

from typing import List, Optional

from ..primus.ate import AttackTechniqueExtractor
from ..primus.rcm import RootCauseMapper
from .bundle import STIXBundle
from .sdo import (
    AttackPatternSDO,
    CourseOfActionSDO,
    IdentitySDO,
    VulnerabilitySDO,
    generate_stix_id,
    get_current_stix_timestamp,
)
from .sro import RelationshipSRO


class STIXGenerator:
    """Generates standardized STIX 2.1 JSON Bundles from security papers."""

    @classmethod
    def _create_identity_sdo(cls, authors: Optional[List[str]], ts: str) -> IdentitySDO:
        name = authors[0] if authors else "arXiv Security Research Community"
        return IdentitySDO(
            type="identity",
            id=generate_stix_id("identity", seed=f"identity:{name}"),
            created=ts,
            modified=ts,
            name=name,
            identity_class="class" if not authors else "individual",
            confidence=95,
        )

    @classmethod
    def _create_vuln_sdos(
        cls,
        paper_id: str,
        title: str,
        abstract: str,
        cwes: Optional[List[str]],
        ts: str,
    ) -> List[VulnerabilitySDO]:
        target_cwes = list(cwes or [])
        if not target_cwes:
            target_cwes = [
                r.mapped_id for r in RootCauseMapper.map_root_causes(abstract)
            ]
        sdos: List[VulnerabilitySDO] = []
        for cwe_id in target_cwes:
            sdos.append(
                VulnerabilitySDO(
                    type="vulnerability",
                    id=generate_stix_id("vulnerability", seed=f"vuln:{cwe_id}"),
                    created=ts,
                    modified=ts,
                    name=cwe_id,
                    description=f"Identified in paper {paper_id}: {title}",
                    confidence=85,
                    external_references=[
                        {
                            "source_name": "cwe",
                            "external_id": cwe_id,
                            "url": f"https://cwe.mitre.org/data/definitions/{cwe_id.replace('CWE-', '')}.html",
                        }
                    ],
                )
            )
        return sdos

    @classmethod
    def _create_attack_sdos(
        cls,
        paper_id: str,
        abstract: str,
        attcks: Optional[List[str]],
        ts: str,
    ) -> List[AttackPatternSDO]:
        target_attcks = list(attcks or [])
        if not target_attcks:
            target_attcks = [
                r.mapped_id
                for r in AttackTechniqueExtractor.extract_techniques(abstract)
            ]
        sdos: List[AttackPatternSDO] = []
        for tech_id in target_attcks:
            sdos.append(
                AttackPatternSDO(
                    type="attack-pattern",
                    id=generate_stix_id("attack-pattern", seed=f"attack:{tech_id}"),
                    created=ts,
                    modified=ts,
                    name=f"Technique {tech_id}",
                    description=f"Attack mechanism evaluated in paper {paper_id}",
                    confidence=85,
                    external_references=[
                        {"source_name": "mitre-attack", "external_id": tech_id}
                    ],
                )
            )
        return sdos

    @classmethod
    def _create_coa_sdos(
        cls,
        paper_id: str,
        defenses: Optional[List[str]],
        ts: str,
    ) -> List[CourseOfActionSDO]:
        defs = defenses or ["Academic Defense Countermeasure"]
        return [
            CourseOfActionSDO(
                type="course-of-action",
                id=generate_stix_id(
                    "course-of-action", seed=f"coa:{paper_id}:{d_name}"
                ),
                created=ts,
                modified=ts,
                name=d_name,
                description=f"Defense mechanism proposed in {paper_id}",
                confidence=90,
            )
            for d_name in defs
        ]

    @classmethod
    def _link_exploits(
        cls,
        bundle: STIXBundle,
        attack_sdos: List[AttackPatternSDO],
        vuln_sdos: List[VulnerabilitySDO],
    ) -> None:
        for ap in attack_sdos:
            for v in vuln_sdos:
                bundle.add_object(
                    RelationshipSRO(
                        relationship_type="exploits",
                        source_ref=ap.id,
                        target_ref=v.id,
                        confidence=85,
                        description=f"{ap.name} exploits {v.name}",
                    )
                )

    @classmethod
    def _link_mitigations(
        cls,
        bundle: STIXBundle,
        coa_sdos: List[CourseOfActionSDO],
        attack_sdos: List[AttackPatternSDO],
        vuln_sdos: List[VulnerabilitySDO],
    ) -> None:
        for coa in coa_sdos:
            for ap in attack_sdos:
                bundle.add_object(
                    RelationshipSRO(
                        relationship_type="mitigates",
                        source_ref=coa.id,
                        target_ref=ap.id,
                        confidence=90,
                        description=f"{coa.name} mitigates {ap.name}",
                    )
                )
            for v in vuln_sdos:
                bundle.add_object(
                    RelationshipSRO(
                        relationship_type="mitigates",
                        source_ref=coa.id,
                        target_ref=v.id,
                        confidence=85,
                        description=f"{coa.name} mitigates {v.name}",
                    )
                )

    @classmethod
    def _link_relationships(
        cls,
        bundle: STIXBundle,
        attack_sdos: List[AttackPatternSDO],
        vuln_sdos: List[VulnerabilitySDO],
        coa_sdos: List[CourseOfActionSDO],
    ) -> None:
        cls._link_exploits(bundle, attack_sdos, vuln_sdos)
        cls._link_mitigations(bundle, coa_sdos, attack_sdos, vuln_sdos)

    @classmethod
    def generate_from_paper(
        cls,
        paper_id: str,
        title: str,
        abstract: str,
        cwes: Optional[List[str]] = None,
        attcks: Optional[List[str]] = None,
        defenses: Optional[List[str]] = None,
        authors: Optional[List[str]] = None,
    ) -> STIXBundle:
        """Synthesizes a complete STIX 2.1 Bundle containing SDOs and SROs."""
        ts = get_current_stix_timestamp()
        bundle = STIXBundle(
            bundle_id=generate_stix_id("bundle", seed=f"paper:{paper_id}")
        )
        bundle.add_object(cls._create_identity_sdo(authors, ts))

        vuln_sdos = cls._create_vuln_sdos(paper_id, title, abstract, cwes, ts)
        for v in vuln_sdos:
            bundle.add_object(v)

        attack_sdos = cls._create_attack_sdos(paper_id, abstract, attcks, ts)
        for ap in attack_sdos:
            bundle.add_object(ap)

        coa_sdos = cls._create_coa_sdos(paper_id, defenses, ts)
        for coa in coa_sdos:
            bundle.add_object(coa)

        cls._link_relationships(bundle, attack_sdos, vuln_sdos, coa_sdos)
        return bundle
