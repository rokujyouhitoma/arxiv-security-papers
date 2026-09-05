#!/usr/bin/env python3
"""
Ontology Master Seeder.
Seeds MITRE ATT&CK (Enterprise & ATLAS) and CWE Master Data into PropertyGraphEngine.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import os
from typing import TYPE_CHECKING, Any, Dict, List, Optional, Tuple

from security.cti.registry import MITRECTIRegistry

if TYPE_CHECKING:
    from graph.engine import PropertyGraphEngine

# 1. MITRE ATT&CK Master Definitions
ATTACK_MASTER: List[Dict[str, Any]] = [
    {
        "id": "AttackTechnique:AML.T0054",
        "label": "AttackTechnique",
        "properties": {
            "name": "LLM Prompt Injection",
            "tactic": "Execution, Initial Access",
            "framework": "MITRE ATLAS",
            "url": "https://atlas.mitre.org/techniques/AML.T0054",
            "description": "Adversary crafts inputs to alter LLM behavior or bypass instructions.",
        },
    },
    {
        "id": "AttackTechnique:AML.T0051",
        "label": "AttackTechnique",
        "properties": {
            "name": "LLM Jailbreak",
            "tactic": "Defense Evasion",
            "framework": "MITRE ATLAS",
            "url": "https://atlas.mitre.org/techniques/AML.T0051",
            "description": "Bypassing safety filters and ethical guardrails in generative AI models.",
        },
    },
    {
        "id": "AttackTechnique:AML.T0044",
        "label": "AttackTechnique",
        "properties": {
            "name": "Data Poisoning",
            "tactic": "Persistence, Resource Development",
            "framework": "MITRE ATLAS",
            "url": "https://atlas.mitre.org/techniques/AML.T0044",
            "description": "Contaminating training or fine-tuning data with backdoor triggers or noise.",
        },
    },
    {
        "id": "AttackTechnique:AML.T0018",
        "label": "AttackTechnique",
        "properties": {
            "name": "Backdoor ML Model",
            "tactic": "Persistence",
            "framework": "MITRE ATLAS",
            "url": "https://atlas.mitre.org/techniques/AML.T0018",
            "description": "Implanting covert trigger-activated payload into neural network weights.",
        },
    },
    {
        "id": "AttackTechnique:AML.T0024",
        "label": "AttackTechnique",
        "properties": {
            "name": "Model Inversion / Stealing",
            "tactic": "Collection, Exfiltration",
            "framework": "MITRE ATLAS",
            "url": "https://atlas.mitre.org/techniques/AML.T0024",
            "description": "Reconstructing model parameters or training secrets from query outputs.",
        },
    },
    {
        "id": "AttackTechnique:AML.T0025",
        "label": "AttackTechnique",
        "properties": {
            "name": "Membership Inference",
            "tactic": "Reconnaissance, Discovery",
            "framework": "MITRE ATLAS",
            "url": "https://atlas.mitre.org/techniques/AML.T0025",
            "description": "Inferring whether specific records were part of private training datasets.",
        },
    },
    {
        "id": "AttackTechnique:T1190",
        "label": "AttackTechnique",
        "properties": {
            "name": "Exploit Public-Facing Application",
            "tactic": "Initial Access",
            "framework": "MITRE Enterprise",
            "url": "https://attack.mitre.org/techniques/T1190",
            "description": "Exploiting vulnerabilities in Internet-facing software or web APIs.",
        },
    },
    {
        "id": "AttackTechnique:T1059",
        "label": "AttackTechnique",
        "properties": {
            "name": "Command and Scripting Interpreter",
            "tactic": "Execution",
            "framework": "MITRE Enterprise",
            "url": "https://attack.mitre.org/techniques/T1059",
            "description": "Executing commands via OS shells, interpreters, or PowerShell.",
        },
    },
    {
        "id": "AttackTechnique:T1203",
        "label": "AttackTechnique",
        "properties": {
            "name": "Exploitation for Client Execution",
            "tactic": "Execution",
            "framework": "MITRE Enterprise",
            "url": "https://attack.mitre.org/techniques/T1203",
            "description": "Exploiting software vulnerabilities in client applications via document/media parsers.",
        },
    },
    {
        "id": "AttackTechnique:T1068",
        "label": "AttackTechnique",
        "properties": {
            "name": "Exploitation for Privilege Escalation",
            "tactic": "Privilege Escalation",
            "framework": "MITRE Enterprise",
            "url": "https://attack.mitre.org/techniques/T1068",
            "description": "Elevating privileges from unprivileged user to root/SYSTEM using software flaws.",
        },
    },
    {
        "id": "AttackTechnique:T1195",
        "label": "AttackTechnique",
        "properties": {
            "name": "Supply Chain Compromise",
            "tactic": "Initial Access, Persistence",
            "framework": "MITRE Enterprise",
            "url": "https://attack.mitre.org/techniques/T1195",
            "description": "Tampering with third-party software dependencies, build pipelines, or registries.",
        },
    },
    {
        "id": "AttackTechnique:T1212",
        "label": "AttackTechnique",
        "properties": {
            "name": "Exploitation for Credential Access",
            "tactic": "Credential Access",
            "framework": "MITRE Enterprise",
            "url": "https://attack.mitre.org/techniques/T1212",
            "description": "Accessing credentials by exploiting memory or security subsystem vulnerabilities.",
        },
    },
    {
        "id": "AttackTechnique:T1499",
        "label": "AttackTechnique",
        "properties": {
            "name": "Endpoint Denial of Service",
            "tactic": "Impact",
            "framework": "MITRE Enterprise",
            "url": "https://attack.mitre.org/techniques/T1499",
            "description": "Exhausting system resources to cause service unresponsiveness or crashes.",
        },
    },
    {
        "id": "AttackTechnique:T1588.005",
        "label": "AttackTechnique",
        "properties": {
            "name": "Obtain Exploits",
            "tactic": "Resource Development",
            "framework": "MITRE Enterprise",
            "url": "https://attack.mitre.org/techniques/T1588/005",
            "description": "Acquiring publicly available or private exploit code for offensive deployment.",
        },
    },
]

# 2. CWE Master Definitions
CWE_MASTER: List[Dict[str, Any]] = [
    {
        "id": "Vulnerability:CWE-119",
        "label": "Vulnerability",
        "properties": {
            "name": "Improper Restriction of Memory Operations",
            "abstraction": "Class",
            "url": "https://cwe.mitre.org/data/definitions/119.html",
            "description": "General memory buffer boundary restriction failures.",
        },
    },
    {
        "id": "Vulnerability:CWE-120",
        "label": "Vulnerability",
        "properties": {
            "name": "Buffer Copy without Checking Size (Buffer Overflow)",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/120.html",
            "description": "Classic buffer copy without checking destination buffer size.",
        },
    },
    {
        "id": "Vulnerability:CWE-125",
        "label": "Vulnerability",
        "properties": {
            "name": "Out-of-bounds Read",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/125.html",
            "description": "Reading past buffer boundary leading to information disclosure.",
        },
    },
    {
        "id": "Vulnerability:CWE-787",
        "label": "Vulnerability",
        "properties": {
            "name": "Out-of-bounds Write",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/787.html",
            "description": "Writing past buffer boundary leading to memory corruption or code execution.",
        },
    },
    {
        "id": "Vulnerability:CWE-416",
        "label": "Vulnerability",
        "properties": {
            "name": "Use After Free",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/416.html",
            "description": "Referencing memory location after it has been freed.",
        },
    },
    {
        "id": "Vulnerability:CWE-190",
        "label": "Vulnerability",
        "properties": {
            "name": "Integer Overflow or Wraparound",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/190.html",
            "description": "Arithmetic calculations resulting in unexpected buffer size allocation.",
        },
    },
    {
        "id": "Vulnerability:CWE-20",
        "label": "Vulnerability",
        "properties": {
            "name": "Improper Input Validation",
            "abstraction": "Class",
            "url": "https://cwe.mitre.org/data/definitions/20.html",
            "description": "Root cause class for injection and untrusted input processing.",
        },
    },
    {
        "id": "Vulnerability:CWE-78",
        "label": "Vulnerability",
        "properties": {
            "name": "OS Command Injection",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/78.html",
            "description": "Improper neutralization of special elements in an OS command.",
        },
    },
    {
        "id": "Vulnerability:CWE-89",
        "label": "Vulnerability",
        "properties": {
            "name": "SQL Injection",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/89.html",
            "description": "Improper neutralization of special elements in an SQL query.",
        },
    },
    {
        "id": "Vulnerability:CWE-79",
        "label": "Vulnerability",
        "properties": {
            "name": "Cross-site Scripting (XSS)",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/79.html",
            "description": "Improper neutralization of input during web page generation.",
        },
    },
    {
        "id": "Vulnerability:CWE-94",
        "label": "Vulnerability",
        "properties": {
            "name": "Code Injection",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/94.html",
            "description": "Improper control of generation of code (e.g. eval, template injection).",
        },
    },
    {
        "id": "Vulnerability:CWE-502",
        "label": "Vulnerability",
        "properties": {
            "name": "Deserialization of Untrusted Data",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/502.html",
            "description": "Deserializing untrusted data leading to arbitrary code execution.",
        },
    },
    {
        "id": "Vulnerability:CWE-862",
        "label": "Vulnerability",
        "properties": {
            "name": "Missing Authorization",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/862.html",
            "description": "Software does not perform authorization check for restricted resource.",
        },
    },
    {
        "id": "Vulnerability:CWE-863",
        "label": "Vulnerability",
        "properties": {
            "name": "Incorrect Authorization",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/863.html",
            "description": "Software performs authorization check incorrectly, allowing unauthorized access.",
        },
    },
    {
        "id": "Vulnerability:CWE-327",
        "label": "Vulnerability",
        "properties": {
            "name": "Broken or Risky Cryptographic Algorithm",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/327.html",
            "description": "Use of deprecated or cryptographically weak cipher algorithms.",
        },
    },
    {
        "id": "Vulnerability:CWE-330",
        "label": "Vulnerability",
        "properties": {
            "name": "Insufficiently Random Values",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/330.html",
            "description": "Predictable pseudorandom number generators in cryptographic keys.",
        },
    },
    {
        "id": "Vulnerability:CWE-1255",
        "label": "Vulnerability",
        "properties": {
            "name": "Microarchitectural Side-Channel Information Exposure",
            "abstraction": "Class",
            "url": "https://cwe.mitre.org/data/definitions/1255.html",
            "description": "Spectre, Meltdown, and cache-timing microarchitectural disclosures.",
        },
    },
    {
        "id": "Vulnerability:CWE-1300",
        "label": "Vulnerability",
        "properties": {
            "name": "Improper Protection Against Glitching Attacks",
            "abstraction": "Class",
            "url": "https://cwe.mitre.org/data/definitions/1300.html",
            "description": "Physical voltage or clock glitching leading to security bypass.",
        },
    },
    {
        "id": "Vulnerability:CWE-1426",
        "label": "Vulnerability",
        "properties": {
            "name": "Resource Exhaustion via Model Queries",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/1426.html",
            "description": "Sponge examples causing exponential computation in neural networks.",
        },
    },
    {
        "id": "Vulnerability:CWE-1427",
        "label": "Vulnerability",
        "properties": {
            "name": "Insecure AI Output Handling",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/1427.html",
            "description": "Downstream execution of unvalidated LLM or neural network outputs.",
        },
    },
    {
        "id": "Vulnerability:CWE-1428",
        "label": "Vulnerability",
        "properties": {
            "name": "Model Weight and Training Data Tampering",
            "abstraction": "Base",
            "url": "https://cwe.mitre.org/data/definitions/1428.html",
            "description": "Unauthorized alteration of neural network weights or fine-tuning datasets.",
        },
    },
]

# 3. Standard Cross-mapping Edges (ATT&CK -> CWE and Hierarchy)
STANDARD_EDGES: List[Tuple[str, str, str, float, Dict[str, Any]]] = [
    (
        "AttackTechnique:AML.T0054",
        "Vulnerability:CWE-20",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:AML.T0054",
        "Vulnerability:CWE-1427",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:AML.T0051",
        "Vulnerability:CWE-863",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:AML.T0044",
        "Vulnerability:CWE-1428",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:AML.T0018",
        "Vulnerability:CWE-1428",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:AML.T0024",
        "Vulnerability:CWE-1426",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:T1190",
        "Vulnerability:CWE-89",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:T1190",
        "Vulnerability:CWE-78",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:T1190",
        "Vulnerability:CWE-502",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:T1059",
        "Vulnerability:CWE-78",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:T1059",
        "Vulnerability:CWE-94",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:T1203",
        "Vulnerability:CWE-120",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:T1203",
        "Vulnerability:CWE-416",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:T1068",
        "Vulnerability:CWE-787",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "AttackTechnique:T1499",
        "Vulnerability:CWE-1426",
        "EXPLOITS",
        1.0,
        {"tier": "gold"},
    ),
    (
        "Vulnerability:CWE-120",
        "Vulnerability:CWE-119",
        "SUBCLASS_OF",
        1.0,
        {"tier": "gold"},
    ),
    (
        "Vulnerability:CWE-125",
        "Vulnerability:CWE-119",
        "SUBCLASS_OF",
        1.0,
        {"tier": "gold"},
    ),
    (
        "Vulnerability:CWE-787",
        "Vulnerability:CWE-119",
        "SUBCLASS_OF",
        1.0,
        {"tier": "gold"},
    ),
    (
        "Vulnerability:CWE-78",
        "Vulnerability:CWE-20",
        "SUBCLASS_OF",
        1.0,
        {"tier": "gold"},
    ),
    (
        "Vulnerability:CWE-89",
        "Vulnerability:CWE-20",
        "SUBCLASS_OF",
        1.0,
        {"tier": "gold"},
    ),
    (
        "Vulnerability:CWE-79",
        "Vulnerability:CWE-20",
        "SUBCLASS_OF",
        1.0,
        {"tier": "gold"},
    ),
    (
        "Vulnerability:CWE-94",
        "Vulnerability:CWE-20",
        "SUBCLASS_OF",
        1.0,
        {"tier": "gold"},
    ),
    (
        "Vulnerability:CWE-1427",
        "Vulnerability:CWE-20",
        "SUBCLASS_OF",
        1.0,
        {"tier": "gold"},
    ),
]


def seed_ontology_graph(engine: PropertyGraphEngine) -> Tuple[int, int]:
    """Seeds ATT&CK techniques, CWEs, and standard causality edges into engine."""
    for node in ATTACK_MASTER:
        engine.add_vertex(
            vertex_id=node["id"],
            label=node["label"],
            properties=node["properties"],
        )

    for node in CWE_MASTER:
        engine.add_vertex(
            vertex_id=node["id"],
            label=node["label"],
            properties=node["properties"],
        )

    for src_id, dst_id, label, weight, props in STANDARD_EDGES:
        engine.add_edge(
            src_id=src_id,
            dst_id=dst_id,
            label=label,
            weight=weight,
            properties=props,
        )

    return len(ATTACK_MASTER) + len(CWE_MASTER), len(STANDARD_EDGES)


def _ingest_single_okf_file(
    fpath: str, fname: str, engine: PropertyGraphEngine
) -> Tuple[int, int]:
    """Ingests a single OKF paper file into the graph engine."""
    from ontology.extractor import OntologyExtractor

    if not fname.endswith(".md"):
        return 0, 0
    clean_id = fname.replace(".md", "")
    try:
        with open(fpath, "r", encoding="utf-8") as pf:
            content = pf.read()
        return OntologyExtractor.ingest_paper_to_graph(
            clean_id=clean_id,
            markdown_content=content,
            engine=engine,
        )
    except Exception:
        return 0, 0


def _scan_okf_files(base_dir: str) -> List[Tuple[str, str]]:
    """Gathers all markdown files across date subdirectories."""
    all_files: List[Tuple[str, str]] = []
    for root, _, files in sorted(os.walk(base_dir), reverse=True):
        for fname in sorted(files, reverse=True):
            if fname.endswith(".md"):
                all_files.append((os.path.join(root, fname), fname))
    return all_files


def _process_file_batch(
    files: List[Tuple[str, str]], engine: PropertyGraphEngine, limit: int
) -> Tuple[int, int]:
    """Processes a list of files up to limit."""
    total_ent = 0
    total_trip = 0
    ingested_papers = 0
    for fpath, fname in files:
        ent_c, trip_c = _ingest_single_okf_file(fpath, fname, engine)
        if ent_c > 0:
            total_ent += ent_c
            total_trip += trip_c
            ingested_papers += 1
            if ingested_papers >= limit:
                break
    return total_ent, total_trip


def ingest_okf_papers(
    engine: PropertyGraphEngine,
    okf_dir: Optional[str] = None,
    limit: int = 100,
) -> Tuple[int, int]:
    """Scans and ingests OKF papers into PropertyGraphEngine."""
    base_dir = okf_dir or os.path.join(engine.workspace_dir, "outputs", "okf_papers")
    if not os.path.exists(base_dir):
        return 0, 0
    files = _scan_okf_files(base_dir)
    return _process_file_batch(files, engine, limit)


def _seed_cti_techniques(
    engine: PropertyGraphEngine, registry: MITRECTIRegistry, limit: int
) -> Tuple[int, int]:
    """Seeds CTI attack techniques into graph."""
    added_v = 0
    added_e = 0
    techs = registry.get_all_techniques()
    count = 0
    for tech_id, meta in sorted(techs.items()):
        if count >= limit:
            break
        v_id = f"AttackTechnique:{tech_id}"
        props = {
            "name": meta.get("name", tech_id),
            "framework": "MITRE Enterprise",
            "url": meta.get(
                "external_url", f"https://attack.mitre.org/techniques/{tech_id}"
            ),
            "description": meta.get("description", ""),
        }
        engine.add_vertex(v_id, "AttackTechnique", props)
        added_v += 1
        count += 1

        # Link to parent technique if subtechnique
        parent_id = meta.get("parent_technique_id")
        if parent_id and parent_id != tech_id:
            parent_v = f"AttackTechnique:{parent_id}"
            engine.add_vertex(parent_v, "AttackTechnique", {"name": parent_id})
            engine.add_edge(v_id, parent_v, "SUBTECHNIQUE_OF")
            added_e += 1

    return added_v, added_e


def _seed_single_mitigation(
    engine: PropertyGraphEngine, m: Dict[str, Any], tech_v: str
) -> Tuple[int, int]:
    m_id = m.get("mitigation_id", "")
    if not m_id:
        return 0, 0
    m_v = f"Mitigation:{m_id}"
    engine.add_vertex(
        m_v,
        "Mitigation",
        {
            "name": m.get("name", m_id),
            "description": m.get("description", ""),
            "url": m.get("external_url", ""),
        },
    )
    engine.add_edge(m_v, tech_v, "MITIGATES")
    return 1, 1


def _seed_cti_mitigations(
    engine: PropertyGraphEngine, registry: MITRECTIRegistry, limit: int
) -> Tuple[int, int]:
    """Seeds CTI mitigations and links them to techniques."""
    added_v, added_e, count = 0, 0, 0
    for tech_id in sorted(registry.get_all_techniques().keys()):
        if count >= limit:
            break
        mitigations = registry.get_mitigations_for_technique(tech_id)
        tech_v = f"AttackTechnique:{tech_id}"
        for m in mitigations:
            v_inc, e_inc = _seed_single_mitigation(engine, m, tech_v)
            added_v += v_inc
            added_e += e_inc
        if mitigations:
            count += 1
    return added_v, added_e


def seed_ontology_from_cti(
    engine: PropertyGraphEngine, limit: int = 500
) -> Tuple[int, int]:
    """
    Seeds MITRE ATT&CK CTI techniques, subtechniques, and defensive mitigations
    into PropertyGraphEngine from local SQLite catalog or fallback definitions.
    """
    registry = MITRECTIRegistry.get_instance()
    tv, te = _seed_cti_techniques(engine, registry, limit)
    mv, me = _seed_cti_mitigations(engine, registry, limit)
    return tv + mv, te + me
