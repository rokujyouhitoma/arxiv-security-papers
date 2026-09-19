#!/usr/bin/env python3
"""Unit tests for ontology.export multi-format graph serializer.

Tests cover:
- W3C Turtle (.ttl) serialization correctness
- W3C JSON-LD 1.1 serialization correctness
- OASIS STIX 2.1 Bundle JSON serialization correctness
- GraphExporter.export() facade dispatch
- Invalid format handling
"""

from __future__ import annotations

import json
import unittest

from graph.engine import PropertyGraphEngine
from ontology.export import (
    GraphExporter,
    JSONLDSerializer,
    STIXSerializer,
    TurtleSerializer,
)


def _build_test_engine() -> PropertyGraphEngine:
    """Returns an in-memory PropertyGraphEngine populated with test data."""
    engine = PropertyGraphEngine(memory_only=True)

    # Vertices
    engine.add_vertex(
        "2401.00001",
        label="Paper",
        properties={
            "title": "Adversarial Attacks on LLM Agents",
            "abstract": "We study prompt injection vulnerabilities in LLM-based agents.",
            "arxiv_id": "2401.00001",
            "published": "2024-01-01T00:00:00Z",
            "tags": ["adversarial-ml", "llm-security"],
        },
    )
    engine.add_vertex(
        "T1566",
        label="AttackTechnique",
        properties={
            "name": "Phishing",
            "description": "MITRE ATT&CK T1566 Phishing technique.",
            "tags": ["initial-access"],
        },
    )
    engine.add_vertex(
        "CWE-20",
        label="Vulnerability",
        properties={
            "name": "Improper Input Validation",
            "description": "CWE-20: The product does not validate input properly.",
        },
    )
    engine.add_vertex(
        "COA-001",
        label="DefenseMechanism",
        properties={
            "name": "Input Sanitization",
            "description": "Sanitize all untrusted input before processing.",
        },
    )

    # Edges
    engine.add_edge("2401.00001", "T1566", label="DESCRIBES")
    engine.add_edge("T1566", "CWE-20", label="EXPLOITS")
    engine.add_edge("COA-001", "CWE-20", label="MITIGATES")

    return engine


class TestTurtleSerializer(unittest.TestCase):
    """Tests for W3C RDF 1.1 Turtle serialization."""

    def setUp(self) -> None:
        self._engine = _build_test_engine()
        self._ttl = TurtleSerializer(self._engine).serialize()

    def test_prefix_declarations_present(self) -> None:
        """Turtle output must include all expected @prefix declarations."""
        self.assertIn("@prefix rdf:", self._ttl)
        self.assertIn("@prefix rdfs:", self._ttl)
        self.assertIn("@prefix owl:", self._ttl)
        self.assertIn("@prefix sec:", self._ttl)
        self.assertIn("@prefix xsd:", self._ttl)

    def test_base_declaration_present(self) -> None:
        """Turtle output must include @base declaration."""
        self.assertIn("@base", self._ttl)

    def test_vertex_class_triple(self) -> None:
        """Each vertex should produce an 'a <class>' triple."""
        self.assertIn("a sec:Paper", self._ttl)
        self.assertIn("a sec:AttackTechnique", self._ttl)
        self.assertIn("a sec:Vulnerability", self._ttl)
        self.assertIn("a sec:DefenseMechanism", self._ttl)

    def test_edge_predicate_triple(self) -> None:
        """Edge labels must appear as Turtle predicates."""
        self.assertIn("sec:describes", self._ttl)
        self.assertIn("sec:exploits", self._ttl)
        self.assertIn("sec:mitigates", self._ttl)

    def test_rdfs_label_triple(self) -> None:
        """Vertices must have rdfs:label triples."""
        self.assertIn("rdfs:label", self._ttl)

    def test_no_absolute_filesystem_paths(self) -> None:
        """Output must not contain absolute filesystem paths."""
        self.assertNotIn("/workspace/", self._ttl)
        self.assertNotIn("/root/", self._ttl)

    def test_output_is_non_empty(self) -> None:
        """Serialization must produce non-empty output."""
        self.assertGreater(len(self._ttl.strip()), 0)


