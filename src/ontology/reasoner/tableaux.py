"""
Pure Python Tableau / Hypertableau Algorithm Engine.
Implements branch-pruning Tableau calculus with subset blocking and clash detection.
Tracks HermiT's deterministic-first strategy and Pellet's dependency clash logging.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

from ontology.reasoner.ast_nodes import (
    AtomicConcept,
    BottomConcept,
    ComplementConcept,
    Concept,
    DisjointClassesAxiom,
    ExistentialRestriction,
    IntersectionConcept,
    SubClassOfAxiom,
    UnionConcept,
    UniversalRestriction,
)
from ontology.reasoner.base import Clash, ClashType


@dataclass
class TableauNode:
    """Represents a node in the Tableau completion tree."""

    node_id: str
    concepts: Set[Concept] = field(default_factory=set)
    parent_id: Optional[str] = None
    is_blocked: bool = False

    def add_concept(self, concept: Concept) -> bool:
        """Adds a concept to the node label. Returns True if newly added."""
        if concept in self.concepts:
            return False
        self.concepts.add(concept)
        return True


@dataclass
class TableauGraph:
    """Represents the completion forest (nodes, role edges, axioms)."""

    nodes: Dict[str, TableauNode] = field(default_factory=dict)
    edges: Dict[Tuple[str, str], Set[str]] = field(
        default_factory=dict
    )  # (src, dst) -> {roles}
    disjoint_axioms: List[DisjointClassesAxiom] = field(default_factory=list)
    subclass_axioms: List[SubClassOfAxiom] = field(default_factory=list)
    clashes: List[Clash] = field(default_factory=list)
    _node_counter: int = 0

    def get_or_create_node(
        self, node_id: str, parent_id: Optional[str] = None
    ) -> TableauNode:
        """Retrieves or instantiates a TableauNode."""
        if node_id not in self.nodes:
            self.nodes[node_id] = TableauNode(node_id=node_id, parent_id=parent_id)
        return self.nodes[node_id]

    def create_fresh_node(self, parent_id: str) -> TableauNode:
        """Creates a fresh anonymous individual node for existential quantification."""
        self._node_counter += 1
        node_id = f"anon_node_{self._node_counter}"
        node = TableauNode(node_id=node_id, parent_id=parent_id)
        self.nodes[node_id] = node
        return node

    def add_edge(self, src: str, role: str, dst: str) -> None:
        """Adds a directed role edge between individuals."""
        key = (src, dst)
        if key not in self.edges:
            self.edges[key] = set()
        self.edges[key].add(role)

    def clone(self) -> TableauGraph:
        """Deep clones the graph state for disjunctive branching and backtracking."""
        new_g = TableauGraph(
            disjoint_axioms=list(self.disjoint_axioms),
            subclass_axioms=list(self.subclass_axioms),
            clashes=list(self.clashes),
            _node_counter=self._node_counter,
        )
        for nid, node in self.nodes.items():
            new_g.nodes[nid] = TableauNode(
                node_id=node.node_id,
                concepts=set(node.concepts),
                parent_id=node.parent_id,
                is_blocked=node.is_blocked,
            )
        for edge_key, roles in self.edges.items():
            new_g.edges[edge_key] = set(roles)
        return new_g


class TableauEngine:
    """Core Tableau / Hypertableau reasoner providing consistency checks and subsumption."""

    @classmethod
    def is_concept_satisfiable(
        cls,
        concept: Concept,
        subclass_axioms: Optional[List[SubClassOfAxiom]] = None,
        disjoint_axioms: Optional[List[DisjointClassesAxiom]] = None,
        root_node_id: Optional[str] = None,
    ) -> Tuple[bool, List[Clash]]:
        """Determines if a concept is logically satisfiable (consistent)."""
        graph = TableauGraph(
            subclass_axioms=subclass_axioms or [],
            disjoint_axioms=disjoint_axioms or [],
        )
        node_id = root_node_id or "root_ind"
        root = graph.get_or_create_node(node_id)
        root.add_concept(concept)

        is_sat, resulting_graph = cls._expand_and_search(graph)
        return is_sat, resulting_graph.clashes

    @classmethod
    def _saturate_deterministic(cls, graph: TableauGraph) -> Optional[Clash]:
        """Saturates deterministic rules and detects clashes."""
        changed = True
        while changed:
            changed = cls._apply_deterministic_rules(graph)
            clash = cls._detect_clash(graph)
            if clash:
                return clash
        return None

    @classmethod
    def _expand_and_search(cls, graph: TableauGraph) -> Tuple[bool, TableauGraph]:
        """Runs deterministic saturation followed by non-deterministic disjunctive branching."""
        clash = cls._saturate_deterministic(graph)
        if clash:
            graph.clashes.append(clash)
            return False, graph

        branch_cand = cls._find_unexpanded_union(graph)
        if not branch_cand:
            return True, graph

        return cls._search_branches(graph, branch_cand[0], branch_cand[1])

    @classmethod
    def _search_branches(
        cls, graph: TableauGraph, node_id: str, union_concept: UnionConcept
    ) -> Tuple[bool, TableauGraph]:
        """Explores disjunctive branches with backtracking."""
        for option in union_concept.operands:
            branch_graph = graph.clone()
            branch_node = branch_graph.nodes[node_id]
            branch_node.add_concept(option)
            is_sat, final_g = cls._expand_and_search(branch_graph)
            if is_sat:
                return True, final_g
        return False, graph

    @classmethod
    def _apply_deterministic_rules(cls, graph: TableauGraph) -> bool:
        """Applies deterministic rules (conjunction, subclass, universal, existential)."""
        cls._apply_blocking(graph)
        changed = False
        for node in list(graph.nodes.values()):
            if not node.is_blocked and cls._apply_node_rules(node, graph):
                changed = True
        return changed

    @classmethod
    def _apply_node_rules(cls, node: TableauNode, graph: TableauGraph) -> bool:
        """Evaluates deterministic expansion rules for a single unblocked node."""
        c1 = cls._apply_intersection_rule(node)
        c2 = cls._apply_subclass_rule(node, graph.subclass_axioms)
        c3 = cls._apply_universal_rule(node, graph)
        c4 = cls._apply_existential_rule(node, graph)
        return c1 or c2 or c3 or c4

    @staticmethod
    def _apply_intersection_rule(node: TableauNode) -> bool:
        """Applies ⊓-Rule: x : C ⊓ D ==> x : C, x : D."""
        added = False
        for c in list(node.concepts):
            if isinstance(c, IntersectionConcept):
                for op in c.operands:
                    if node.add_concept(op):
                        added = True
        return added

    @staticmethod
    def _apply_subclass_rule(node: TableauNode, axioms: List[SubClassOfAxiom]) -> bool:
        """Applies TBox SubClassOf expansion: x : C and C ⊑ D ==> x : D."""
        added = False
        for ax in axioms:
            if ax.sub_concept in node.concepts:
                if node.add_concept(ax.super_concept):
                    added = True
        return added

    @classmethod
    def _apply_universal_rule(cls, node: TableauNode, graph: TableauGraph) -> bool:
        """Applies ∀-Rule: x : ∀R.C and (x, R, y) ==> y : C."""
        added = False
        for c in list(node.concepts):
            if isinstance(c, UniversalRestriction):
                if cls._propagate_universal(node.node_id, c, graph):
                    added = True
        return added

    @staticmethod
    def _add_filler_to_target(graph: TableauGraph, dst: str, filler: Concept) -> bool:
        """Adds filler concept to destination node if present."""
        dst_node = graph.nodes.get(dst)
        return dst_node.add_concept(filler) if dst_node else False

    @classmethod
    def _propagate_universal(
        cls, src_id: str, restriction: UniversalRestriction, graph: TableauGraph
    ) -> bool:
        """Propagates universal filler to matching edge targets."""
        added = False
        prop = restriction.property_name
        filler = restriction.filler
        for (src, dst), roles in graph.edges.items():
            if src == src_id and prop in roles:
                if cls._add_filler_to_target(graph, dst, filler):
                    added = True
        return added

    @classmethod
    def _apply_existential_rule(cls, node: TableauNode, graph: TableauGraph) -> bool:
        """Applies ∃-Rule: x : ∃R.C ==> create fresh y, (x, R, y), y : C."""
        for c in list(node.concepts):
            if isinstance(c, ExistentialRestriction):
                if not cls._has_role_filler(node, c.property_name, c.filler, graph):
                    new_node = graph.create_fresh_node(parent_id=node.node_id)
                    new_node.add_concept(c.filler)
                    graph.add_edge(node.node_id, c.property_name, new_node.node_id)
                    return True
        return False

    @staticmethod
    def _has_role_filler(
        node: TableauNode, role: str, filler: Concept, graph: TableauGraph
    ) -> bool:
        """Checks if an existing role edge already satisfies the existential constraint."""
        return any(
            role in roles and filler in graph.nodes[dst].concepts
            for (src, dst), roles in graph.edges.items()
            if src == node.node_id and dst in graph.nodes
        )

    @classmethod
    def _apply_blocking(cls, graph: TableauGraph) -> None:
        """Applies subset/equality ancestor blocking to prevent infinite tree growth."""
        for node in graph.nodes.values():
            if node.parent_id is None:
                continue
            ancestor = cls._find_blocking_ancestor(node, graph)
            node.is_blocked = ancestor is not None

    @classmethod
    def _find_blocking_ancestor(
        cls, node: TableauNode, graph: TableauGraph
    ) -> Optional[TableauNode]:
        """Finds an ancestor node whose concept label is a superset of node's label."""
        curr_id = node.parent_id
        while curr_id:
            ancestor = graph.nodes.get(curr_id)
            if ancestor and node.concepts.issubset(ancestor.concepts):
                return ancestor
            curr_id = ancestor.parent_id if ancestor else None
        return None

    @classmethod
    def _find_unexpanded_union(
        cls, graph: TableauGraph
    ) -> Optional[Tuple[str, UnionConcept]]:
        """Finds an unexpanded union concept C ⊔ D for disjunctive branching."""
        for node in graph.nodes.values():
            if not node.is_blocked:
                u = cls._find_union_in_node(node)
                if u:
                    return node.node_id, u
        return None

    @staticmethod
    def _find_union_in_node(node: TableauNode) -> Optional[UnionConcept]:
        """Finds first unsatisfied union in node concepts."""
        for c in node.concepts:
            if isinstance(c, UnionConcept):
                if not any(op in node.concepts for op in c.operands):
                    return c
        return None

    @classmethod
    def _detect_clash(cls, graph: TableauGraph) -> Optional[Clash]:
        """Detects contradictions (atomic, bottom, or disjoint classes) across nodes."""
        for node in graph.nodes.values():
            bottom_clash = cls._check_bottom_concept(node)
            if bottom_clash:
                return bottom_clash

            atomic_clash = cls._check_atomic_complement(node)
            if atomic_clash:
                return atomic_clash

            disjoint_clash = cls._check_disjoint_violation(node, graph.disjoint_axioms)
            if disjoint_clash:
                return disjoint_clash

        return None

    @staticmethod
    def _check_bottom_concept(node: TableauNode) -> Optional[Clash]:
        """Detects if owl:Nothing (BottomConcept) was inferred in the node."""
        for c in node.concepts:
            if isinstance(c, BottomConcept):
                return Clash(
                    clash_type=ClashType.BOTTOM_CONCEPT,
                    node_id=node.node_id,
                    conflicting_concepts=(c.to_manchester(),),
                    justification_axioms=("BottomConceptDerived",),
                    explanation_message=f"Node '{node.node_id}' contains owl:Nothing (⊥).",
                )
        return None

    @staticmethod
    def _extract_negated_atomic_names(node: TableauNode) -> Set[str]:
        """Extracts class names occurring as negated atomics (not A)."""
        names: Set[str] = set()
        for c in node.concepts:
            if isinstance(c, ComplementConcept) and isinstance(
                c.concept, AtomicConcept
            ):
                names.add(c.concept.name)
        return names

    @classmethod
    def _check_atomic_complement(cls, node: TableauNode) -> Optional[Clash]:
        """Detects atomic complement clashes (A and ¬A in the same node)."""
        atomic_names = {c.name for c in node.concepts if isinstance(c, AtomicConcept)}
        neg_names = cls._extract_negated_atomic_names(node)
        conflicts = atomic_names.intersection(neg_names)
        if not conflicts:
            return None
        name = next(iter(conflicts))
        return Clash(
            clash_type=ClashType.ATOMIC_CONTRADICTION,
            node_id=node.node_id,
            conflicting_concepts=(name, f"(not {name})"),
            justification_axioms=("AtomicComplementContradiction",),
            explanation_message=(
                f"Node '{node.node_id}' asserts both '{name}' "
                f"and '(not {name})' simultaneously."
            ),
        )

    @classmethod
    def _check_disjoint_violation(
        cls, node: TableauNode, axioms: List[DisjointClassesAxiom]
    ) -> Optional[Clash]:
        """Detects violation of DisjointClasses axioms."""
        for ax in axioms:
            clash = cls._check_single_disjoint_axiom(node, ax)
            if clash:
                return clash
        return None

    @staticmethod
    def _check_single_disjoint_axiom(
        node: TableauNode, ax: DisjointClassesAxiom
    ) -> Optional[Clash]:
        """Checks a single disjoint classes axiom against a node's label."""
        overlapping = [c for c in ax.classes if c in node.concepts]
        if len(overlapping) >= 2:
            labels = tuple(c.to_manchester() for c in overlapping)
            return Clash(
                clash_type=ClashType.DISJOINT_CLASSES,
                node_id=node.node_id,
                conflicting_concepts=labels,
                justification_axioms=(ax.to_manchester(),),
                explanation_message=(
                    f"Node '{node.node_id}' simultaneously belongs to disjoint classes: "
                    f"{', '.join(labels)} under axiom '{ax.to_manchester()}'."
                ),
            )
        return None
