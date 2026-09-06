#!/usr/bin/env python3
"""
Unit tests for Core Ontology AST, Interpreter, and Turtle Code Generator.
Zero security domain logic; purely tests generic ontology engine behavior.
"""

from __future__ import annotations

from ontology.core.ast import (
    AxiomNode,
    AxiomType,
    ClassNode,
    DatatypePropertyNode,
    InstanceNode,
    MetadataNode,
    ObjectPropertyNode,
    OntologyDocumentNode,
)
from ontology.core.codegen_turtle import TurtleCodeGenerator
from ontology.core.interpreter import ASTVisitor, OntologyInterpreter


class NodeCountingVisitor(ASTVisitor):
    """Test visitor that counts visited nodes."""

    def __init__(self) -> None:
        self.metadata_count = 0
        self.class_count = 0
        self.object_prop_count = 0
        self.data_prop_count = 0
        self.axiom_count = 0
        self.instance_count = 0

    def visit_metadata(self, node: MetadataNode) -> None:
        self.metadata_count += 1

    def visit_class(self, node: ClassNode) -> None:
        self.class_count += 1

    def visit_object_property(self, node: ObjectPropertyNode) -> None:
        self.object_prop_count += 1

    def visit_datatype_property(self, node: DatatypePropertyNode) -> None:
        self.data_prop_count += 1

    def visit_axiom(self, node: AxiomNode) -> None:
        self.axiom_count += 1

    def visit_instance(self, node: InstanceNode) -> None:
        self.instance_count += 1


def test_ast_node_creation() -> None:
    """Tests creating individual AST nodes."""
    cls_node = ClassNode(
        uri="ex:Person",
        label="人物",
        comment="A human person.",
        sub_class_of="owl:Thing",
    )
    assert cls_node.uri == "ex:Person"
    assert cls_node.label == "人物"

    obj_prop = ObjectPropertyNode(
        uri="ex:knows",
        label="知っている",
        domain="ex:Person",
        range_="ex:Person",
        inverse_of="ex:knownBy",
        is_transitive=True,
    )
    assert obj_prop.uri == "ex:knows"
    assert obj_prop.is_transitive is True

    data_prop = DatatypePropertyNode(
        uri="ex:age",
        label="年齢",
        domain="ex:Person",
        range_="xsd:integer",
        is_functional=True,
    )
    assert data_prop.uri == "ex:age"
    assert data_prop.is_functional is True

    axiom = AxiomNode(
        axiom_type=AxiomType.DISJOINT,
        subject_uri="ex:Person",
        target_uri="ex:Organization",
    )
    assert axiom.axiom_type == AxiomType.DISJOINT
    assert axiom.subject_uri == "ex:Person"
    assert axiom.target_uri == "ex:Organization"


def test_ontology_interpreter_walk() -> None:
    """Tests that OntologyInterpreter walks all nodes via ASTVisitor."""
    meta = MetadataNode(
        uri="https://example.org/core",
        label="Core Test",
        comment="Test model",
        version_info="1.0.0",
    )
    classes = {
        "ex:A": ClassNode(uri="ex:A"),
        "ex:B": ClassNode(uri="ex:B"),
    }
    obj_props = {
        "ex:relatesTo": ObjectPropertyNode(
            uri="ex:relatesTo", domain="ex:A", range_="ex:B"
        ),
    }
    data_props = {
        "ex:id": DatatypePropertyNode(uri="ex:id", domain="ex:A", range_="xsd:string"),
    }
    axioms = [
        AxiomNode(axiom_type=AxiomType.DISJOINT, subject_uri="ex:A", target_uri="ex:B"),
    ]
    instances = {
        "ex:inst1": InstanceNode(
            uri="ex:inst1",
            rdf_types=["ex:A"],
            statements=[("ex:id", "val1")],
        ),
    }

    doc = OntologyDocumentNode(
        metadata=meta,
        prefixes={
            "ex": "https://example.org#",
            "xsd": "http://www.w3.org/2001/XMLSchema#",
        },
        classes=classes,
        object_properties=obj_props,
        datatype_properties=data_props,
        axioms=axioms,
        instances=instances,
    )

    visitor = NodeCountingVisitor()
    interpreter = OntologyInterpreter(doc)
    interpreter.interpret(visitor)

    assert visitor.metadata_count == 1
    assert visitor.class_count == 2
    assert visitor.object_prop_count == 1
    assert visitor.data_prop_count == 1
    assert visitor.axiom_count == 1
    assert visitor.instance_count == 1


def test_codegen_turtle_output() -> None:
    """Tests TurtleCodeGenerator serializes AST to valid Turtle syntax."""
    meta = MetadataNode(
        uri="https://example.org/test",
        label="Test Schema",
        comment="A sample schema",
        version_info="1.0.0",
    )
    doc = OntologyDocumentNode(
        metadata=meta,
        prefixes={
            "ex": "https://example.org/test#",
            "owl": "http://www.w3.org/2002/07/owl#",
            "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
            "xsd": "http://www.w3.org/2001/XMLSchema#",
        },
        classes={
            "ex:Cat": ClassNode(uri="ex:Cat", label="猫", sub_class_of="owl:Thing"),
            "ex:Dog": ClassNode(uri="ex:Dog", label="犬", sub_class_of="owl:Thing"),
        },
        object_properties={
            "ex:chases": ObjectPropertyNode(
                uri="ex:chases",
                label="追いかける",
                domain="ex:Dog",
                range_="ex:Cat",
            )
        },
        datatype_properties={
            "ex:name": DatatypePropertyNode(
                uri="ex:name",
                label="名前",
                domain="ex:Dog",
                range_="xsd:string",
            )
        },
        axioms=[
            AxiomNode(
                axiom_type=AxiomType.DISJOINT,
                subject_uri="ex:Cat",
                target_uri="ex:Dog",
            )
        ],
        instances={
            "ex:shiba": InstanceNode(
                uri="ex:shiba",
                rdf_types=["ex:Dog"],
                statements=[("ex:name", "Pochi")],
            )
        },
    )

    ttl = TurtleCodeGenerator.compile_document(doc)
    assert "@prefix ex:" in ttl
    assert "<https://example.org/test#> ." in ttl
    assert "<https://example.org/test>" in ttl
    assert "rdf:type owl:Ontology ;" in ttl
    assert "ex:Cat" in ttl
    assert 'rdfs:label "猫"@ja' in ttl
    assert "ex:chases" in ttl
    assert "rdf:type owl:ObjectProperty ;" in ttl
    assert "rdfs:domain ex:Dog ;" in ttl
    assert "rdfs:range ex:Cat" in ttl
    assert "ex:name" in ttl
    assert "rdf:type owl:DatatypeProperty ;" in ttl
    assert "ex:Cat owl:disjointWith ex:Dog ." in ttl
    assert "ex:shiba" in ttl
    assert "rdf:type ex:Dog ;" in ttl
    assert 'ex:name "Pochi"' in ttl
