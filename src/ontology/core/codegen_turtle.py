#!/usr/bin/env python3
"""
Turtle Code Generator Visitor.
Compiles an OntologyDocumentNode AST into standard W3C RDF 1.1 Turtle (.ttl) format.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

from typing import Any, Dict, List

from .ast import (
    AxiomNode,
    AxiomType,
    ClassNode,
    DatatypePropertyNode,
    InstanceNode,
    MetadataNode,
    ObjectPropertyNode,
    OntologyDocumentNode,
)
from .interpreter import ASTVisitor, OntologyInterpreter


class TurtleCodeGenerator(ASTVisitor):
    """
    Visitor compiling ontology AST nodes into standard Turtle (.ttl) representation.
    """

    def __init__(self, prefixes: Dict[str, str]) -> None:
        self.prefixes = dict(prefixes)
        self.header_lines: List[str] = []
        self.metadata_lines: List[str] = []
        self.class_lines: List[str] = []
        self.property_lines: List[str] = []
        self.axiom_lines: List[str] = []
        self.instance_lines: List[str] = []

    def _render_prefixes(self) -> None:
        """Renders standard sorted @prefix declarations."""
        self.header_lines.clear()
        for p, uri in sorted(self.prefixes.items()):
            p_col = f"{p}:"
            self.header_lines.append(f"@prefix {p_col:<6} <{uri}> .")

    def visit_metadata(self, node: MetadataNode) -> None:
        """Renders owl:Ontology metadata header."""
        self._render_prefixes()
        lines: List[str] = [
            "",
            "### --------------------------------------------------",
            "### オントロジー メタデータ",
            "### --------------------------------------------------",
            f"<{node.uri}>",
            "    rdf:type owl:Ontology ;",
        ]
        if node.label:
            lines.append(f'    rdfs:label "{node.label}"@ja ;')
        if node.comment:
            lines.append(f'    rdfs:comment "{node.comment}"@ja ;')
        lines.append(f'    owl:versionInfo "{node.version_info}" .')
        self.metadata_lines = lines

    def visit_class(self, node: ClassNode) -> None:
        """Renders owl:Class definition."""
        lines: List[str] = [
            f"{node.uri} rdf:type owl:Class ;",
        ]
        if node.sub_class_of:
            lines.append(f"    rdfs:subClassOf {node.sub_class_of} ;")
        if node.label:
            lines.append(f'    rdfs:label "{node.label}"@ja ;')
        if node.comment:
            lines.append(f'    rdfs:comment "{node.comment}"@ja ;')
        lines[-1] = lines[-1].rstrip(" ;") + " ."
        self.class_lines.extend(lines)
        self.class_lines.append("")

    def _render_object_prop_modifiers(
        self, node: ObjectPropertyNode, lines: List[str]
    ) -> None:
        """Renders inverse, transitive, and symmetric modifiers."""
        if node.inverse_of:
            lines.append(f"    owl:inverseOf {node.inverse_of} ;")
        if node.is_transitive:
            lines.append("    rdf:type owl:TransitiveProperty ;")
        if node.is_symmetric:
            lines.append("    rdf:type owl:SymmetricProperty ;")

    def visit_object_property(self, node: ObjectPropertyNode) -> None:
        """Renders owl:ObjectProperty definition."""
        lines: List[str] = [
            f"{node.uri} rdf:type owl:ObjectProperty ;",
        ]
        if node.label:
            lines.append(f'    rdfs:label "{node.label}"@ja ;')
        if node.comment:
            lines.append(f'    rdfs:comment "{node.comment}"@ja ;')
        if node.domain:
            lines.append(f"    rdfs:domain {node.domain} ;")
        if node.range_:
            lines.append(f"    rdfs:range {node.range_} ;")
        self._render_object_prop_modifiers(node, lines)
        lines[-1] = lines[-1].rstrip(" ;") + " ."
        self.property_lines.extend(lines)
        self.property_lines.append("")

    def visit_datatype_property(self, node: DatatypePropertyNode) -> None:
        """Renders owl:DatatypeProperty definition."""
        lines: List[str] = [
            f"{node.uri} rdf:type owl:DatatypeProperty ;",
        ]
        if node.label:
            lines.append(f'    rdfs:label "{node.label}"@ja ;')
        if node.comment:
            lines.append(f'    rdfs:comment "{node.comment}"@ja ;')
        if node.domain:
            lines.append(f"    rdfs:domain {node.domain} ;")
        if node.range_:
            lines.append(f"    rdfs:range {node.range_} ;")
        lines[-1] = lines[-1].rstrip(" ;") + " ."
        self.property_lines.extend(lines)
        self.property_lines.append("")

    def visit_axiom(self, node: AxiomNode) -> None:
        """Renders standalone ontology axioms (e.g. disjointWith)."""
        if node.axiom_type == AxiomType.DISJOINT:
            self.axiom_lines.append(
                f"{node.subject_uri} owl:disjointWith {node.target_uri} ."
            )

    @staticmethod
    def _format_instance_object(obj: Any) -> str:
        """Formats an instance statement object."""
        if (
            isinstance(obj, str)
            and not obj.startswith("sec:")
            and not obj.startswith("ex:")
        ):
            return f'"{obj}"'
        return str(obj)

    def visit_instance(self, node: InstanceNode) -> None:
        """Renders an ABox individual instance."""
        lines: List[str] = [f"{node.uri}"]
        for t in node.rdf_types:
            lines.append(f"    rdf:type {t} ;")
        for pred, obj in node.statements:
            rendered_obj = self._format_instance_object(obj)
            lines.append(f"    {pred} {rendered_obj} ;")
        lines[-1] = lines[-1].rstrip(" ;") + " ."
        self.instance_lines.extend(lines)
        self.instance_lines.append("")

    def generate(self) -> str:
        """Combines all generated sections into complete Turtle string."""
        sections: List[List[str]] = [
            self.header_lines,
            self.metadata_lines,
            [
                "",
                "### --------------------------------------------------",
                "### 1. クラス（概念）の定義",
                "### --------------------------------------------------",
            ],
            self.class_lines,
            [
                "### --------------------------------------------------",
                "### 2. プロパティ（関係・属性）の定義",
                "### --------------------------------------------------",
            ],
            self.property_lines,
        ]
        if self.axiom_lines:
            sections.append(
                [
                    "### --------------------------------------------------",
                    "### 3. 公理・制約の定義",
                    "### --------------------------------------------------",
                ]
            )
            sections.append(self.axiom_lines)
        if self.instance_lines:
            sections.append(
                [
                    "### --------------------------------------------------",
                    "### 4. インスタンス実体の定義",
                    "### --------------------------------------------------",
                ]
            )
            sections.append(self.instance_lines)

        flattened: List[str] = []
        for sec in sections:
            flattened.extend(sec)
        return "\n".join(flattened).strip() + "\n"

    @classmethod
    def compile_document(cls, doc: OntologyDocumentNode) -> str:
        """Convenience method to compile an AST document node directly to Turtle."""
        gen = cls(prefixes=doc.prefixes)
        interpreter = OntologyInterpreter(doc)
        interpreter.interpret(gen)
        return gen.generate()