class TestJSONLDSerializer(unittest.TestCase):
    """Tests for W3C JSON-LD 1.1 serialization."""

    def setUp(self) -> None:
        self._engine = _build_test_engine()
        self._jsonld_str = JSONLDSerializer(self._engine).serialize()
        self._doc = json.loads(self._jsonld_str)

    def test_context_present(self) -> None:
        """JSON-LD document must include @context key."""
        self.assertIn("@context", self._doc)

    def test_vocab_in_context(self) -> None:
        """@context must include @vocab."""
        self.assertIn("@vocab", self._doc["@context"])

    def test_graph_key_present(self) -> None:
        """JSON-LD document must include @graph key."""
        self.assertIn("@graph", self._doc)

    def test_graph_contains_nodes(self) -> None:
        """@graph must contain nodes for all vertices."""
        graph = self._doc["@graph"]
        ids = [n.get("@id", "") for n in graph]
        self.assertTrue(any("Paper" in i or "2401_00001" in i for i in ids))

    def test_type_annotations_present(self) -> None:
        """Nodes must have @type annotations."""
        graph = self._doc["@graph"]
        typed = [n for n in graph if "@type" in n]
        self.assertGreater(len(typed), 0)

    def test_statement_sros_present(self) -> None:
        """Edges must appear as rdf:Statement entries in @graph."""
        graph = self._doc["@graph"]
        stmts = [n for n in graph if n.get("@type") == "rdf:Statement"]
        self.assertGreater(len(stmts), 0)

    def test_valid_json(self) -> None:
        """Output must be valid JSON (already tested by setUp, but explicit check)."""
        try:
            json.loads(self._jsonld_str)
        except json.JSONDecodeError as exc:
            self.fail(f"JSON-LD output is not valid JSON: {exc}")


class TestSTIXSerializer(unittest.TestCase):
    """Tests for OASIS STIX 2.1 Bundle JSON serialization."""

    def setUp(self) -> None:
        self._engine = _build_test_engine()
        self._stix_str = STIXSerializer(self._engine).serialize()
        self._bundle = json.loads(self._stix_str)

    def test_bundle_type(self) -> None:
        """Bundle root must have type='bundle'."""
        self.assertEqual(self._bundle.get("type"), "bundle")

    def test_bundle_id_format(self) -> None:
        """Bundle ID must follow STIX type--UUID format."""
        bid = self._bundle.get("id", "")
        self.assertTrue(bid.startswith("bundle--"), f"Bundle ID malformed: {bid}")

    def test_objects_list_present(self) -> None:
        """Bundle must include non-empty 'objects' list."""
        objs = self._bundle.get("objects", [])
        self.assertIsInstance(objs, list)
        self.assertGreater(len(objs), 0)

    def test_paper_mapped_to_report(self) -> None:
        """Paper vertices must be serialized as STIX 'report' SDOs."""
        objs = self._bundle["objects"]
        reports = [o for o in objs if o.get("type") == "report"]
        self.assertGreater(len(reports), 0)

    def test_attack_technique_mapped(self) -> None:
        """AttackTechnique vertices must be serialized as 'attack-pattern'."""
        objs = self._bundle["objects"]
        aps = [o for o in objs if o.get("type") == "attack-pattern"]
        self.assertGreater(len(aps), 0)

    def test_vulnerability_mapped(self) -> None:
        """Vulnerability vertices must be serialized as 'vulnerability'."""
        objs = self._bundle["objects"]
        vulns = [o for o in objs if o.get("type") == "vulnerability"]
        self.assertGreater(len(vulns), 0)

    def test_relationships_sro_present(self) -> None:
        """Edges must be serialized as STIX 'relationship' SROs."""
        objs = self._bundle["objects"]
        rels = [o for o in objs if o.get("type") == "relationship"]
        self.assertGreater(len(rels), 0)

    def test_relationship_refs_valid(self) -> None:
        """Each relationship SRO must have valid source_ref and target_ref."""
        objs = self._bundle["objects"]
        sdo_ids = {o["id"] for o in objs if o.get("type") != "relationship"}
        for rel in objs:
            if rel.get("type") != "relationship":
                continue
            src = rel.get("source_ref", "")
            tgt = rel.get("target_ref", "")
            self.assertIn(src, sdo_ids, f"source_ref '{src}' not found in SDO IDs")
            self.assertIn(tgt, sdo_ids, f"target_ref '{tgt}' not found in SDO IDs")

    def test_spec_version_field(self) -> None:
        """All SDOs must include spec_version='2.1'."""
        objs = self._bundle["objects"]
        for obj in objs:
            if obj.get("type") == "relationship":
                continue
            self.assertEqual(
                obj.get("spec_version"),
                "2.1",
                f"Missing spec_version in {obj.get('type')}",
            )

    def test_valid_json(self) -> None:
        """STIX output must be valid JSON (already tested by setUp, but explicit)."""
        try:
            json.loads(self._stix_str)
        except json.JSONDecodeError as exc:
            self.fail(f"STIX output is not valid JSON: {exc}")


