"""
Unit and integration tests for Pure Python OWL DL / RL Reasoner.
Verifies Tableau/Hypertableau clash detection, subsumption, blocking, Datalog deduction,
and HermiT/Pellet reference tracking metadata.
"""

from __future__ import annotations

from ontology.reasoner.ast_nodes import (
    AtomicConcept,
    ComplementConcept,
    DisjointClassesAxiom,
    ExistentialRestriction,
    IntersectionConcept,
    SubClassOfAxiom,
)
from ontology.reasoner.base import ClashType
from ontology.reasoner.facade import PureOWLReasoner
from ontology.reasoner.forward_rule_engine import ForwardRuleEngine, RuleEngineConfig
from ontology.reasoner.hermit_pellet_tracker import ReferenceReasonerTracker
from ontology.reasoner.tableaux import TableauEngine
from ontology.schema import Triple


def test_hermit_pellet_reference_tracking() -> None:
    """Verifies that HermiT and Pellet reference profiles are tracked with full architectural metadata."""
    profiles = ReferenceReasonerTracker.get_reference_profiles()
    assert "HermiT" in profiles
    assert "Pellet" in profiles

    hermit = profiles["HermiT"]
    assert "Hypertableau" in hermit["algorithm"]
    assert "2-NEXPTIME" in hermit["complexity"]
    assert len(hermit["optimizations"]) >= 3
    assert "src/ontology/reasoner/tableaux.py" in hermit["pure_python_mapping"]

    pellet = profiles["Pellet"]
    assert "Tableau" in pellet["algorithm"]
    assert "SWRL" in pellet["profile"]
    assert "explanation.py" in pellet["pure_python_mapping"]

    narrative = ReferenceReasonerTracker.get_summary_narrative()
    assert "Pure Python" in narrative
    assert "HermiT" in narrative
    assert "Pellet" in narrative


def test_tableau_atomic_contradiction_clash() -> None:
    """Verifies that asserting A and not A on the same node triggers AtomicContradiction clash."""
    concept = IntersectionConcept(
        (
            AtomicConcept("sec:Malware"),
            ComplementConcept(AtomicConcept("sec:Malware")),
        )
    )
    is_sat, clashes = TableauEngine.is_concept_satisfiable(concept)
    assert not is_sat
    assert len(clashes) >= 1
    assert clashes[0].clash_type == ClashType.ATOMIC_CONTRADICTION
    assert "sec:Malware" in clashes[0].conflicting_concepts


def test_tableau_disjoint_classes_clash() -> None:
    """Verifies that an entity simultaneously in disjoint classes triggers DisjointClasses clash."""
    c_attack = AtomicConcept("sec:AttackTechnique")
    c_defense = AtomicConcept("sec:DefenseMechanism")
    disjoint_ax = DisjointClassesAxiom((c_attack, c_defense))

    concept = IntersectionConcept((c_attack, c_defense))
    is_sat, clashes = TableauEngine.is_concept_satisfiable(
        concept=concept,
        disjoint_axioms=[disjoint_ax],
    )
    assert not is_sat
    assert len(clashes) >= 1
    assert clashes[0].clash_type == ClashType.DISJOINT_CLASSES
    assert "sec:AttackTechnique" in clashes[0].conflicting_concepts
    assert "sec:DefenseMechanism" in clashes[0].conflicting_concepts


def test_tableau_satisfiable_model() -> None:
    """Verifies that consistent concept combinations are satisfiable with zero clashes."""
    concept = IntersectionConcept(
        (
            AtomicConcept("sec:Vulnerability"),
            AtomicConcept("sec:BufferOverflow"),
        )
    )
    is_sat, clashes = TableauEngine.is_concept_satisfiable(concept)
    assert is_sat
    assert len(clashes) == 0


def test_tableau_existential_and_universal_inference() -> None:
    """Verifies that existential role generation interacts correctly with universal role propagation."""
    # Concept: (hasMitigation some (Defense and (not Defense))) -> must be unsatisfiable
    conflict_defense = IntersectionConcept(
        (
            AtomicConcept("sec:Firewall"),
            ComplementConcept(AtomicConcept("sec:Firewall")),
        )
    )
    concept = ExistentialRestriction(
        property_name="sec:hasMitigation",
        filler=conflict_defense,
    )
    is_sat, clashes = TableauEngine.is_concept_satisfiable(concept)
    assert not is_sat
    assert len(clashes) >= 1


def test_tableau_blocking_prevents_infinite_recursion() -> None:
    """Verifies that ancestor subset blocking prevents infinite loops for recursive axioms (A SubClassOf some R A)."""
    c_node = AtomicConcept("sec:SelfReferentialEntity")
    ax = SubClassOfAxiom(
        sub_concept=c_node,
        super_concept=ExistentialRestriction("sec:relatesTo", c_node),
    )
    # Must terminate without recursion error and return satisfiable
    is_sat, clashes = TableauEngine.is_concept_satisfiable(
        concept=c_node,
        subclass_axioms=[ax],
    )
    assert is_sat
    assert len(clashes) == 0


