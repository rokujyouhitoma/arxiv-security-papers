#!/usr/bin/env python3
"""
Ontology AST Parser.
Parses decorated Python classes into an in-memory OntologyDocumentNode AST.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

from typing import Any, Dict, Iterable, List, Optional, Type

from .ast import (
    AxiomNode,
    AxiomType,
    ClassNode,
    DatatypePropertyNode,
    MetadataNode,
    ObjectPropertyNode,
    OntologyDocumentNode,
)
from .dsl import (
    ClassDeclaration,
    DatatypePropertyField,
    ObjectPropertyField,
    PropertyField,
)


class OntologyParser:
    """
    Constructs an OntologyDocumentNode AST from Python classes decorated with @ontology_class.
    """

    def __init__(
        self,
        base_uri: str,
        label: str = "",
        comment: str = "",
        version_info: str = "1.0.0",
        prefixes: Optional[Dict[str, str]] = None,
    ) -> None:
        self.doc = OntologyDocumentNode(
            metadata=MetadataNode(
                uri=base_uri,
                label=label,
                comment=comment,
                version_info=version_info,
            ),
            prefixes=dict(prefixes or {}),
        )

    def _parse_object_property(
        self, class_uri: str, prop: ObjectPropertyField
    ) -> ObjectPropertyNode:
        """Parses an ObjectPropertyField into an ObjectPropertyNode."""
        prop_uri = prop.uri or prop.name
        return ObjectPropertyNode(
            uri=prop_uri,
            label=prop.label or prop.name,
            comment=prop.comment,
            domain=class_uri,
            range_=prop.range,
            is_functional=prop.is_functional,
            inverse_of=prop.inverse_of,
            is_transitive=prop.is_transitive,
            is_symmetric=prop.is_symmetric,
        )

    def _parse_datatype_property(
        self, class_uri: str, prop: DatatypePropertyField
    ) -> DatatypePropertyNode:
        """Parses a DatatypePropertyField into a DatatypePropertyNode."""
        prop_uri = prop.uri or prop.name
        return DatatypePropertyNode(
            uri=prop_uri,
            label=prop.label or prop.name,
            comment=prop.comment,
            domain=class_uri,
            range_=prop.range,
            is_functional=prop.is_functional,
        )

    def _register_object_prop(
        self, class_uri: str, prop: ObjectPropertyField, uri: str
    ) -> None:
        """Registers an object property if not present."""
        if uri not in self.doc.object_properties:
            self.doc.object_properties[uri] = self._parse_object_property(
                class_uri, prop
            )

    def _register_datatype_prop(
        self, class_uri: str, prop: DatatypePropertyField, uri: str
    ) -> None:
        """Registers a datatype property if not present."""
        if uri not in self.doc.datatype_properties:
            self.doc.datatype_properties[uri] = self._parse_datatype_property(
                class_uri, prop
            )

    def _register_property_field(
        self, class_uri: str, prop: PropertyField, declared: List[str]
    ) -> None:
        """Dispatches and registers a single property field into AST."""
        prop_uri = prop.uri or prop.name
        declared.append(prop_uri)
        if isinstance(prop, ObjectPropertyField):
            self._register_object_prop(class_uri, prop, prop_uri)
        elif isinstance(prop, DatatypePropertyField):
            self._register_datatype_prop(class_uri, prop, prop_uri)

    def _register_axioms(self, meta: ClassDeclaration) -> None:
        """Generates subclass and disjointness axioms for a class declaration."""
        if meta.sub_class_of:
            self.doc.axioms.append(
                AxiomNode(
                    axiom_type=AxiomType.SUBCLASS,
                    subject_uri=meta.uri,
                    target_uri=meta.sub_class_of,
                )
            )
        for disj in meta.disjoint_with:
            self.doc.axioms.append(
                AxiomNode(
                    axiom_type=AxiomType.DISJOINT,
                    subject_uri=meta.uri,
                    target_uri=disj,
                )
            )

    def parse_class(self, cls: Type[Any]) -> Optional[ClassNode]:
        """Parses a single Python class into AST ClassNode."""
        meta: Optional[ClassDeclaration] = getattr(cls, "_ontology_meta", None)
        if meta is None:
            return None

        declared: List[str] = []
        for prop in meta.fields.values():
            self._register_property_field(meta.uri, prop, declared)

        node = ClassNode(
            uri=meta.uri,
            label=meta.label,
            comment=meta.comment,
            sub_class_of=meta.sub_class_of,
            disjoint_with=list(meta.disjoint_with),
            declared_properties=declared,
        )
        self.doc.classes[meta.uri] = node
        self._register_axioms(meta)
        return node

    def parse_classes(self, classes: Iterable[Type[Any]]) -> OntologyDocumentNode:
        """Parses an iterable collection of Python ontology classes into the AST."""
        for c in classes:
            self.parse_class(c)
        return self.doc