class TestGraphExporterFacade(unittest.TestCase):
    """Tests for the GraphExporter public facade."""

    def setUp(self) -> None:
        self._engine = _build_test_engine()
        self._exporter = GraphExporter(self._engine)

    def test_to_turtle_returns_string(self) -> None:
        result = self._exporter.to_turtle()
        self.assertIsInstance(result, str)
        self.assertGreater(len(result), 0)

    def test_to_jsonld_returns_string(self) -> None:
        result = self._exporter.to_jsonld()
        self.assertIsInstance(result, str)
        self.assertGreater(len(result), 0)

    def test_to_stix_returns_string(self) -> None:
        result = self._exporter.to_stix()
        self.assertIsInstance(result, str)
        self.assertGreater(len(result), 0)

    def test_export_turtle_format(self) -> None:
        content, ct, fname = self._exporter.export("turtle")
        self.assertIn("text/turtle", ct)
        self.assertTrue(fname.endswith(".ttl"))
        self.assertIn("@prefix", content)

    def test_export_ttl_alias(self) -> None:
        """'ttl' must be accepted as an alias for 'turtle'."""
        content, ct, fname = self._exporter.export("ttl")
        self.assertIn("text/turtle", ct)

    def test_export_jsonld_format(self) -> None:
        content, ct, fname = self._exporter.export("jsonld")
        self.assertIn("application/ld+json", ct)
        self.assertTrue(fname.endswith(".jsonld"))
        doc = json.loads(content)
        self.assertIn("@context", doc)

    def test_export_stix_format(self) -> None:
        content, ct, fname = self._exporter.export("stix")
        self.assertIn("application/json", ct)
        self.assertIn("stix", fname)
        bundle = json.loads(content)
        self.assertEqual(bundle["type"], "bundle")

    def test_export_invalid_format_raises_value_error(self) -> None:
        with self.assertRaises(ValueError) as ctx:
            self._exporter.export("invalid_format_xyz")
        self.assertIn("invalid_format_xyz", str(ctx.exception))

    def test_export_case_insensitive(self) -> None:
        """Format string should be case-insensitive."""
        content, ct, fname = self._exporter.export("TURTLE")
        self.assertIn("text/turtle", ct)

    def test_export_stix_alias_stix21(self) -> None:
        """'stix21' must be accepted as an alias for 'stix'."""
        content, ct, fname = self._exporter.export("stix21")
        self.assertIn("application/json", ct)


if __name__ == "__main__":
    unittest.main()
