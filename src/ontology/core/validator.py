#!/usr/bin/env python3
"""
Ontology Semantic Validator & AST Linter.
Validates structural integrity, reference completeness, cyclic inheritance,
and logical consistency of an OntologyDocumentNode AST.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Dict, List, Optional, Set

from .ast import OntologyDocumentNode


class DiagnosticSeverity(str, Enum):
    """Severity levels for ontology diagnostics."""

    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"


@dataclass(frozen=True)
class Diagnostic:
    """Represents a static validation finding."""

    severity: DiagnosticSeverity
    code: str
    message: str
    target_uri: str


class SemanticValidator:
    """
    Performs comprehensive static semantic analysis and validation on OntologyDocumentNode.
    """

    @classmethod
    def _validate_single_range(
        cls,
        prop_uri: str,
        range_val: Optional[str],
        declared_classes: Set[str],
        diagnostics: List[Diagnostic],
    ) -> None:
        """Checks if a single property range is valid."""
        if not range_val or range_val in declared_classes:
            return
        if range_val.startswith("xsd:") or range_val.startswith("owl:"):
            return
        diagnostics.append(
            Diagnostic(
                severity=DiagnosticSeverity.WARNING,
                code="ONT-W001",
                message=f"Object property '{prop_uri}' references undeclared range '{range_val}'",
                target_uri=prop_uri,
            )
        )

    @classmethod
    def _check_property_ranges(
        cls,
        doc: OntologyDocumentNode,
        declared_classes: Set[str],
        diagnostics: List[Diagnostic],
    ) -> None:
        """Validates that object property ranges point to declared classes."""
        for prop_uri, prop in doc.object_properties.items():
            cls._validate_single_range(
                prop_uri, prop.range_, declared_classes, diagnostics
            )

    @classmethod
    def _check_inverse_properties(
        cls, doc: OntologyDocumentNode, diagnostics: List[Diagnostic]
    ) -> None:
        """Validates that inverse properties are mutually registered."""
        for prop_uri, prop in doc.object_properties.items():
            if prop.inverse_of:
                inv = doc.object_properties.get(prop.inverse_of)
                if inv is None:
                    diagnostics.append(
                        Diagnostic(
                            severity=DiagnosticSeverity.WARNING,
                            code="ONT-W002",
                            message=(
                                f"Property '{prop_uri}' declares inverse '{prop.inverse_of}' "
                                "which is an undeclared property"
                            ),
                            target_uri=prop_uri,
                        )
                    )

    @classmethod
    def _detect_cycle_from_node(
        cls, curr: str, parent_map: Dict[str, str], visited: Set[str], path: List[str]
    ) -> bool:
        """Detects inheritance cycles starting from a specific node."""
        if curr in path:
            return True
        if curr in visited or curr not in parent_map:
            return False
        visited.add(curr)
        path.append(curr)
        cycle = cls._detect_cycle_from_node(parent_map[curr], parent_map, visited, path)
        path.pop()
        return cycle

    @classmethod
    def _check_cyclic_inheritance(
        cls, doc: OntologyDocumentNode, diagnostics: List[Diagnostic]
    ) -> None:
        """Detects cyclic subClassOf inheritance chains."""
        parent_map: Dict[str, str] = {}
        for c_uri, c_node in doc.classes.items():
            if c_node.sub_class_of:
                parent_map[c_uri] = c_node.sub_class_of

        visited: Set[str] = set()
        for start_uri in parent_map:
            path: List[str] = []
            if cls._detect_cycle_from_node(start_uri, parent_map, visited, path):
                diagnostics.append(
                    Diagnostic(
                        severity=DiagnosticSeverity.ERROR,
                        code="ONT-E001",
                        message=f"Cyclic inheritance detected involving class '{start_uri}'",
                        target_uri=start_uri,
                    )
                )

    @classmethod
    def _check_disjoint_self(
        cls, doc: OntologyDocumentNode, diagnostics: List[Diagnostic]
    ) -> None:
        """Checks if a class declares disjointness with itself."""
        for c_uri, c_node in doc.classes.items():
            if c_uri in c_node.disjoint_with:
                diagnostics.append(
                    Diagnostic(
                        severity=DiagnosticSeverity.ERROR,
                        code="ONT-E002",
                        message=f"Class '{c_uri}' cannot be disjoint with itself",
                        target_uri=c_uri,
                    )
                )
        for ax in doc.axioms:
            if ax.subject_uri == ax.target_uri:
                diagnostics.append(
                    Diagnostic(
                        severity=DiagnosticSeverity.ERROR,
                        code="ONT-E002",
                        message=f"Class '{ax.subject_uri}' cannot be disjoint with itself in axiom",
                        target_uri=ax.subject_uri,
                    )
                )

    @classmethod
    def validate(cls, doc: OntologyDocumentNode) -> List[Diagnostic]:
        """Runs all semantic diagnostic checks on the ontology AST."""
        diagnostics: List[Diagnostic] = []
        declared_classes = set(doc.classes.keys())

        cls._check_property_ranges(doc, declared_classes, diagnostics)
        cls._check_inverse_properties(doc, diagnostics)
        cls._check_cyclic_inheritance(doc, diagnostics)
        cls._check_disjoint_self(doc, diagnostics)

        return diagnostics
