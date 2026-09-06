#!/usr/bin/env python3
"""
Unit tests for Core Ontology DSL Parser and Semantic Validator.
Zero security domain logic; verifies pure generic DSL declarations and validation rules.
"""

from __future__ import annotations

from ontology.core.ast import (
    AxiomNode,
    AxiomType,
    ClassNode,
    MetadataNode,
    ObjectPropertyNode,
    OntologyDocumentNode,
)
from ontology.core.dsl import DatatypePropertyField, ObjectPropertyField, ontology_class
from ontology.core.parser import OntologyParser
from ontology.core.validator import DiagnosticSeverity, SemanticValidator


# Sample generic domain using pure Python DSL
@ontology_class(
    uri="org:Organization",
    label="組織",
    comment="A generic organization entity.",
    sub_class_of="owl:Thing",
)
class Organization:
    org_name = DatatypePropertyField(
        uri="org:name",
        label="組織名",
        range="xsd:string",
        is_functional=True,
    )


@ontology_class(
    uri="org:Employee",
    label="従業員",
    comment="An employee of an organization.",
    sub_class_of="owl:Thing",
)
class Employee:
    works_for = ObjectPropertyField(
        uri="org:worksFor",
        label="所属する",
        range="org:Organization",
        inverse_of="org:employs",
    )
    employs = ObjectPropertyField(
        uri="org:employs",
        label="雇用する",
        range="org:Employee",
        inverse_of="org:worksFor",
    )
    emp_id = DatatypePropertyField(
        uri="org:employeeId",
        label="社員ID",
        range="xsd:string",
        is_functional=True,
    )


def test_parser_extracts_classes_and_properties() -> None:
    """Tests that OntologyParser extracts classes and fields correctly."""
    parser = OntologyParser(
        base_uri="https://example.org/org",
        label="Organization Ontology",
        comment="Test DSL parser",
        version_info="1.0.0",
        prefixes={
            "org": "https://example.org/org#",
            "xsd": "http://www.w3.org/2001/XMLSchema#",
        },
    )
    doc = parser.parse_classes([Organization, Employee])

    assert len(doc.classes) == 2
    assert "org:Organization" in doc.classes
    assert "org:Employee" in doc.classes

    assert len(doc.object_properties) == 2
    assert "org:worksFor" in doc.object_properties
    assert "org:employs" in doc.object_properties

    assert len(doc.datatype_properties) == 2
    assert "org:name" in doc.datatype_properties
    assert "org:employeeId" in doc.datatype_properties


def test_validator_clean_pass() -> None:
    """Tests that a well-formed model passes validation with 0 errors."""
    parser = OntologyParser(
        base_uri="https://example.org/org",
        prefixes={
            "org": "https://example.org/org#",
            "xsd": "http://www.w3.org/2001/XMLSchema#",
        },
    )
    doc = parser.parse_classes([Organization, Employee])
    diagnostics = SemanticValidator.validate(doc)
    errors = [d for d in diagnostics if d.severity == DiagnosticSeverity.ERROR]
    assert len(errors) == 0


def test_validator_detects_self_disjointness() -> None:
    """Tests that disjointness between a class and itself is caught as ERROR."""
    meta = MetadataNode(uri="https://example.org/test")
    doc = OntologyDocumentNode(
        metadata=meta,
        prefixes={},
        classes={"ex:Item": ClassNode(uri="ex:Item")},
        axioms=[
            AxiomNode(
                axiom_type=AxiomType.DISJOINT,
                subject_uri="ex:Item",
                target_uri="ex:Item",
            )
        ],
    )
    diagnostics = SemanticValidator.validate(doc)
    errors = [d for d in diagnostics if d.severity == DiagnosticSeverity.ERROR]
    assert len(errors) >= 1
    assert "disjoint with itself" in errors[0].message


def test_validator_detects_cyclic_inheritance() -> None:
    """Tests that circular inheritance (A -> B -> A) is caught as ERROR."""
    meta = MetadataNode(uri="https://example.org/test")
    doc = OntologyDocumentNode(
        metadata=meta,
        prefixes={},
        classes={
            "ex:A": ClassNode(uri="ex:A", sub_class_of="ex:B"),
            "ex:B": ClassNode(uri="ex:B", sub_class_of="ex:A"),
        },
    )
    diagnostics = SemanticValidator.validate(doc)
    errors = [d for d in diagnostics if d.severity == DiagnosticSeverity.ERROR]
    assert len(errors) >= 1
    assert any("Cyclic inheritance" in e.message for e in errors)


def test_validator_warns_on_missing_inverse() -> None:
    """Tests warning when an object property declares inverse_of that is not defined."""
    meta = MetadataNode(uri="https://example.org/test")
    doc = OntologyDocumentNode(
        metadata=meta,
        prefixes={},
        classes={"ex:Person": ClassNode(uri="ex:Person")},
        object_properties={
            "ex:parentOf": ObjectPropertyNode(
                uri="ex:parentOf",
                domain="ex:Person",
                range_="ex:Person",
                inverse_of="ex:childOf",  # ex:childOf is not declared!
            )
        },
    )
    diagnostics = SemanticValidator.validate(doc)
    warnings = [d for d in diagnostics if d.severity == DiagnosticSeverity.WARNING]
    assert len(warnings) >= 1
    assert any("undeclared property" in w.message for w in warnings)