def test_subsumption_reasoning() -> None:
    """Verifies that subsumption C SubClassOf D is proved by unsatisfiability of C and not D."""
    reasoner = PureOWLReasoner()
    reasoner.add_subclass_axiom("sec:Ransomware", "sec:Malware")
    reasoner.add_subclass_axiom("sec:Malware", "sec:CyberThreat")

    # Direct subclass
    assert reasoner.is_subclass_of("sec:Ransomware", "sec:Malware")
    # Transitive subclass
    assert reasoner.is_subclass_of("sec:Ransomware", "sec:CyberThreat")
    # Non-subclass
    assert not reasoner.is_subclass_of("sec:CyberThreat", "sec:Ransomware")


def test_forward_rule_engine_transitive_and_inverse() -> None:
    """Verifies that ForwardRuleEngine expands transitive properties and inverse relationships in PTime."""
    cfg = RuleEngineConfig(
        transitive_properties={"sec:subTechniqueOf"},
        inverse_properties={"sec:mitigates": "sec:isMitigatedBy"},
    )
    engine = ForwardRuleEngine(cfg)

    triples = [
        # Transitive chain: T1 -> T2 -> T3
        Triple("tech:T1059.001", "sec:subTechniqueOf", "tech:T1059"),
        Triple("tech:T1059", "sec:subTechniqueOf", "tech:Execution"),
        # Inverse: D1 mitigates T1
        Triple("def:D1", "sec:mitigates", "tech:T1059.001"),
    ]

    inferred = engine.materialize(triples)
    inferred_set = {(t.subject_id, t.predicate, t.object_id) for t in inferred}

    # Transitive deduction T1 -> T3 must be present
    assert ("tech:T1059.001", "sec:subTechniqueOf", "tech:Execution") in inferred_set
    # Inverse deduction T1 isMitigatedBy D1 must be present
    assert ("tech:T1059.001", "sec:isMitigatedBy", "def:D1") in inferred_set


def test_forward_rule_engine_security_causal() -> None:
    """Verifies DL-Safe causal rule: mitigates(?d, ?a) ^ targets(?a, ?t) ==> defendsAgainst(?d, ?t)."""
    engine = ForwardRuleEngine()
    triples = [
        Triple("def:AppArmor", "sec:mitigates", "threat:PrivilegeEscalation"),
        Triple("threat:PrivilegeEscalation", "sec:targets", "target:LinuxKernel"),
    ]
    inferred = engine.materialize(triples)
    inferred_set = {(t.subject_id, t.predicate, t.object_id) for t in inferred}

    assert ("def:AppArmor", "sec:defendsAgainst", "target:LinuxKernel") in inferred_set


def test_inconsistency_explainer_markdown() -> None:
    """Verifies that InconsistencyExplainer outputs transparent, audit-compliant markdown for detected clashes."""
    reasoner = PureOWLReasoner()
    reasoner.add_disjoint_classes("sec:AttackTechnique", "sec:DefenseMechanism")
    # Assert contradictory types for the same individual
    reasoner.add_class_assertion("entity:DualUseKernelHook", "sec:AttackTechnique")
    reasoner.add_class_assertion("entity:DualUseKernelHook", "sec:DefenseMechanism")

    report = reasoner.check_consistency()
    assert not report.is_consistent
    assert len(report.clashes) >= 1

    expl = report.explanation
    assert "### ⚠️ Logical Inconsistency Audit Report" in expl
    assert "DisjointClasses" in expl
    assert "entity:DualUseKernelHook" in expl
    assert "sec:AttackTechnique" in expl
    assert "sec:DefenseMechanism" in expl
    assert "Audit Remediations" in expl


def test_facade_end_to_end_clean() -> None:
    """Verifies that a fully consistent ontology yields a successful report and materializes inferences."""
    reasoner = PureOWLReasoner()
    reasoner.add_subclass_axiom("sec:ASLR", "sec:ExploitMitigation")
    reasoner.add_subclass_axiom("sec:ExploitMitigation", "sec:DefenseMechanism")
    reasoner.add_transitive_property("sec:subClassOf")

    report = reasoner.check_consistency()
    assert report.is_consistent
    assert len(report.clashes) == 0
    assert "consistent" in report.explanation.lower()

    # Load triples and run materialization
    reasoner.load_triples(
        [
            Triple("def:KASLR", "sec:subClassOf", "sec:ASLR"),
            Triple("sec:ASLR", "sec:subClassOf", "sec:ExploitMitigation"),
        ]
    )
    added = reasoner.materialize_inferences()
    assert added >= 1
    inferred_set = {
        (t.subject_id, t.predicate, t.object_id) for t in reasoner.triples_storage
    }
    assert ("def:KASLR", "sec:subClassOf", "sec:ExploitMitigation") in inferred_set


def test_mcp_check_ontology_consistency() -> None:
    """Verifies MCP threat defense server consistency check tool handler."""
    from mcp.threat_defense_server import handle_check_ontology_consistency

    res = handle_check_ontology_consistency(
        {
            "subclass_axioms": [{"sub": "Ransomware", "super": "Malware"}],
            "disjoint_axioms": [["DeterministicEncryption", "ProbabilisticEncryption"]],
            "individual_assertions": [
                {
                    "individual": "algo:AES_ECB",
                    "classes": ["DeterministicEncryption", "ProbabilisticEncryption"],
                }
            ],
        }
    )
    assert res["status"] == "success"
    assert not res["is_consistent"]
    assert res["clash_count"] >= 1
    assert "HermiT" in res["reference_implementations"]["hermit"]
    assert "Pellet" in res["reference_implementations"]["pellet"]
