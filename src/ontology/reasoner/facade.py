"""
Unified Facade for Pure Python OWL Reasoner.
Orchestrates Tableau consistency checks, subsumption tests, and forward-chaining deduction.
"""

from __future__ import annotations

from typing import Dict, List, Optional, Set

from ontology.reasoner.ast_nodes import (
    AtomicConcept,
    ClassAssertionAxiom,
    ComplementConcept,
    DisjointClassesAxiom,
    IntersectionConcept,
    PropertyAssertionAxiom,
    SubClassOfAxiom,
)
from ontology.reasoner.base import AbstractReasoner, Clash, ConsistencyReport
from ontology.reasoner.explanation import InconsistencyExplainer
from ontology.reasoner.forward_rule_engine import ForwardRuleEngine, RuleEngineConfig
from ontology.reasoner.tableaux import TableauEngine
from ontology.schema import Triple


class PureOWLReasoner(AbstractReasoner):
    """High-level reasoner facade coordinating Tableau DL checks and Datalog deduction."""

    def __init__(
        self,
        subclass_axioms: Optional[List[SubClassOfAxiom]] = None,
        disjoint_axioms: Optional[List[DisjointClassesAxiom]] = None,
    ) -> None:
        self.subclass_axioms: List[SubClassOfAxiom] = list(subclass_axioms or [])
        self.disjoint_axioms: List[DisjointClassesAxiom] = list(disjoint_axioms or [])
        self.class_assertions: List[ClassAssertionAxiom] = []
        self.property_assertions: List[PropertyAssertionAxiom] = []
        self.transitive_props: Set[str] = set()
        self.inverse_props: Dict[str, str] = {}
        self.triples_storage: List[Triple] = []

    def add_subclass_axiom(self, sub_class: str, super_class: str) -> None:
        """Declares subClassOf axiom C ⊑ D."""
        self.subclass_axioms.append(
            SubClassOfAxiom(
                sub_concept=AtomicConcept(sub_class),
                super_concept=AtomicConcept(super_class),
            )
        )

    def add_disjoint_classes(self, *class_names: str) -> None:
        """Declares DisjointClasses axiom C ⊓ D ⊑ ⊥."""
        concepts = tuple(AtomicConcept(c) for c in class_names)
        self.disjoint_axioms.append(DisjointClassesAxiom(classes=concepts))

    def add_class_assertion(self, individual: str, class_name: str) -> None:
        """Asserts individual membership a : C."""
        self.class_assertions.append(
            ClassAssertionAxiom(
                individual=individual,
                concept=AtomicConcept(class_name),
            )
        )

    def add_individual_type(self, individual: str, class_name: str) -> None:
        """Convenience alias for add_class_assertion."""
        self.add_class_assertion(individual, class_name)

    def add_inverse_properties(self, prop_a: str, prop_b: str) -> None:
        """Registers inverse role pair R ≡ S⁻."""
        self.inverse_props[prop_a] = prop_b
        self.inverse_props[prop_b] = prop_a

    def add_transitive_property(self, prop_name: str) -> None:
        """Registers transitive property R⁺ ⊑ R."""
        self.transitive_props.add(prop_name)

    def load_triples(self, triples: List[Triple]) -> None:
        """Loads ABox triples into the reasoner knowledge base."""
        self.triples_storage.extend(triples)

    def check_consistency(self) -> ConsistencyReport:
        """Evaluates logical consistency of all TBox classes and ABox assertions."""
        all_clashes: List[Clash] = []
        unsatisfiable: List[str] = []

        # 1. Check ABox individual assertion consistency
        self._check_abox_consistency(all_clashes)

        # 2. Check TBox class satisfiability
        self._check_tbox_satisfiability(unsatisfiable, all_clashes)

        report = ConsistencyReport(
            is_consistent=len(all_clashes) == 0,
            unsatisfiable_classes=unsatisfiable,
            clashes=all_clashes,
        )
        return InconsistencyExplainer.attach_explanation_to_report(report)

    def _collect_individual_classes(self) -> Dict[str, Set[str]]:
        """Aggregates asserted atomic classes by individual."""
        ind_classes: Dict[str, Set[str]] = {}
        for ca in self.class_assertions:
            if isinstance(ca.concept, AtomicConcept):
                ind_classes.setdefault(ca.individual, set()).add(ca.concept.name)
        return ind_classes

    def _check_individual_overlap(
        self, ind: str, classes: Set[str], out_clashes: List[Clash]
    ) -> None:
        """Checks if a single individual violates any disjointness axiom."""
        for ax in self.disjoint_axioms:
            clashes = self._test_disjoint_overlap(ind, classes, ax)
            out_clashes.extend(clashes)

    def _test_disjoint_overlap(
        self, ind: str, classes: Set[str], ax: DisjointClassesAxiom
    ) -> List[Clash]:
        """Tests overlap of atomic classes for a single disjointness axiom."""
        disj_names = {c.name for c in ax.classes if isinstance(c, AtomicConcept)}
        overlap = classes.intersection(disj_names)
        if len(overlap) < 2:
            return []
        return self._run_disjoint_tableau(ind, overlap)

    def _run_disjoint_tableau(self, ind: str, overlap: Set[str]) -> List[Clash]:
        """Runs tableau satisfiability for overlapping disjoint classes."""
        concept = IntersectionConcept(tuple(AtomicConcept(c) for c in overlap))
        is_sat, clashes = TableauEngine.is_concept_satisfiable(
            concept=concept,
            subclass_axioms=self.subclass_axioms,
            disjoint_axioms=self.disjoint_axioms,
            root_node_id=ind,
        )
        return clashes if not is_sat else []

    def _check_abox_consistency(self, out_clashes: List[Clash]) -> None:
        """Validates that individuals do not violate disjointness axioms."""
        ind_classes = self._collect_individual_classes()
        for ind, classes in ind_classes.items():
            self._check_individual_overlap(ind, classes, out_clashes)

    def _collect_tbox_class_names(self) -> Set[str]:
        """Collects unique atomic class names from subclass axioms."""
        names: Set[str] = set()
        for ax in self.subclass_axioms:
            for c in (ax.sub_concept, ax.super_concept):
                if isinstance(c, AtomicConcept):
                    names.add(c.name)
        return names

    def _check_tbox_satisfiability(
        self, out_unsat: List[str], out_clashes: List[Clash]
    ) -> None:
        """Tests each declared class for satisfiability."""
        for name in self._collect_tbox_class_names():
            is_sat, clashes = TableauEngine.is_concept_satisfiable(
                concept=AtomicConcept(name),
                subclass_axioms=self.subclass_axioms,
                disjoint_axioms=self.disjoint_axioms,
            )
            if not is_sat:
                out_unsat.append(name)
                out_clashes.extend(clashes)

    def is_subclass_of(self, sub_class: str, super_class: str) -> bool:
        """Tests subsumption C ⊑ D by checking unsatisfiability of C ⊓ ¬D."""
        test_concept = IntersectionConcept(
            (
                AtomicConcept(sub_class),
                ComplementConcept(AtomicConcept(super_class)),
            )
        )
        is_sat, _ = TableauEngine.is_concept_satisfiable(
            concept=test_concept,
            subclass_axioms=self.subclass_axioms,
            disjoint_axioms=self.disjoint_axioms,
        )
        # If C ⊓ ¬D is unsatisfiable (not satisfiable), then C ⊑ D holds
        return not is_sat

    def materialize_inferences(self) -> int:
        """Executes OWL 2 RL deduction on loaded triples and stores inferred facts."""
        sub_class_map: Dict[str, Set[str]] = {}
        for ax in self.subclass_axioms:
            if isinstance(ax.sub_concept, AtomicConcept) and isinstance(
                ax.super_concept, AtomicConcept
            ):
                sub = ax.sub_concept.name
                sup = ax.super_concept.name
                if sub not in sub_class_map:
                    sub_class_map[sub] = set()
                sub_class_map[sub].add(sup)

        cfg = RuleEngineConfig(
            transitive_properties=self.transitive_props,
            inverse_properties=self.inverse_props,
            sub_classes=sub_class_map,
        )
        engine = ForwardRuleEngine(cfg)
        init_count = len(self.triples_storage)
        deduced = engine.materialize(self.triples_storage)
        self.triples_storage = deduced
        return len(self.triples_storage) - init_count
