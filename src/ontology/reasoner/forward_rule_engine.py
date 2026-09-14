"""
Pure Python OWL 2 RL / Datalog Forward Chaining Deduction Engine.
Computes deductive closure (fixpoint) over large-scale ABox triples in polynomial time (PTime).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set, Tuple

from ontology.schema import Predicate, Triple


@dataclass
class RuleEngineConfig:
    """Configuration and axiom constraints for the forward rule engine."""

    transitive_properties: Set[str] = field(default_factory=set)
    inverse_properties: Dict[str, str] = field(default_factory=dict)  # prop -> inv_prop
    sub_properties: Dict[str, Set[str]] = field(
        default_factory=dict
    )  # prop -> {super_props}
    sub_classes: Dict[str, Set[str]] = field(
        default_factory=dict
    )  # class -> {super_classes}
    property_domains: Dict[str, str] = field(
        default_factory=dict
    )  # prop -> domain_class
    property_ranges: Dict[str, str] = field(default_factory=dict)  # prop -> range_class


class ForwardRuleEngine:
    """Evaluates OWL 2 RL inference rules using semi-naive forward-chaining fixpoint."""

    def __init__(self, config: Optional[RuleEngineConfig] = None) -> None:
        self.config = config or RuleEngineConfig()

    def materialize(
        self, triples: List[Triple], max_iterations: int = 20
    ) -> List[Triple]:
        """Runs forward-chaining deduction until a fixpoint is reached."""
        all_triples: Set[Tuple[str, str, str]] = {
            (t.subject_id, self._norm_pred(t.predicate), t.object_id) for t in triples
        }

        iteration = 0
        while iteration < max_iterations:
            iteration += 1
            new_inferred = self._run_single_pass(all_triples)
            if not new_inferred:
                break
            all_triples.update(new_inferred)

        return self._to_triple_objects(all_triples)

    def _run_single_pass(
        self, current: Set[Tuple[str, str, str]]
    ) -> Set[Tuple[str, str, str]]:
        """Executes one deduction pass across all active OWL 2 RL rules."""
        inferred: Set[Tuple[str, str, str]] = set()

        self._eval_transitive_rules(current, inferred)
        self._eval_inverse_rules(current, inferred)
        self._eval_subproperty_rules(current, inferred)
        self._eval_subclass_and_domain_rules(current, inferred)
        self._eval_security_causal_rules(current, inferred)

        return inferred - current

    def _eval_transitive_rules(
        self, current: Set[Tuple[str, str, str]], out: Set[Tuple[str, str, str]]
    ) -> None:
        """Applies TransitiveProperty rule: (x, R, y) and (y, R, z) ==> (x, R, z)."""
        for p in self.config.transitive_properties:
            self._expand_single_transitive(p, current, out)

    @staticmethod
    def _expand_single_transitive(
        p: str, current: Set[Tuple[str, str, str]], out: Set[Tuple[str, str, str]]
    ) -> None:
        """Expands pairs for a single transitive role."""
        adj = ForwardRuleEngine._build_adjacency(p, current)
        for s, mid_nodes in adj.items():
            ForwardRuleEngine._add_transitive_hops(s, p, mid_nodes, adj, out)

    @staticmethod
    def _build_adjacency(
        p: str, current: Set[Tuple[str, str, str]]
    ) -> Dict[str, Set[str]]:
        """Builds adjacency map for a specific role."""
        adj: Dict[str, Set[str]] = {}
        for s, pred, o in current:
            if pred == p:
                adj.setdefault(s, set()).add(o)
        return adj

    @staticmethod
    def _add_transitive_hops(
        s: str,
        p: str,
        mid_nodes: Set[str],
        adj: Dict[str, Set[str]],
        out: Set[Tuple[str, str, str]],
    ) -> None:
        """Adds two-hop transitive closures for node s."""
        for mid in mid_nodes:
            for dest in adj.get(mid, set()):
                if s != dest:
                    out.add((s, p, dest))

    def _eval_inverse_rules(
        self, current: Set[Tuple[str, str, str]], out: Set[Tuple[str, str, str]]
    ) -> None:
        """Applies InverseOf rule: (x, R, y) ==> (y, R_inv, x)."""
        for s, p, o in current:
            inv = self.config.inverse_properties.get(p)
            if inv:
                out.add((o, inv, s))

    def _eval_subproperty_rules(
        self, current: Set[Tuple[str, str, str]], out: Set[Tuple[str, str, str]]
    ) -> None:
        """Applies SubPropertyOf rule: (x, R, y) and R ⊑ S ==> (x, S, y)."""
        for s, p, o in current:
            super_props = self.config.sub_properties.get(p, set())
            for sp in super_props:
                out.add((s, sp, o))

    def _eval_subclass_and_domain_rules(
        self, current: Set[Tuple[str, str, str]], out: Set[Tuple[str, str, str]]
    ) -> None:
        """Applies SubClassOf, Domain, and Range inference rules."""
        for s, p, o in current:
            if p == "rdf:type":
                self._expand_subclasses(s, o, out)
            else:
                self._expand_domain_range(s, p, o, out)

    def _expand_subclasses(
        self, s: str, o: str, out: Set[Tuple[str, str, str]]
    ) -> None:
        """Propagates subClassOf taxonomy to individual types."""
        for sc in self.config.sub_classes.get(o, set()):
            out.add((s, "rdf:type", sc))

    def _expand_domain_range(
        self, s: str, p: str, o: str, out: Set[Tuple[str, str, str]]
    ) -> None:
        """Infers individual types from property domain and range."""
        dom = self.config.property_domains.get(p)
        if dom:
            out.add((s, "rdf:type", dom))
        rng = self.config.property_ranges.get(p)
        if rng:
            out.add((o, "rdf:type", rng))

    @staticmethod
    def _eval_security_causal_rules(
        current: Set[Tuple[str, str, str]], out: Set[Tuple[str, str, str]]
    ) -> None:
        """Applies DL-Safe rule: mitigates(?d, ?a) ^ targets(?a, ?t) ==> defendsAgainst(?d, ?t)."""
        target_map = ForwardRuleEngine._build_target_map(current)
        for d, p, a in current:
            ForwardRuleEngine._link_causal(d, p, a, target_map, out)

    @staticmethod
    def _build_target_map(current: Set[Tuple[str, str, str]]) -> Dict[str, Set[str]]:
        """Maps threat actors to targeted assets."""
        targets: Dict[str, Set[str]] = {}
        for s, p, o in current:
            if "targets" in p.lower():
                targets.setdefault(s, set()).add(o)
        return targets

    @staticmethod
    def _link_causal(
        d: str,
        p: str,
        a: str,
        target_map: Dict[str, Set[str]],
        out: Set[Tuple[str, str, str]],
    ) -> None:
        """Emits defendsAgainst triple when mitigation meets target."""
        if "mitigates" in p.lower() and a in target_map:
            for t in target_map[a]:
                out.add((d, "sec:defendsAgainst", t))

    @staticmethod
    def _norm_pred(pred: Any) -> str:
        """Normalizes predicate enum or string representation."""
        if hasattr(pred, "value"):
            return str(pred.value)
        return str(pred)

    @classmethod
    def _to_triple_objects(cls, raw_triples: Set[Tuple[str, str, str]]) -> List[Triple]:
        """Converts raw string tuples back to Triple domain objects."""
        return [
            Triple(
                subject_id=s,
                predicate=cls._parse_predicate(p),
                object_id=o,
                weight=1.0,
            )
            for s, p, o in raw_triples
        ]

    @staticmethod
    def _parse_predicate(pred_str: str) -> Any:
        """Maps predicate string to Predicate enum if possible, otherwise string."""
        for p in Predicate:
            if p.value == pred_str:
                return p
        return pred_str
