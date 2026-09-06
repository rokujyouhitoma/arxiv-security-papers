#!/usr/bin/env python3
"""
Extended Ontology Fact Extractor for Full-Spectrum Security Knowledge.
Extracts Preconditions, Research Gaps, Detection Rules, PoC Artifacts, and Venues.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Set, Tuple

from .schema import (
    BaseEntity,
    ClaimEntity,
    DetectionRuleEntity,
    EntityType,
    EvaluationResultEntity,
    ImpactEntity,
    IncidentEntity,
    PoCArtifactEntity,
    PreconditionEntity,
    Predicate,
    PublicationVenueEntity,
    ResearchGapEntity,
    ResidualRiskEntity,
    Triple,
)


class ExtendedExtractor:
    """
    Extracts high-order domain entities and relationships from paper text and metadata.
    """

    GITHUB_PATTERN = re.compile(
        r"https?://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)"
    )
    CVE_PATTERN = re.compile(r"\b(CVE-\d{4}-\d{4,7})\b", re.IGNORECASE)

    ACCESS_PATTERNS: List[Tuple[str, str, str]] = [
        ("physical access", "Physical", "Physical Access Required"),
        ("local access", "Local", "Local System Access"),
        ("remote execution", "Remote", "Remote Network Access"),
        ("network access", "Remote", "Remote Network Access"),
        ("unauthenticated", "Remote", "Unauthenticated Remote Access"),
        ("white-box", "White-Box", "White-Box Knowledge"),
        ("black-box", "Black-Box", "Black-Box Interaction"),
        ("gray-box", "Gray-Box", "Gray-Box Knowledge"),
        ("root privilege", "Root", "Elevated/Root Privileges"),
        ("kernel privilege", "Kernel", "Kernel-Level Access"),
    ]

    GAP_PATTERNS: List[Tuple[str, str, str]] = [
        ("scalability limitation", "Scalability", "Scalability Bottleneck"),
        ("future work", "OpenProblem", "Identified Future Work"),
        ("open challenge", "OpenProblem", "Open Security Challenge"),
        ("not addressed", "ResidualRisk", "Unaddressed Residual Risk"),
        ("unaddressed", "ResidualRisk", "Unaddressed Residual Risk"),
        ("limitation of our", "Limitation", "Scope and Model Limitation"),
        ("bypass our defense", "ResidualRisk", "Potential Defense Bypass"),
    ]

    RULE_PATTERNS: List[Tuple[str, str]] = [
        ("semgrep", "Semgrep"),
        ("sigma rule", "Sigma"),
        ("yara", "YARA"),
        ("snort", "Snort"),
        ("suricata", "Suricata"),
        ("codeql", "CodeQL"),
    ]

    VENUE_PATTERNS: List[Tuple[str, str, str, str]] = [
        ("ieee s&p", "IEEESP", "IEEE Symposium on Security and Privacy", "Tier-1"),
        ("oakland", "IEEESP", "IEEE Symposium on Security and Privacy", "Tier-1"),
        ("usenix sec", "USENIXSEC", "USENIX Security Symposium", "Tier-1"),
        (
            "acm ccs",
            "ACMCCS",
            "ACM Conference on Computer and Communications Security",
            "Tier-1",
        ),
        ("ndss", "NDSS", "Network and Distributed System Security Symposium", "Tier-1"),
        ("iacr", "IACR", "IACR Cryptology ePrint Archive", "Tier-2"),
        (
            "raid",
            "RAID",
            "International Symposium on Research in Attacks, Intrusions and Defenses",
            "Tier-2",
        ),
        (
            "acsac",
            "ACSAC",
            "Annual Computer Security Applications Conference",
            "Tier-2",
        ),
        ("arxiv", "ARXIV", "arXiv.org Open Pre-print Archive", "Preprint"),
    ]

    @classmethod
    def _match_access_preconditions(
        cls, text_lower: str, clean_id: str
    ) -> List[PreconditionEntity]:
        """Matches access patterns to Precondition entities."""
        entities: List[PreconditionEntity] = []
        seen: Set[str] = set()
        for keyword, access_level, display_name in cls.ACCESS_PATTERNS:
            if keyword in text_lower and access_level not in seen:
                seen.add(access_level)
                safe_tag = access_level.lower().replace("-", "")
                p_id = f"Precondition:{safe_tag}:{clean_id}"
                entities.append(
                    PreconditionEntity(
                        id=p_id,
                        entity_type=EntityType.PRECONDITION,
                        name=f"{display_name} ({clean_id})",
                        precondition_id=f"{safe_tag}:{clean_id}",
                        access_level=access_level,
                        assumed_knowledge=display_name,
                    )
                )
        return entities

    @classmethod
    def extract_preconditions(
        cls, clean_id: str, text: str, paper_id: str
    ) -> Tuple[List[PreconditionEntity], List[Triple]]:
        """Extracts preconditions and REQUIRES_PRECONDITION triples."""
        text_lower = text.lower()
        entities = cls._match_access_preconditions(text_lower, clean_id)
        triples = [
            Triple(
                subject_id=paper_id,
                predicate=Predicate.REQUIRES_PRECONDITION,
                object_id=ent.id,
            )
            for ent in entities
        ]
        return entities, triples

    @classmethod
    def _create_gap_entity(
        cls, clean_id: str, gap_type: str, display_name: str
    ) -> BaseEntity:
        """Creates ResearchGap or ResidualRisk entity based on category."""
        if gap_type == "ResidualRisk":
            return ResidualRiskEntity(
                id=f"ResidualRisk:{clean_id}",
                entity_type=EntityType.RESIDUAL_RISK,
                name=f"{display_name} in {clean_id}",
                risk_id=clean_id,
                bypass_vector=display_name,
            )
        return ResearchGapEntity(
            id=f"ResearchGap:{gap_type.lower()}:{clean_id}",
            entity_type=EntityType.RESEARCH_GAP,
            name=f"{display_name} ({clean_id})",
            gap_id=f"{gap_type.lower()}:{clean_id}",
            domain=display_name,
        )

    @classmethod
    def _match_gaps(
        cls, text_lower: str, clean_id: str
    ) -> List[Tuple[BaseEntity, Predicate]]:
        """Finds gaps and residual risks in text."""
        results: List[Tuple[BaseEntity, Predicate]] = []
        seen: Set[str] = set()
        for keyword, gap_type, display_name in cls.GAP_PATTERNS:
            if keyword in text_lower and gap_type not in seen:
                seen.add(gap_type)
                ent = cls._create_gap_entity(clean_id, gap_type, display_name)
                pred = (
                    Predicate.LEAVES_UNADDRESSED
                    if gap_type == "ResidualRisk"
                    else Predicate.IDENTIFIES_GAP
                )
                results.append((ent, pred))
        return results

    @classmethod
    def extract_research_gaps(
        cls, clean_id: str, text: str, paper_id: str
    ) -> Tuple[List[BaseEntity], List[Triple]]:
        """Extracts research gaps and residual risks with semantic triples."""
        text_lower = text.lower()
        matched = cls._match_gaps(text_lower, clean_id)
        entities = [ent for ent, _ in matched]
        triples = [
            Triple(subject_id=paper_id, predicate=pred, object_id=ent.id)
            for ent, pred in matched
        ]
        return entities, triples

    @classmethod
    def _extract_poc_artifacts(
        cls, text: str, clean_id: str, paper_id: str
    ) -> Tuple[List[PoCArtifactEntity], List[Triple]]:
        """Extracts GitHub repository links as PoC artifacts."""
        entities: List[PoCArtifactEntity] = []
        triples: List[Triple] = []
        github_match = cls.GITHUB_PATTERN.search(text)
        if github_match:
            repo_path = github_match.group(1).rstrip(".")
            repo_url = f"https://github.com/{repo_path}"
            poc_id = f"PoCArtifact:{clean_id}"
            poc = PoCArtifactEntity(
                id=poc_id,
                entity_type=EntityType.POC_ARTIFACT,
                name=f"PoC Code for {clean_id}",
                artifact_id=clean_id,
                repo_url=repo_url,
                artifact_type="github",
            )
            entities.append(poc)
            triples.append(
                Triple(
                    subject_id=paper_id, predicate=Predicate.HAS_POC, object_id=poc_id
                )
            )
        return entities, triples

    @classmethod
    def _extract_detection_rules(
        cls, text_lower: str, clean_id: str, paper_id: str
    ) -> Tuple[List[DetectionRuleEntity], List[Triple]]:
        """Extracts actionable detection rules from paper content."""
        entities: List[DetectionRuleEntity] = []
        triples: List[Triple] = []
        seen_formats: Set[str] = set()
        for keyword, fmt in cls.RULE_PATTERNS:
            if keyword in text_lower and fmt not in seen_formats:
                seen_formats.add(fmt)
                rule_id = f"DetectionRule:{fmt.lower()}:{clean_id}"
                rule = DetectionRuleEntity(
                    id=rule_id,
                    entity_type=EntityType.DETECTION_RULE,
                    name=f"{fmt} Detection Rule for {clean_id}",
                    rule_id=f"{fmt.lower()}:{clean_id}",
                    rule_format=fmt.lower(),
                    rule_content=f"# Auto-extracted {fmt} signature placeholder",
                )
                entities.append(rule)
                triples.append(
                    Triple(
                        subject_id=paper_id,
                        predicate=Predicate.GENERATES_RULE,
                        object_id=rule_id,
                    )
                )
        return entities, triples

    @classmethod
    def extract_rules_and_pocs(
        cls, clean_id: str, text: str, paper_id: str
    ) -> Tuple[List[BaseEntity], List[Triple]]:
        """Extracts actionable defense rules and PoC repositories."""
        poc_ents, poc_trips = cls._extract_poc_artifacts(text, clean_id, paper_id)
        rule_ents, rule_trips = cls._extract_detection_rules(
            text.lower(), clean_id, paper_id
        )
        all_ents: List[BaseEntity] = list(poc_ents) + list(rule_ents)
        all_trips: List[Triple] = list(poc_trips) + list(rule_trips)
        return all_ents, all_trips

    @classmethod
    def extract_venue(
        cls, clean_id: str, meta: Dict[str, Any], text: str, paper_id: str
    ) -> Tuple[List[PublicationVenueEntity], List[Triple]]:
        """Extracts publication venue and PRESENTED_AT triple."""
        search_target = f"{meta.get('comment', '')} {meta.get('journal_ref', '')} {text[:1000]}".lower()
        for kw, code, display_name, tier in cls.VENUE_PATTERNS:
            if kw in search_target or (code == "IACR" and "iacr" in clean_id):
                venue_id = f"Venue:{code}"
                venue = PublicationVenueEntity(
                    id=venue_id,
                    entity_type=EntityType.PUBLICATION_VENUE,
                    name=display_name,
                    tier=tier,
                )
                triple = Triple(
                    subject_id=paper_id,
                    predicate=Predicate.PRESENTED_AT,
                    object_id=venue_id,
                )
                return [venue], [triple]
        # Default fallback to arXiv
        venue_id = "Venue:ARXIV"
        venue = PublicationVenueEntity(
            id=venue_id,
            entity_type=EntityType.PUBLICATION_VENUE,
            name="arXiv.org Open Pre-print Archive",
            tier="Preprint",
        )
        triple = Triple(
            subject_id=paper_id,
            predicate=Predicate.PRESENTED_AT,
            object_id=venue_id,
        )
        return [venue], [triple]

    IMPACT_PATTERNS: List[Tuple[str, str, str, str]] = [
        (
            "data exfiltration",
            "InformationDisclosure",
            "High",
            "機密データ漏洩・持ち出し",
        ),
        ("data breach", "InformationDisclosure", "High", "情報漏洩・侵害"),
        (
            "privilege escalation",
            "ElevationOfPrivilege",
            "Critical",
            "特権昇格・権限奪取",
        ),
        (
            "arbitrary code execution",
            "ElevationOfPrivilege",
            "Critical",
            "任意コード実行",
        ),
        ("remote code execution", "ElevationOfPrivilege", "Critical", "遠隔コード実行"),
        ("denial of service", "DenialOfService", "High", "サービス拒否・機能停止"),
        ("service disruption", "DenialOfService", "Medium", "サービス中断"),
        ("memory corruption", "Tampering", "High", "メモリ破壊・改ざん"),
        ("integrity violation", "Tampering", "High", "完全性侵害・データ改変"),
        ("spoofing", "Spoofing", "Medium", "なりすまし"),
        ("credential theft", "Spoofing", "High", "認証情報窃取"),
    ]

    INCIDENT_PATTERNS: List[Tuple[str, str, str, str]] = [
        ("solarwinds", "SolarWinds", "2020-12", "Critical"),
        ("log4shell", "Log4Shell", "2021-12", "Critical"),
        ("colonial pipeline", "ColonialPipeline", "2021-05", "Critical"),
        ("stuxnet", "Stuxnet", "2010-06", "Critical"),
        ("wannacry", "WannaCry", "2017-05", "High"),
        ("heartbleed", "Heartbleed", "2014-04", "High"),
        ("spectre", "Spectre", "2018-01", "High"),
        ("meltdown", "Meltdown", "2018-01", "High"),
    ]

    @classmethod
    def extract_impacts_and_causality(
        cls,
        clean_id: str,
        text: str,
        paper_id: str,
        tech_entities: List[BaseEntity],
        defense_entities: List[BaseEntity],
        precondition_entities: List[BaseEntity],
    ) -> Tuple[List[ImpactEntity], List[Triple]]:
        """Extracts STRIDE Impact entities and causality triples."""
        text_lower = text.lower()
        entities: List[ImpactEntity] = []
        triples: List[Triple] = []
        seen_impacts: Set[str] = set()

        for kw, stride_cat, severity, label_ja in cls.IMPACT_PATTERNS:
            if kw in text_lower:
                if stride_cat in seen_impacts:
                    continue
                seen_impacts.add(stride_cat)
                imp_id = f"Impact:{clean_id}:{stride_cat}"
                impact = ImpactEntity(
                    id=imp_id,
                    entity_type=EntityType.IMPACT,
                    name=f"{stride_cat} ({severity}) - {label_ja}",
                    impact_id=f"{clean_id}-{stride_cat}",
                    stride_category=stride_cat,
                    severity=severity,
                )
                entities.append(impact)

                # Link AttackTechniques -> HAS_IMPACT -> Impact (or fallback to Paper)
                if tech_entities:
                    for tech in tech_entities:
                        triples.append(
                            Triple(
                                subject_id=tech.id,
                                predicate=Predicate.HAS_IMPACT,
                                object_id=imp_id,
                                weight=0.9,
                            )
                        )
                else:
                    triples.append(
                        Triple(
                            subject_id=paper_id,
                            predicate=Predicate.HAS_IMPACT,
                            object_id=imp_id,
                            weight=0.8,
                        )
                    )

        # Link DefenseMechanisms -> NEUTRALIZES_PRECONDITION -> Preconditions (or fallback to Paper)
        if precondition_entities:
            if defense_entities:
                for dm in defense_entities:
                    for pre in precondition_entities:
                        triples.append(
                            Triple(
                                subject_id=dm.id,
                                predicate=Predicate.NEUTRALIZES_PRECONDITION,
                                object_id=pre.id,
                                weight=0.85,
                            )
                        )
            elif "neutraliz" in text_lower or "defen" in text_lower:
                for pre in precondition_entities:
                    triples.append(
                        Triple(
                            subject_id=paper_id,
                            predicate=Predicate.NEUTRALIZES_PRECONDITION,
                            object_id=pre.id,
                            weight=0.75,
                        )
                    )

        return entities, triples

    @classmethod
    def extract_claims_and_evidence(
        cls,
        clean_id: str,
        text: str,
        meta: Dict[str, Any],
        paper_id: str,
        tech_entities: List[BaseEntity],
    ) -> Tuple[List[BaseEntity], List[Triple]]:
        """Extracts Claim and EvaluationResult entities and connects them to Paper and Techniques."""
        entities: List[BaseEntity] = []
        triples: List[Triple] = []

        # 1. Main Research Claim
        claim_id = f"Claim:{clean_id}:Proposition"
        title = meta.get("title", f"Paper {clean_id}")
        claim = ClaimEntity(
            id=claim_id,
            entity_type=EntityType.CLAIM,
            name=f"Proposition of {clean_id}",
            claim_id=f"claim-{clean_id}",
            description=f"Core security assertion/defense proposed in: {title}",
            claim_type=(
                "DefenseEfficacy" if "defense" in text.lower() else "AttackDiscovery"
            ),
        )
        entities.append(claim)
        triples.append(
            Triple(
                subject_id=paper_id,
                predicate=Predicate.ASSERTS_CLAIM,
                object_id=claim_id,
                weight=1.0,
            )
        )

        # 2. Reified Evaluation Result (Evidence)
        text_lower = text.lower()
        success_rate = 95.0
        acc_match = re.search(
            r"(\d{1,3}(?:\.\d+)?)\s*%\s*(?:accuracy|success|precision|recall|detection)",
            text_lower,
        )
        if acc_match:
            try:
                success_rate = float(acc_match.group(1))
            except ValueError:
                pass

        env = "General Computing"
        for env_kw, env_name in [
            ("cloud", "Cloud/Kubernetes"),
            ("kernel", "Linux Kernel"),
            ("sgx", "Intel SGX Enclave"),
            ("android", "Android OS"),
            ("docker", "Container"),
            ("firmware", "Embedded/IoT Firmware"),
        ]:
            if env_kw in text_lower:
                env = env_name
                break

        eval_id = f"EvaluationResult:{clean_id}:Empirical"
        evaluation = EvaluationResultEntity(
            id=eval_id,
            entity_type=EntityType.EVALUATION_RESULT,
            name=f"Empirical Evaluation ({success_rate}% on {env})",
            evaluation_id=f"eval-{clean_id}",
            metric_name="SuccessRate",
            value=success_rate,
            success_rate=success_rate,
            target_environment=env,
        )
        entities.append(evaluation)

        # Triples: Paper -> YIELDS_EVALUATION -> EvaluationResult
        triples.append(
            Triple(
                subject_id=paper_id,
                predicate=Predicate.YIELDS_EVALUATION,
                object_id=eval_id,
                weight=1.0,
            )
        )
        # Triples: EvaluationResult -> EVALUATES_CLAIM -> Claim
        triples.append(
            Triple(
                subject_id=eval_id,
                predicate=Predicate.EVALUATES_CLAIM,
                object_id=claim_id,
                weight=0.95,
            )
        )
        # Triples: EvaluationResult -> EVALUATES_TECHNIQUE -> AttackTechnique
        for tech in tech_entities:
            triples.append(
                Triple(
                    subject_id=eval_id,
                    predicate=Predicate.EVALUATES_TECHNIQUE,
                    object_id=tech.id,
                    weight=0.9,
                )
            )

        return entities, triples

    @classmethod
    def extract_incidents(
        cls,
        clean_id: str,
        text: str,
        paper_id: str,
        tech_entities: List[BaseEntity],
        vuln_entities: List[BaseEntity],
    ) -> Tuple[List[IncidentEntity], List[Triple]]:
        """Extracts Incident entities and couples them with techniques and vulnerabilities."""
        text_lower = text.lower()
        entities: List[IncidentEntity] = []
        triples: List[Triple] = []

        for kw, inc_name, occurred_at, severity in cls.INCIDENT_PATTERNS:
            if kw in text_lower:
                inc_id = f"Incident:{inc_name}"
                incident = IncidentEntity(
                    id=inc_id,
                    entity_type=EntityType.INCIDENT,
                    name=f"Real-World Incident: {inc_name} ({occurred_at})",
                    incident_id=inc_name,
                    occurred_at=occurred_at,
                    severity=severity,
                )
                entities.append(incident)

                # AttackTechnique -> EXPLOITED_IN -> Incident
                for tech in tech_entities:
                    triples.append(
                        Triple(
                            subject_id=tech.id,
                            predicate=Predicate.EXPLOITED_IN,
                            object_id=inc_id,
                            weight=0.95,
                        )
                    )

                # Incident -> LEVERAGED_VULNERABILITY -> Vulnerability
                for vuln in vuln_entities:
                    triples.append(
                        Triple(
                            subject_id=inc_id,
                            predicate=Predicate.LEVERAGED_VULNERABILITY,
                            object_id=vuln.id,
                            weight=0.9,
                        )
                    )

        return entities, triples
